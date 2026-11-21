import Foundation

/// Represents a single term in a Folk statement or pattern.
public enum Term: CustomStringConvertible, Equatable {
    case literal(String)
    case variable(String)
    case list([Term])
    case closure(([String: String], FolkEngine.MatchContext) -> Void)
    
    public static func == (lhs: Term, rhs: Term) -> Bool {
        switch (lhs, rhs) {
        case let (.literal(a), .literal(b)):
            return a == b
        case let (.variable(a), .variable(b)):
            return a == b
        case let (.list(a), .list(b)):
            return a == b
        default:
            return false // Closures are not directly comparable
        }
    }
    
    public var description: String {
        switch self {
        case .literal(let s): return s
        case .variable(let name): return "/\(name)/"
        case .list(let list): return "[" + list.map { $0.description }.joined(separator: " ") + "]"
        case .closure: return "<closure>"
        }
    }
    
    /// Parses a string token into a literal or variable.
    public static func parse(_ token: String) -> Term {
        if token.hasPrefix("/") && token.hasSuffix("/") && token.count > 2 {
            let varName = String(token.dropFirst().dropLast())
            return .variable(varName)
        }
        return .literal(token)
    }
}

public final class FolkEngine {
    
    /// A Statement is a tuple of Terms stored in the database.
    public struct Statement: Hashable, Equatable {
        public let id: UUID
        public let terms: [Term]
        public let parentMatchId: UUID?
        
        public func hash(into hasher: inout Hasher) {
            // Hash based on the string descriptions of terms
            hasher.combine(terms.map { $0.description })
        }
        
        public static func == (lhs: Statement, rhs: Statement) -> Bool {
            return lhs.terms == rhs.terms
        }
    }
    
    /// A Match represents a successful join between a query and a claim.
    public final class Match {
        public let id: UUID
        public let whenPattern: [Term]
        public let parentStatements: [Statement]
        public var childStatements: [Statement] = []
        public var destructors: [() -> Void] = []
        
        public init(id: UUID = UUID(), whenPattern: [Term], parentStatements: [Statement]) {
            self.id = id
            self.whenPattern = whenPattern
            self.parentStatements = parentStatements
        }
    }
    
    /// The MatchContext is passed into a When closure, allowing registration of cleanups.
    public final class MatchContext {
        private let onRetractHandler: (@escaping () -> Void) -> Void
        
        init(onRetract: @escaping (@escaping () -> Void) -> Void) {
            self.onRetractHandler = onRetract
        }
        
        public func onRetract(_ destructor: @escaping () -> Void) {
            onRetractHandler(destructor)
        }
    }
    
    private let queue = DispatchQueue(label: "org.folk.engine", attributes: .concurrent)
    private var statements: Set<Statement> = []
    private var matches: [UUID: Match] = [:]
    
    private static let currentMatchKey = "FolkEngine.currentMatchId"
    
    /// Thread-local storage to track nesting and automatically associate
    /// assertions with their parent matches.
    private var currentMatchId: UUID? {
        get { Thread.current.threadDictionary[Self.currentMatchKey] as? UUID }
        set { Thread.current.threadDictionary[Self.currentMatchKey] = newValue }
    }
    
    public init() {}
    
    // MARK: - DSL Methods
    
    /// Asserts a claim in the database.
    public func claim(_ terms: [String]) {
        let parsed = terms.map { Term.parse($0) }
        assert(parsed)
    }
    
    /// Asserts a wish in the database.
    public func wish(_ terms: [String]) {
        var withWish: [Term] = [.literal("wish")]
        withWish.append(contentsOf: terms.map { Term.parse($0) })
        assert(withWish)
    }
    
    /// Registers a reactive block.
    public func when(_ pattern: [String], _ closure: @escaping ([String: String], MatchContext) -> Void) {
        let patternTerms = pattern.map { Term.parse($0) }
        let whenStatement = [
            Term.literal("when"),
            Term.list(patternTerms),
            Term.closure(closure)
        ]
        assert(whenStatement)
    }
    
    /// Retracts any statements matching the exact terms.
    public func retract(_ terms: [String]) {
        let parsed = terms.map { Term.parse($0) }
        queue.async(flags: .barrier) {
            let targets = self.statements.filter { $0.terms == parsed }
            for target in targets {
                self.retractStatementUnsafe(target)
            }
        }
    }
    
    // MARK: - Core Unification & Reaction Logic
    
    private func assert(_ terms: [Term]) {
        let parentMatchId = self.currentMatchId
        queue.async(flags: .barrier) {
            let statement = Statement(id: UUID(), terms: terms, parentMatchId: parentMatchId)
            
            // Avoid duplicate statements
            if self.statements.contains(statement) { return }
            
            self.statements.insert(statement)
            
            if let parentId = parentMatchId, let match = self.matches[parentId] {
                match.childStatements.append(statement)
            }
            
            self.react(to: statement)
        }
    }
    
    private func retractStatementUnsafe(_ statement: Statement) {
        guard statements.contains(statement) else { return }
        statements.remove(statement)
        
        // Find all matches that depend on this statement
        let dependentMatches = matches.values.filter { $0.parentStatements.contains(statement) }
        for match in dependentMatches {
            invalidateMatchUnsafe(match)
        }
    }
    
    private func invalidateMatchUnsafe(_ match: Match) {
        guard matches[match.id] != nil else { return }
        matches.removeValue(forKey: match.id)
        
        // 1. Run all cleanups registered on this match
        for destructor in match.destructors {
            destructor()
        }
        
        // 2. Cascading retraction of all child statements asserted by this match
        for child in match.childStatements {
            retractStatementUnsafe(child)
        }
    }
    
    /// Evaluates existing statements against new queries, or new statements against existing queries.
    private func react(to newStatement: Statement) {
        // Case 1: The new statement is a "When" query
        if newStatement.terms.count == 3,
           case let .literal(op) = newStatement.terms[0], op == "when",
           case let .list(pattern) = newStatement.terms[1],
           case let .closure(closure) = newStatement.terms[2] {
            
            // Scan all existing assertions (not 'when's) that match the pattern
            let activeClaims = statements.filter { stmt in
                if stmt.terms.count > 0, case let .literal(first) = stmt.terms[0], first == "when" {
                    return false
                }
                return true
            }
            
            for claim in activeClaims {
                var bindings: [String: String] = [:]
                if unify(pattern: pattern, statement: claim.terms, bindings: &bindings) {
                    executeMatch(whenStatement: newStatement, matchingStatement: claim, pattern: pattern, bindings: bindings, closure: closure)
                }
            }
        } 
        // Case 2: The new statement is a regular assertion, see if it triggers any registered Whens
        else {
            let activeWhens = statements.filter { stmt in
                stmt.terms.count == 3 &&
                stmt.terms[0] == .literal("when")
            }
            
            for whenStmt in activeWhens {
                guard case let .list(pattern) = whenStmt.terms[1],
                      case let .closure(closure) = whenStmt.terms[2] else { continue }
                
                var bindings: [String: String] = [:]
                if unify(pattern: pattern, statement: newStatement.terms, bindings: &bindings) {
                    executeMatch(whenStatement: whenStmt, matchingStatement: newStatement, pattern: pattern, bindings: bindings, closure: closure)
                }
            }
        }
    }
    
    private func executeMatch(whenStatement: Statement, matchingStatement: Statement, pattern: [Term], bindings: [String: String], closure: @escaping ([String: String], MatchContext) -> Void) {
        let match = Match(whenPattern: pattern, parentStatements: [whenStatement, matchingStatement])
        matches[match.id] = match
        
        let ctx = MatchContext { [weak self, weak match] destructor in
            self?.queue.async(flags: .barrier) {
                match?.destructors.append(destructor)
            }
        }
        
        // Execute the closure inside a thread-local context with match.id active
        let previousMatchId = self.currentMatchId
        self.currentMatchId = match.id
        
        closure(bindings, ctx)
        
        self.currentMatchId = previousMatchId
    }
    
    // MARK: - Unification Helper
    
    private func unify(pattern: [Term], statement: [Term], bindings: inout [String: String]) -> Bool {
        guard pattern.count == statement.count else { return false }
        for (p, s) in zip(pattern, statement) {
            if !unify(pattern: p, statement: s, bindings: &bindings) {
                return false
            }
        }
        return true
    }
    
    private func unify(pattern: Term, statement: Term, bindings: inout [String: String]) -> Bool {
        switch (pattern, statement) {
        case let (.literal(p), .literal(s)):
            return p == s
            
        case let (.variable(pVar), .literal(sLit)):
            bindings[pVar] = sLit
            return true
            
        case let (.variable(pVar), .list(sList)):
            bindings[pVar] = sList.map { $0.description }.joined(separator: " ")
            return true
            
        case let (.list(pList), .list(sList)):
            return unify(pattern: pList, statement: sList, bindings: &bindings)
            
        default:
            return false
        }
    }
    
    // MARK: - Debug Helpers
    
    public func dumpDatabase() {
        queue.sync {
            print("=== Active Claims ===")
            for stmt in statements {
                print("  - ID: \(stmt.id.uuidString.prefix(6))... ParentMatch: \(stmt.parentMatchId?.uuidString.prefix(6) ?? "none") | \(stmt.terms.map { $0.description }.joined(separator: " "))")
            }
            print("=== Matches ===")
            for match in matches.values {
                print("  - Match \(match.id.uuidString.prefix(6)): childCount=\(match.childStatements.count) destructorCount=\(match.destructors.count)")
            }
            print("=====================")
        }
    }
    
    public func activeStatementCount() -> Int {
        queue.sync { statements.count }
    }
}

// MARK: - Self-Contained Test Suite

#if DEBUG
func runEngineTests() {
    print("🚀 Starting FolkEngine Tests...")
    let engine = FolkEngine()
    
    var outlineDrawn = false
    var colorOutlined: String? = nil
    
    // 1. Register a dynamic outlined wish drawing system
    engine.when(["tag", "/id/", "is", "active"]) { bindings, ctx in
        let id = bindings["id"]!
        engine.wish(["tag", id, "is", "outlined", "green"])
    }
    
    engine.when(["wish", "tag", "/id/", "is", "outlined", "/color/"]) { bindings, ctx in
        let id = bindings["id"]!
        let color = bindings["color"]!
        outlineDrawn = true
        colorOutlined = color
        print("🎨 DRAWING OUTLINE: tag \(id) outline \(color)")
        
        ctx.onRetract {
            outlineDrawn = false
            colorOutlined = nil
            print("🧹 CLEANUP: outline for tag \(id) removed.")
        }
    }
    
    // Wait for queue initialization
    Thread.sleep(forTimeInterval: 0.1)
    
    // Database is empty
    assert(engine.activeStatementCount() == 2) // Just the 2 when statements
    
    // 2. Assert that Tag 4 is active
    print("\n--- Asserting Tag 4 is active ---")
    engine.claim(["tag", "4", "is", "active"])
    
    // Wait for async queue
    Thread.sleep(forTimeInterval: 0.1)
    
    // Confirm the outline is drawn and is green
    assert(outlineDrawn == true)
    assert(colorOutlined == "green")
    
    // 3. Retract Tag 4 is active
    print("\n--- Retracting Tag 4 is active ---")
    engine.retract(["tag", "4", "is", "active"])
    
    Thread.sleep(forTimeInterval: 0.1)
    
    // Confirm cascading retraction cleared the outlines
    assert(outlineDrawn == false)
    assert(colorOutlined == nil)
    
    print("\n✅ All FolkEngine tests passed successfully!")
}

// Run the tests
runEngineTests()
#endif
