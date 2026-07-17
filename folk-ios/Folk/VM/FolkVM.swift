// FolkVM.swift
// The Folk layer on top of the Tcl evaluator: a reactive statement database
// with Claim / Wish / When, re-evaluated from scratch every tick (like Folk's
// own evaluation model, minus Commit and I/O).

import Foundation
import CoreGraphics

struct FolkStatement: Hashable {
    let source: String       // program that made the claim
    let words: [String]

    var key: String {
        source + "\u{1}" + words.joined(separator: "\u{1}")
    }
}

struct FolkProgram: Identifiable, Equatable {
    let id: String           // program name, used as $this
    var code: String
}

struct FolkFrame {
    var instructions: [DrawInstruction] = []
    var labels: [(program: String, text: String)] = []
    var output: [String] = []
    var errors: [(program: String, message: String)] = []
}

final class FolkVM {

    private struct WhenRule {
        let id: Int
        let pattern: [String]
        let body: String
        let program: String
        let env: [String: String]
    }

    var programs: [FolkProgram] = []

    /// Log of `puts` output across ticks (bounded).
    private(set) var outputLog: [String] = []

    private var nextRuleID = 0

    func setProgram(id: String, code: String) {
        if let idx = programs.firstIndex(where: { $0.id == id }) {
            programs[idx].code = code
        } else {
            programs.append(FolkProgram(id: id, code: code))
        }
    }

    func removeProgram(id: String) {
        programs.removeAll { $0.id == id }
    }

    /// Evaluate every program against a fresh statement database.
    func tick(now: Date, uptime: TimeInterval, surfaceSize: CGSize) -> FolkFrame {
        var frame = FolkFrame()
        var statements: [FolkStatement] = []
        var statementKeys = Set<String>()
        var rules: [WhenRule] = []
        nextRuleID = 0

        let interp = TclInterp()
        interp.puts = { text in
            frame.output.append(text)
        }

        var currentProgram = "system"

        func addStatement(_ st: FolkStatement) {
            if statementKeys.insert(st.key).inserted {
                statements.append(st)
            }
        }

        // --- Folk commands -------------------------------------------------

        interp.register("Claim") { _, args in
            guard !args.isEmpty else { throw TclError(message: "Claim needs arguments") }
            addStatement(FolkStatement(source: currentProgram, words: args))
            return ""
        }

        interp.register("Wish") { _, args in
            guard !args.isEmpty else { throw TclError(message: "Wish needs arguments") }
            addStatement(FolkStatement(source: currentProgram, words: ["wish"] + args))
            return ""
        }

        interp.register("When") { interp, args in
            guard args.count >= 2 else {
                throw TclError(message: "When needs a pattern and a body")
            }
            let body = args[args.count - 1]
            let pattern = Array(args.dropLast())
            rules.append(WhenRule(id: self.nextRuleID,
                                  pattern: pattern,
                                  body: body,
                                  program: currentProgram,
                                  env: interp.visibleVars()))
            self.nextRuleID += 1
            return ""
        }

        // Commit needs cross-tick state, which this VM doesn't keep yet;
        // accept it as a no-op that still evaluates its body once.
        interp.register("Commit") { interp, args in
            guard let body = args.last else { return "" }
            _ = try interp.eval(body)
            return ""
        }

        // --- Base claims ---------------------------------------------------

        let t = String((uptime * 1000).rounded() / 1000)
        addStatement(FolkStatement(source: "system", words: ["the", "clock", "time", "is", t]))

        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
        let hh = comps.hour ?? 0
        let mm = comps.minute ?? 0
        let ss = comps.second ?? 0
        let ms = (comps.nanosecond ?? 0) / 1_000_000
        addStatement(FolkStatement(source: "system",
                                   words: ["the", "wall", "clock", "is",
                                           String(hh), String(mm), String(ss), String(ms)]))

        let w = String(Int(surfaceSize.width))
        let h = String(Int(surfaceSize.height))
        addStatement(FolkStatement(source: "system", words: ["the", "surface", "has", "size", w, h]))

        // --- Run every program at top level --------------------------------

        for program in programs {
            currentProgram = program.id
            interp.setVar("this", program.id)
            interp.resetStepBudget()
            do {
                _ = try interp.eval(program.code)
            } catch let e as TclError {
                frame.errors.append((program.id, e.message))
            } catch TclControl.ret {
                // top-level return: fine
            } catch {
                frame.errors.append((program.id, "\(error)"))
            }
        }

        // --- Match When rules to statements until fixpoint -----------------

        var executed = Set<String>()
        for _ in 0..<8 {
            var fired = false
            // Snapshot: rules/statements may grow while bodies run.
            let currentRules = rules
            let currentStatements = statements
            for rule in currentRules {
                for st in currentStatements {
                    guard let bindings = FolkVM.match(pattern: rule.pattern, statement: st) else { continue }
                    let execKey = "\(rule.id)|\(st.key)"
                    if executed.contains(execKey) { continue }
                    executed.insert(execKey)
                    fired = true

                    currentProgram = rule.program
                    for (k, v) in rule.env { interp.setVar(k, v) }
                    interp.setVar("this", rule.program)
                    for (k, v) in bindings { interp.setVar(k, v) }
                    interp.resetStepBudget()
                    do {
                        _ = try interp.eval(rule.body)
                    } catch let e as TclError {
                        frame.errors.append((rule.program, e.message))
                    } catch TclControl.ret {
                        // ignore
                    } catch {
                        frame.errors.append((rule.program, "\(error)"))
                    }
                }
            }
            if !fired { break }
        }

        // --- Collect wishes into draw instructions & labels ----------------

        for st in statements where st.words.first == "wish" {
            let wish = Array(st.words.dropFirst())
            if let instruction = DrawInstruction.parse(wishWords: wish) {
                frame.instructions.append(instruction)
            } else if wish.count >= 4 && wish[1] == "is" && wish[2] == "labelled" {
                frame.labels.append((program: st.source, text: wish[3]))
            }
            // Unrecognized wishes are inert, as in Folk: nothing handles them.
        }

        outputLog.append(contentsOf: frame.output)
        if outputLog.count > 200 {
            outputLog.removeFirst(outputLog.count - 200)
        }
        return frame
    }

    /// Match a When pattern against a statement.
    /// `/name/` binds one word; a leading `/x/ claims` binds x to the source
    /// program (Folk's "someone claims" convention).
    static func match(pattern: [String], statement: FolkStatement) -> [String: String]? {
        var pat = pattern
        var bindings: [String: String] = [:]

        if pat.count >= 2, let someone = varName(pat[0]), pat[1] == "claims" {
            bindings[someone] = statement.source
            pat = Array(pat.dropFirst(2))
        }
        guard pat.count == statement.words.count else { return nil }
        for (pword, sword) in zip(pat, statement.words) {
            if let name = varName(pword) {
                if name == "someone" || name == "any" {
                    // anonymous wildcards still bind, harmlessly
                }
                bindings[name] = sword
            } else if pword != sword {
                return nil
            }
        }
        return bindings
    }

    private static func varName(_ word: String) -> String? {
        guard word.count >= 3, word.hasPrefix("/"), word.hasSuffix("/") else { return nil }
        let inner = String(word.dropFirst().dropLast())
        guard !inner.contains("/") else { return nil }
        return inner
    }
}
