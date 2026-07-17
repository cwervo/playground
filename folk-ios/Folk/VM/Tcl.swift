// Tcl.swift
// A small Tcl evaluator written in Swift — the core of the Folk "Swift VM".
// Modeled on picol: enough Tcl to run Folk programs (procs, expr, control
// flow, lists, string ops), with no file or network I/O.

import Foundation

struct TclError: Error {
    let message: String
}

enum TclControl: Error {
    case ret(String)
    case brk
    case cont
}

final class TclInterp {

    struct Frame {
        var vars: [String: String] = [:]
        var globalLinks: Set<String> = []
    }

    struct TclProc {
        let params: [[String]]   // each entry: [name] or [name, default]
        let body: String
    }

    typealias Builtin = (TclInterp, [String]) throws -> String

    private(set) var globals: [String: String] = [:]
    private var frames: [Frame] = []
    private var procs: [String: TclProc] = [:]
    private var builtins: [String: Builtin] = [:]

    /// Where `puts` output goes.
    var puts: (String) -> Void = { print($0) }

    /// Guard against runaway loops in user programs.
    var stepLimit = 250_000
    private var steps = 0

    init() {
        registerCore()
    }

    func resetStepBudget() {
        steps = 0
    }

    func register(_ name: String, _ fn: @escaping Builtin) {
        builtins[name] = fn
    }

    // MARK: - Variables

    func getVar(_ name: String) throws -> String {
        if name.hasPrefix("::") {
            let bare = String(name.dropFirst(2))
            if let v = globals[bare] { return v }
            throw TclError(message: "can't read \"\(name)\": no such variable")
        }
        if let frame = frames.last {
            if frame.globalLinks.contains(name), let v = globals[name] { return v }
            if let v = frame.vars[name] { return v }
        } else if let v = globals[name] {
            return v
        }
        throw TclError(message: "can't read \"\(name)\": no such variable")
    }

    func setVar(_ name: String, _ value: String) {
        if name.hasPrefix("::") {
            globals[String(name.dropFirst(2))] = value
            return
        }
        if frames.isEmpty {
            globals[name] = value
        } else if frames[frames.count - 1].globalLinks.contains(name) {
            globals[name] = value
        } else {
            frames[frames.count - 1].vars[name] = value
        }
    }

    func varExists(_ name: String) -> Bool {
        return (try? getVar(name)) != nil
    }

    func unsetVar(_ name: String) {
        if name.hasPrefix("::") {
            globals.removeValue(forKey: String(name.dropFirst(2)))
            return
        }
        if frames.isEmpty {
            globals.removeValue(forKey: name)
        } else {
            frames[frames.count - 1].vars.removeValue(forKey: name)
        }
    }

    private func linkGlobal(_ name: String) {
        if !frames.isEmpty {
            frames[frames.count - 1].globalLinks.insert(name)
        }
    }

    /// Snapshot of every variable visible at the current scope (used by the
    /// Folk layer to capture environments for `When` bodies).
    func visibleVars() -> [String: String] {
        var result = globals
        if let frame = frames.last {
            for (k, v) in frame.vars { result[k] = v }
        }
        return result
    }

    // MARK: - Evaluation

    @discardableResult
    func eval(_ script: String) throws -> String {
        let chars = Array(script)
        var i = 0
        var lastResult = ""
        while i < chars.count {
            steps += 1
            if steps > stepLimit {
                throw TclError(message: "step limit exceeded (possible infinite loop)")
            }
            let words = try parseCommand(chars, &i)
            if words.isEmpty { continue }
            lastResult = try execute(words)
        }
        return lastResult
    }

    func execute(_ words: [String]) throws -> String {
        let name = words[0]
        let args = Array(words.dropFirst())

        if let p = procs[name] {
            return try callProc(name, p, args)
        }
        if let b = builtins[name] {
            return try b(self, args)
        }
        throw TclError(message: "invalid command name \"\(name)\"")
    }

    private func callProc(_ name: String, _ p: TclProc, _ args: [String]) throws -> String {
        var frame = Frame()
        var argIndex = 0
        for (i, param) in p.params.enumerated() {
            let pname = param[0]
            if pname == "args" && i == p.params.count - 1 {
                frame.vars["args"] = TclInterp.formatList(Array(args[min(argIndex, args.count)...]))
                argIndex = args.count
            } else if argIndex < args.count {
                frame.vars[pname] = args[argIndex]
                argIndex += 1
            } else if param.count > 1 {
                frame.vars[pname] = param[1]
            } else {
                throw TclError(message: "wrong # args: should be \"\(name) \(p.params.map { $0[0] }.joined(separator: " "))\"")
            }
        }
        frames.append(frame)
        defer { frames.removeLast() }
        do {
            return try eval(p.body)
        } catch TclControl.ret(let v) {
            return v
        }
    }

    // MARK: - Parser

    /// Parses one command (up to newline/semicolon), performing substitution.
    private func parseCommand(_ chars: [Character], _ i: inout Int) throws -> [String] {
        var words: [String] = []
        while i < chars.count {
            // Skip inter-word whitespace (and escaped newlines).
            while i < chars.count {
                let c = chars[i]
                if c == " " || c == "\t" || c == "\r" {
                    i += 1
                } else if c == "\\" && i + 1 < chars.count && chars[i + 1] == "\n" {
                    i += 2
                } else {
                    break
                }
            }
            if i >= chars.count { break }
            let c = chars[i]
            if c == "\n" || c == ";" {
                i += 1
                break
            }
            if c == "#" && words.isEmpty {
                while i < chars.count && chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "{" {
                words.append(try parseBraced(chars, &i))
            } else if c == "\"" {
                words.append(try parseQuoted(chars, &i))
            } else {
                words.append(try parseBare(chars, &i))
            }
        }
        return words
    }

    private func parseBraced(_ chars: [Character], _ i: inout Int) throws -> String {
        // chars[i] == "{"
        i += 1
        var depth = 1
        var out = ""
        while i < chars.count {
            let c = chars[i]
            if c == "\\" && i + 1 < chars.count {
                out.append(c)
                out.append(chars[i + 1])
                i += 2
                continue
            }
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 {
                    i += 1
                    return out
                }
            }
            out.append(c)
            i += 1
        }
        throw TclError(message: "missing close-brace")
    }

    private func parseQuoted(_ chars: [Character], _ i: inout Int) throws -> String {
        // chars[i] == "\""
        i += 1
        var out = ""
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                i += 1
                return out
            }
            if c == "\\" {
                out.append(try parseEscape(chars, &i))
            } else if c == "$" {
                out.append(try parseVarSubst(chars, &i))
            } else if c == "[" {
                out.append(try parseCmdSubst(chars, &i))
            } else {
                out.append(c)
                i += 1
            }
        }
        throw TclError(message: "missing closing quote")
    }

    private func parseBare(_ chars: [Character], _ i: inout Int) throws -> String {
        var out = ""
        while i < chars.count {
            let c = chars[i]
            if c == " " || c == "\t" || c == "\r" || c == "\n" || c == ";" {
                break
            }
            if c == "\\" {
                out.append(try parseEscape(chars, &i))
            } else if c == "$" {
                out.append(try parseVarSubst(chars, &i))
            } else if c == "[" {
                out.append(try parseCmdSubst(chars, &i))
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }

    private func parseEscape(_ chars: [Character], _ i: inout Int) throws -> String {
        // chars[i] == "\\"
        i += 1
        guard i < chars.count else { return "\\" }
        let c = chars[i]
        i += 1
        switch c {
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        case "\n":
            // Backslash-newline: swallow following whitespace, becomes a space.
            while i < chars.count && (chars[i] == " " || chars[i] == "\t") { i += 1 }
            return " "
        default:
            return String(c)
        }
    }

    private func isVarNameChar(_ c: Character) -> Bool {
        return c.isLetter || c.isNumber || c == "_" || c == ":"
    }

    private func parseVarSubst(_ chars: [Character], _ i: inout Int) throws -> String {
        // chars[i] == "$"
        i += 1
        guard i < chars.count else { return "$" }
        if chars[i] == "{" {
            i += 1
            var name = ""
            while i < chars.count && chars[i] != "}" {
                name.append(chars[i])
                i += 1
            }
            guard i < chars.count else { throw TclError(message: "missing close-brace for variable name") }
            i += 1
            return try getVar(name)
        }
        var name = ""
        while i < chars.count && isVarNameChar(chars[i]) {
            name.append(chars[i])
            i += 1
        }
        if name.isEmpty { return "$" }
        // Trim trailing single colons (e.g. "$x:" — colon belongs to text).
        while name.hasSuffix(":") && !name.hasSuffix("::") {
            name = String(name.dropLast())
            i -= 1
        }
        return try getVar(name)
    }

    private func parseCmdSubst(_ chars: [Character], _ i: inout Int) throws -> String {
        // chars[i] == "["
        i += 1
        var depth = 1
        var braceDepth = 0
        var script = ""
        while i < chars.count {
            let c = chars[i]
            if c == "\\" && i + 1 < chars.count {
                script.append(c)
                script.append(chars[i + 1])
                i += 2
                continue
            }
            if c == "{" { braceDepth += 1 }
            if c == "}" && braceDepth > 0 { braceDepth -= 1 }
            if braceDepth == 0 {
                if c == "[" { depth += 1 }
                if c == "]" {
                    depth -= 1
                    if depth == 0 {
                        i += 1
                        return try eval(script)
                    }
                }
            }
            script.append(c)
            i += 1
        }
        throw TclError(message: "missing close-bracket")
    }

    /// Performs $-substitution and [command]-substitution on a string
    /// (used by `expr` on brace-quoted expressions).
    func substitute(_ s: String) throws -> String {
        let chars = Array(s)
        var i = 0
        var out = ""
        while i < chars.count {
            let c = chars[i]
            if c == "\\" {
                out.append(try parseEscape(chars, &i))
            } else if c == "$" {
                out.append(try parseVarSubst(chars, &i))
            } else if c == "[" {
                out.append(try parseCmdSubst(chars, &i))
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }

    // MARK: - Lists

    static func parseList(_ s: String) -> [String] {
        let chars = Array(s)
        var i = 0
        var items: [String] = []
        while i < chars.count {
            while i < chars.count && chars[i].isWhitespace { i += 1 }
            if i >= chars.count { break }
            var item = ""
            if chars[i] == "{" {
                var depth = 1
                i += 1
                while i < chars.count && depth > 0 {
                    if chars[i] == "\\" && i + 1 < chars.count {
                        item.append(chars[i])
                        item.append(chars[i + 1])
                        i += 2
                        continue
                    }
                    if chars[i] == "{" { depth += 1 }
                    if chars[i] == "}" {
                        depth -= 1
                        if depth == 0 { i += 1; break }
                    }
                    item.append(chars[i])
                    i += 1
                }
            } else if chars[i] == "\"" {
                i += 1
                while i < chars.count && chars[i] != "\"" {
                    if chars[i] == "\\" && i + 1 < chars.count {
                        item.append(chars[i + 1])
                        i += 2
                        continue
                    }
                    item.append(chars[i])
                    i += 1
                }
                if i < chars.count { i += 1 }
            } else {
                while i < chars.count && !chars[i].isWhitespace {
                    if chars[i] == "\\" && i + 1 < chars.count {
                        item.append(chars[i + 1])
                        i += 2
                        continue
                    }
                    item.append(chars[i])
                    i += 1
                }
            }
            items.append(item)
        }
        return items
    }

    static func quoteListItem(_ s: String) -> String {
        if s.isEmpty { return "{}" }
        let needsQuoting = s.contains(where: { $0.isWhitespace || $0 == "{" || $0 == "}" || $0 == "[" || $0 == "]" || $0 == "$" || $0 == "\"" || $0 == ";" })
        if !needsQuoting { return s }
        // Only brace-quote when braces inside are balanced.
        var depth = 0
        var balanced = true
        for c in s {
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth < 0 { balanced = false; break }
            }
        }
        if balanced && depth == 0 {
            return "{" + s + "}"
        }
        var out = ""
        for c in s {
            if c.isWhitespace || c == "{" || c == "}" || c == "[" || c == "]" || c == "$" || c == "\"" || c == "\\" || c == ";" {
                out.append("\\")
            }
            out.append(c)
        }
        return out
    }

    static func formatList(_ items: [String]) -> String {
        return items.map(quoteListItem).joined(separator: " ")
    }

    // MARK: - Core commands

    private func registerCore() {
        register("set") { interp, args in
            guard args.count == 1 || args.count == 2 else {
                throw TclError(message: "wrong # args: should be \"set varName ?newValue?\"")
            }
            if args.count == 2 {
                interp.setVar(args[0], args[1])
                return args[1]
            }
            return try interp.getVar(args[0])
        }

        register("unset") { interp, args in
            for a in args { interp.unsetVar(a) }
            return ""
        }

        register("incr") { interp, args in
            guard args.count == 1 || args.count == 2 else {
                throw TclError(message: "wrong # args: should be \"incr varName ?increment?\"")
            }
            let current = interp.varExists(args[0]) ? (Int(try interp.getVar(args[0])) ?? 0) : 0
            let amount = args.count == 2 ? (Int(args[1]) ?? 0) : 1
            let value = String(current + amount)
            interp.setVar(args[0], value)
            return value
        }

        register("global") { interp, args in
            for a in args { interp.linkGlobal(a) }
            return ""
        }

        register("expr") { interp, args in
            let text = args.joined(separator: " ")
            return try TclExpr.evaluate(try interp.substitute(text))
        }

        register("if") { interp, args in
            var idx = 0
            while idx < args.count {
                let cond = try TclExpr.evaluate(try interp.substitute(args[idx]))
                let truthy = TclExpr.isTrue(cond)
                idx += 1
                var body: String? = nil
                if idx < args.count {
                    if args[idx] == "then" { idx += 1 }
                    body = args[idx]
                    idx += 1
                }
                if truthy {
                    return try interp.eval(body ?? "")
                }
                if idx >= args.count { return "" }
                if args[idx] == "elseif" {
                    idx += 1
                    continue
                }
                if args[idx] == "else" {
                    idx += 1
                    guard idx < args.count else { throw TclError(message: "wrong # args: no script following \"else\"") }
                    return try interp.eval(args[idx])
                }
                // Bare else body.
                return try interp.eval(args[idx])
            }
            return ""
        }

        register("while") { interp, args in
            guard args.count == 2 else {
                throw TclError(message: "wrong # args: should be \"while test command\"")
            }
            while true {
                interp.steps += 1
                if interp.steps > interp.stepLimit {
                    throw TclError(message: "step limit exceeded (possible infinite loop)")
                }
                let cond = try TclExpr.evaluate(try interp.substitute(args[0]))
                if !TclExpr.isTrue(cond) { break }
                do {
                    _ = try interp.eval(args[1])
                } catch TclControl.brk {
                    break
                } catch TclControl.cont {
                    continue
                }
            }
            return ""
        }

        register("for") { interp, args in
            guard args.count == 4 else {
                throw TclError(message: "wrong # args: should be \"for start test next command\"")
            }
            _ = try interp.eval(args[0])
            while true {
                interp.steps += 1
                if interp.steps > interp.stepLimit {
                    throw TclError(message: "step limit exceeded (possible infinite loop)")
                }
                let cond = try TclExpr.evaluate(try interp.substitute(args[1]))
                if !TclExpr.isTrue(cond) { break }
                do {
                    _ = try interp.eval(args[3])
                } catch TclControl.brk {
                    break
                } catch TclControl.cont {
                    // fall through to next
                }
                _ = try interp.eval(args[2])
            }
            return ""
        }

        register("foreach") { interp, args in
            guard args.count == 3 else {
                throw TclError(message: "wrong # args: should be \"foreach varList list body\"")
            }
            let varNames = TclInterp.parseList(args[0])
            let items = TclInterp.parseList(args[1])
            guard !varNames.isEmpty else { return "" }
            var idx = 0
            while idx < items.count {
                for v in varNames {
                    interp.setVar(v, idx < items.count ? items[idx] : "")
                    idx += 1
                }
                do {
                    _ = try interp.eval(args[2])
                } catch TclControl.brk {
                    break
                } catch TclControl.cont {
                    continue
                }
            }
            return ""
        }

        let defineProc: Builtin = { interp, args in
            guard args.count == 3 else {
                throw TclError(message: "wrong # args: should be \"proc name args body\"")
            }
            let params = TclInterp.parseList(args[1]).map { TclInterp.parseList($0) }
            interp.procs[args[0]] = TclProc(params: params.map { $0.isEmpty ? [""] : $0 }, body: args[2])
            return ""
        }
        register("proc", defineProc)
        register("fn", defineProc)   // Folk's alias

        register("return") { _, args in
            throw TclControl.ret(args.first ?? "")
        }
        register("break") { _, _ in throw TclControl.brk }
        register("continue") { _, _ in throw TclControl.cont }

        register("puts") { interp, args in
            // Accept and ignore -nonewline / channel arguments.
            let text = args.last ?? ""
            interp.puts(text)
            return ""
        }

        register("eval") { interp, args in
            return try interp.eval(args.joined(separator: " "))
        }

        register("catch") { interp, args in
            guard args.count == 1 || args.count == 2 else {
                throw TclError(message: "wrong # args: should be \"catch script ?resultVarName?\"")
            }
            do {
                let r = try interp.eval(args[0])
                if args.count == 2 { interp.setVar(args[1], r) }
                return "0"
            } catch let e as TclError {
                if args.count == 2 { interp.setVar(args[1], e.message) }
                return "1"
            } catch TclControl.ret(let v) {
                if args.count == 2 { interp.setVar(args[1], v) }
                return "2"
            }
        }

        register("error") { _, args in
            throw TclError(message: args.first ?? "error")
        }

        register("list") { _, args in
            return TclInterp.formatList(args)
        }

        register("lindex") { _, args in
            guard args.count >= 1 else { throw TclError(message: "wrong # args: should be \"lindex list ?index?\"") }
            var current = args[0]
            for idxArg in args.dropFirst() {
                let items = TclInterp.parseList(current)
                var idx: Int
                if idxArg == "end" {
                    idx = items.count - 1
                } else if idxArg.hasPrefix("end-"), let off = Int(idxArg.dropFirst(4)) {
                    idx = items.count - 1 - off
                } else {
                    idx = Int(idxArg) ?? -1
                }
                guard idx >= 0 && idx < items.count else { return "" }
                current = items[idx]
            }
            return current
        }

        register("llength") { _, args in
            guard args.count == 1 else { throw TclError(message: "wrong # args: should be \"llength list\"") }
            return String(TclInterp.parseList(args[0]).count)
        }

        register("lappend") { interp, args in
            guard args.count >= 1 else { throw TclError(message: "wrong # args: should be \"lappend varName ?value ...?\"") }
            var items = interp.varExists(args[0]) ? TclInterp.parseList(try interp.getVar(args[0])) : []
            items.append(contentsOf: args.dropFirst())
            let value = TclInterp.formatList(items)
            interp.setVar(args[0], value)
            return value
        }

        register("lassign") { interp, args in
            guard args.count >= 2 else { throw TclError(message: "wrong # args: should be \"lassign list varName ?varName ...?\"") }
            let items = TclInterp.parseList(args[0])
            for (i, name) in args.dropFirst().enumerated() {
                interp.setVar(name, i < items.count ? items[i] : "")
            }
            let rest = args.count - 1 < items.count ? Array(items[(args.count - 1)...]) : []
            return TclInterp.formatList(rest)
        }

        register("lrange") { _, args in
            guard args.count == 3 else { throw TclError(message: "wrong # args: should be \"lrange list first last\"") }
            let items = TclInterp.parseList(args[0])
            func resolve(_ s: String) -> Int {
                if s == "end" { return items.count - 1 }
                if s.hasPrefix("end-"), let off = Int(s.dropFirst(4)) { return items.count - 1 - off }
                return Int(s) ?? 0
            }
            let lo = max(0, resolve(args[1]))
            let hi = min(items.count - 1, resolve(args[2]))
            guard lo <= hi else { return "" }
            return TclInterp.formatList(Array(items[lo...hi]))
        }

        register("concat") { _, args in
            return args.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        }

        register("join") { _, args in
            guard args.count == 1 || args.count == 2 else { throw TclError(message: "wrong # args: should be \"join list ?joinString?\"") }
            let sep = args.count == 2 ? args[1] : " "
            return TclInterp.parseList(args[0]).joined(separator: sep)
        }

        register("split") { _, args in
            guard args.count == 1 || args.count == 2 else { throw TclError(message: "wrong # args: should be \"split string ?splitChars?\"") }
            let seps = args.count == 2 ? Set(args[1]) : Set(" \t\n\r")
            if seps.isEmpty { return TclInterp.formatList(args[0].map { String($0) }) }
            var parts: [String] = []
            var current = ""
            for c in args[0] {
                if seps.contains(c) {
                    parts.append(current)
                    current = ""
                } else {
                    current.append(c)
                }
            }
            parts.append(current)
            return TclInterp.formatList(parts)
        }

        register("string") { _, args in
            guard args.count >= 2 else { throw TclError(message: "wrong # args: should be \"string subcommand ...\"") }
            let sub = args[0]
            let s = args[1]
            let chars = Array(s)
            switch sub {
            case "length":
                return String(chars.count)
            case "index":
                guard args.count == 3 else { throw TclError(message: "wrong # args: should be \"string index string charIndex\"") }
                var idx: Int
                if args[2] == "end" { idx = chars.count - 1 }
                else if args[2].hasPrefix("end-"), let off = Int(args[2].dropFirst(4)) { idx = chars.count - 1 - off }
                else { idx = Int(args[2]) ?? -1 }
                guard idx >= 0 && idx < chars.count else { return "" }
                return String(chars[idx])
            case "range":
                guard args.count == 4 else { throw TclError(message: "wrong # args: should be \"string range string first last\"") }
                func resolve(_ t: String) -> Int {
                    if t == "end" { return chars.count - 1 }
                    if t.hasPrefix("end-"), let off = Int(t.dropFirst(4)) { return chars.count - 1 - off }
                    return Int(t) ?? 0
                }
                let lo = max(0, resolve(args[2]))
                let hi = min(chars.count - 1, resolve(args[3]))
                guard lo <= hi else { return "" }
                return String(chars[lo...hi])
            case "tolower":
                return s.lowercased()
            case "toupper":
                return s.uppercased()
            case "trim":
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            case "equal":
                guard args.count == 3 else { throw TclError(message: "wrong # args: should be \"string equal string1 string2\"") }
                return s == args[2] ? "1" : "0"
            case "compare":
                guard args.count == 3 else { throw TclError(message: "wrong # args: should be \"string compare string1 string2\"") }
                if s == args[2] { return "0" }
                return s < args[2] ? "-1" : "1"
            case "repeat":
                guard args.count == 3, let n = Int(args[2]) else { throw TclError(message: "wrong # args: should be \"string repeat string count\"") }
                return String(repeating: s, count: max(0, n))
            default:
                throw TclError(message: "unknown or unsupported string subcommand \"\(sub)\"")
            }
        }

        register("append") { interp, args in
            guard args.count >= 1 else { throw TclError(message: "wrong # args: should be \"append varName ?value ...?\"") }
            var value = interp.varExists(args[0]) ? try interp.getVar(args[0]) : ""
            for a in args.dropFirst() { value += a }
            interp.setVar(args[0], value)
            return value
        }

        register("format") { _, args in
            guard args.count >= 1 else { throw TclError(message: "wrong # args: should be \"format formatString ?arg ...?\"") }
            return try TclFormat.format(args[0], Array(args.dropFirst()))
        }

        register("clock") { _, args in
            guard let sub = args.first else { throw TclError(message: "wrong # args: should be \"clock subcommand\"") }
            switch sub {
            case "milliseconds", "clicks":
                return String(Int(Date().timeIntervalSince1970 * 1000))
            case "seconds":
                return String(Int(Date().timeIntervalSince1970))
            default:
                throw TclError(message: "unsupported clock subcommand \"\(sub)\"")
            }
        }

        register("info") { interp, args in
            guard args.count >= 1 else { throw TclError(message: "wrong # args: should be \"info subcommand\"") }
            switch args[0] {
            case "exists":
                guard args.count == 2 else { throw TclError(message: "wrong # args: should be \"info exists varName\"") }
                return interp.varExists(args[1]) ? "1" : "0"
            case "commands":
                return TclInterp.formatList(Array(interp.builtins.keys) + Array(interp.procs.keys))
            default:
                throw TclError(message: "unsupported info subcommand \"\(args[0])\"")
            }
        }
    }
}

// MARK: - printf-style formatting for the `format` command

enum TclFormat {
    static func format(_ spec: String, _ args: [String]) throws -> String {
        var out = ""
        var chars = Array(spec)[...]
        var argIndex = 0

        func nextArg() throws -> String {
            guard argIndex < args.count else {
                throw TclError(message: "not enough arguments for all format specifiers")
            }
            defer { argIndex += 1 }
            return args[argIndex]
        }

        while let c = chars.first {
            chars = chars.dropFirst()
            if c != "%" {
                out.append(c)
                continue
            }
            guard let first = chars.first else { break }
            if first == "%" {
                out.append("%")
                chars = chars.dropFirst()
                continue
            }
            // Parse [flags][width][.precision]conversion
            var leftAlign = false
            var zeroPad = false
            while let f = chars.first, f == "-" || f == "0" || f == "+" || f == " " {
                if f == "-" { leftAlign = true }
                if f == "0" { zeroPad = true }
                chars = chars.dropFirst()
            }
            var width = 0
            while let d = chars.first, d.isNumber {
                width = width * 10 + Int(String(d))!
                chars = chars.dropFirst()
            }
            var precision = -1
            if chars.first == "." {
                chars = chars.dropFirst()
                precision = 0
                while let d = chars.first, d.isNumber {
                    precision = precision * 10 + Int(String(d))!
                    chars = chars.dropFirst()
                }
            }
            guard let conv = chars.first else { break }
            chars = chars.dropFirst()

            var piece: String
            switch conv {
            case "d", "i":
                let v = Int(Double(try nextArg()) ?? 0)
                piece = String(v)
                if zeroPad && piece.count < width {
                    let neg = piece.hasPrefix("-")
                    let digits = neg ? String(piece.dropFirst()) : piece
                    let padded = String(repeating: "0", count: width - piece.count) + digits
                    piece = (neg ? "-" : "") + padded
                }
            case "f", "e", "g":
                let v = Double(try nextArg()) ?? 0
                let p = precision >= 0 ? precision : 6
                if conv == "f" {
                    piece = fixed(v, p)
                } else {
                    piece = String(v)
                }
            case "s":
                piece = try nextArg()
                if precision >= 0 && piece.count > precision {
                    piece = String(piece.prefix(precision))
                }
            case "x":
                piece = String(Int(Double(try nextArg()) ?? 0), radix: 16)
            case "X":
                piece = String(Int(Double(try nextArg()) ?? 0), radix: 16).uppercased()
            case "c":
                let v = Int(Double(try nextArg()) ?? 0)
                if v > 0 && v < 0x110000, let scalar = UnicodeScalar(UInt32(v)) {
                    piece = String(Character(scalar))
                } else {
                    piece = ""
                }
            default:
                throw TclError(message: "bad format conversion \"%\(conv)\"")
            }
            if piece.count < width {
                let pad = String(repeating: " ", count: width - piece.count)
                piece = leftAlign ? piece + pad : pad + piece
            }
            out += piece
        }
        return out
    }

    static func fixed(_ v: Double, _ places: Int) -> String {
        var scale = 1.0
        for _ in 0..<places { scale *= 10 }
        let rounded = (v * scale).rounded() / scale
        var intPart = Int(rounded)
        if places == 0 { return String(intPart) }
        let neg = rounded < 0
        var frac = abs(rounded) - Double(abs(intPart))
        var fracDigits = ""
        for _ in 0..<places {
            frac *= 10
            let d = Int(frac)
            fracDigits.append(String(d))
            frac -= Double(d)
        }
        if neg && intPart == 0 {
            return "-0." + fracDigits
        }
        if neg { intPart = -abs(intPart) }
        return String(intPart) + "." + fracDigits
    }
}
