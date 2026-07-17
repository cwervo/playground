// TclExpr.swift
// Expression evaluator for the `expr` command: numbers, arithmetic,
// comparison, boolean logic, and the usual math functions.
// The interpreter substitutes $vars and [commands] before this runs.

import Foundation

enum TclValue {
    case int(Int)
    case dbl(Double)
    case str(String)

    var asDouble: Double {
        switch self {
        case .int(let i): return Double(i)
        case .dbl(let d): return d
        case .str(let s): return Double(s) ?? 0
        }
    }

    var asString: String {
        switch self {
        case .int(let i): return String(i)
        case .dbl(let d):
            if d == d.rounded() && abs(d) < 1e15 {
                return String(format0(d))
            }
            return String(d)
        case .str(let s): return s
        }
    }

    var isNumeric: Bool {
        switch self {
        case .int, .dbl: return true
        case .str(let s): return Int(s) != nil || Double(s) != nil
        }
    }

    var truthy: Bool {
        switch self {
        case .int(let i): return i != 0
        case .dbl(let d): return d != 0
        case .str(let s):
            let lower = s.lowercased()
            if lower == "true" || lower == "yes" || lower == "on" { return true }
            if lower == "false" || lower == "no" || lower == "off" || lower.isEmpty { return false }
            if let i = Int(s) { return i != 0 }
            if let d = Double(s) { return d != 0 }
            return true
        }
    }
}

private func format0(_ d: Double) -> String {
    // Tcl prints whole doubles as "5.0"; keep that so int/double parsing stays sane.
    let i = Int(d)
    return "\(i).0"
}

enum TclExpr {

    static func isTrue(_ s: String) -> Bool {
        return TclValue.str(s).truthy
    }

    static func evaluate(_ text: String) throws -> String {
        var parser = ExprParser(text)
        let v = try parser.parseTernary()
        parser.skipSpace()
        if !parser.atEnd {
            throw TclError(message: "invalid expression: trailing characters in \"\(text)\"")
        }
        return v.asString
    }

    struct ExprParser {
        let chars: [Character]
        var i = 0

        init(_ s: String) {
            chars = Array(s)
        }

        var atEnd: Bool { i >= chars.count }

        mutating func skipSpace() {
            while i < chars.count && chars[i].isWhitespace { i += 1 }
        }

        func peek(_ offset: Int = 0) -> Character? {
            let idx = i + offset
            return idx < chars.count ? chars[idx] : nil
        }

        mutating func match(_ s: String) -> Bool {
            skipSpace()
            let target = Array(s)
            guard i + target.count <= chars.count else { return false }
            for (k, c) in target.enumerated() where chars[i + k] != c { return false }
            i += target.count
            return true
        }

        // Ternary  cond ? a : b
        mutating func parseTernary() throws -> TclValue {
            let cond = try parseOr()
            skipSpace()
            if peek() == "?" {
                i += 1
                let a = try parseTernary()
                skipSpace()
                guard peek() == ":" else { throw TclError(message: "expected : in ternary expression") }
                i += 1
                let b = try parseTernary()
                return cond.truthy ? a : b
            }
            return cond
        }

        mutating func parseOr() throws -> TclValue {
            var v = try parseAnd()
            while true {
                skipSpace()
                if peek() == "|" && peek(1) == "|" {
                    i += 2
                    let rhs = try parseAnd()
                    v = .int((v.truthy || rhs.truthy) ? 1 : 0)
                } else {
                    return v
                }
            }
        }

        mutating func parseAnd() throws -> TclValue {
            var v = try parseEquality()
            while true {
                skipSpace()
                if peek() == "&" && peek(1) == "&" {
                    i += 2
                    let rhs = try parseEquality()
                    v = .int((v.truthy && rhs.truthy) ? 1 : 0)
                } else {
                    return v
                }
            }
        }

        mutating func parseEquality() throws -> TclValue {
            var v = try parseRelational()
            while true {
                skipSpace()
                if peek() == "=" && peek(1) == "=" {
                    i += 2
                    let rhs = try parseRelational()
                    v = .int(equalValues(v, rhs) ? 1 : 0)
                } else if peek() == "!" && peek(1) == "=" {
                    i += 2
                    let rhs = try parseRelational()
                    v = .int(equalValues(v, rhs) ? 0 : 1)
                } else if matchWord("eq") {
                    let rhs = try parseRelational()
                    v = .int(v.asString == rhs.asString ? 1 : 0)
                } else if matchWord("ne") {
                    let rhs = try parseRelational()
                    v = .int(v.asString != rhs.asString ? 1 : 0)
                } else {
                    return v
                }
            }
        }

        mutating func matchWord(_ w: String) -> Bool {
            skipSpace()
            let target = Array(w)
            guard i + target.count <= chars.count else { return false }
            for (k, c) in target.enumerated() where chars[i + k] != c { return false }
            // Must not be followed by an identifier character.
            let after = i + target.count
            if after < chars.count {
                let c = chars[after]
                if c.isLetter || c.isNumber || c == "_" { return false }
            }
            i += target.count
            return true
        }

        mutating func parseRelational() throws -> TclValue {
            var v = try parseAdditive()
            while true {
                skipSpace()
                if peek() == "<" && peek(1) == "=" {
                    i += 2
                    let rhs = try parseAdditive()
                    v = .int(v.asDouble <= rhs.asDouble ? 1 : 0)
                } else if peek() == ">" && peek(1) == "=" {
                    i += 2
                    let rhs = try parseAdditive()
                    v = .int(v.asDouble >= rhs.asDouble ? 1 : 0)
                } else if peek() == "<" {
                    i += 1
                    let rhs = try parseAdditive()
                    v = .int(v.asDouble < rhs.asDouble ? 1 : 0)
                } else if peek() == ">" {
                    i += 1
                    let rhs = try parseAdditive()
                    v = .int(v.asDouble > rhs.asDouble ? 1 : 0)
                } else {
                    return v
                }
            }
        }

        mutating func parseAdditive() throws -> TclValue {
            var v = try parseMultiplicative()
            while true {
                skipSpace()
                if peek() == "+" {
                    i += 1
                    let rhs = try parseMultiplicative()
                    v = numericOp(v, rhs, { $0 + $1 }, { $0 + $1 })
                } else if peek() == "-" {
                    i += 1
                    let rhs = try parseMultiplicative()
                    v = numericOp(v, rhs, { $0 - $1 }, { $0 - $1 })
                } else {
                    return v
                }
            }
        }

        mutating func parseMultiplicative() throws -> TclValue {
            var v = try parseUnary()
            while true {
                skipSpace()
                if peek() == "*" && peek(1) == "*" {
                    i += 2
                    let rhs = try parseUnary()
                    v = .dbl(pow(v.asDouble, rhs.asDouble))
                } else if peek() == "*" {
                    i += 1
                    let rhs = try parseUnary()
                    v = numericOp(v, rhs, { $0 * $1 }, { $0 * $1 })
                } else if peek() == "/" {
                    i += 1
                    let rhs = try parseUnary()
                    if case .int(let a) = normalize(v), case .int(let b) = normalize(rhs) {
                        guard b != 0 else { throw TclError(message: "divide by zero") }
                        v = .int(Int((Double(a) / Double(b)).rounded(.down)))
                    } else {
                        let b = rhs.asDouble
                        guard b != 0 else { throw TclError(message: "divide by zero") }
                        v = .dbl(v.asDouble / b)
                    }
                } else if peek() == "%" {
                    i += 1
                    let rhs = try parseUnary()
                    guard case .int(let a) = normalize(v), case .int(let b) = normalize(rhs), b != 0 else {
                        throw TclError(message: "can't take modulo: operands must be nonzero integers")
                    }
                    // Tcl modulo takes the sign of the divisor.
                    var m = a % b
                    if m != 0 && ((m < 0) != (b < 0)) { m += b }
                    v = .int(m)
                } else {
                    return v
                }
            }
        }

        mutating func parseUnary() throws -> TclValue {
            skipSpace()
            if peek() == "-" {
                i += 1
                let v = try parseUnary()
                if case .int(let a) = normalize(v) { return .int(-a) }
                return .dbl(-v.asDouble)
            }
            if peek() == "+" {
                i += 1
                return try parseUnary()
            }
            if peek() == "!" && peek(1) != "=" {
                i += 1
                let v = try parseUnary()
                return .int(v.truthy ? 0 : 1)
            }
            return try parsePrimary()
        }

        mutating func parsePrimary() throws -> TclValue {
            skipSpace()
            guard let c = peek() else {
                throw TclError(message: "unexpected end of expression")
            }
            if c == "(" {
                i += 1
                let v = try parseTernary()
                skipSpace()
                guard peek() == ")" else { throw TclError(message: "missing )") }
                i += 1
                return v
            }
            if c == "\"" {
                i += 1
                var s = ""
                while let ch = peek(), ch != "\"" {
                    s.append(ch)
                    i += 1
                }
                guard peek() == "\"" else { throw TclError(message: "missing closing quote in expression") }
                i += 1
                return .str(s)
            }
            if c == "{" {
                i += 1
                var depth = 1
                var s = ""
                while let ch = peek() {
                    if ch == "{" { depth += 1 }
                    if ch == "}" {
                        depth -= 1
                        if depth == 0 { break }
                    }
                    s.append(ch)
                    i += 1
                }
                guard peek() == "}" else { throw TclError(message: "missing } in expression") }
                i += 1
                return .str(s)
            }
            if c.isNumber || (c == "." && (peek(1)?.isNumber ?? false)) {
                return try parseNumber()
            }
            if c.isLetter || c == "_" {
                return try parseIdentifier()
            }
            throw TclError(message: "unexpected character \"\(c)\" in expression")
        }

        mutating func parseNumber() throws -> TclValue {
            var s = ""
            var isDouble = false
            if peek() == "0" && (peek(1) == "x" || peek(1) == "X") {
                i += 2
                var hex = ""
                while let c = peek(), c.isHexDigit {
                    hex.append(c)
                    i += 1
                }
                guard let v = Int(hex, radix: 16) else { throw TclError(message: "bad hex number") }
                return .int(v)
            }
            while let c = peek() {
                if c.isNumber {
                    s.append(c)
                    i += 1
                } else if c == "." && !isDouble {
                    isDouble = true
                    s.append(c)
                    i += 1
                } else if (c == "e" || c == "E"), !s.isEmpty,
                          let n = peek(1), n.isNumber || n == "-" || n == "+" {
                    isDouble = true
                    s.append(c)
                    i += 1
                    if let sign = peek(), sign == "-" || sign == "+" {
                        s.append(sign)
                        i += 1
                    }
                } else {
                    break
                }
            }
            if isDouble {
                guard let d = Double(s) else { throw TclError(message: "bad number \"\(s)\"") }
                return .dbl(d)
            }
            guard let n = Int(s) else {
                guard let d = Double(s) else { throw TclError(message: "bad number \"\(s)\"") }
                return .dbl(d)
            }
            return .int(n)
        }

        mutating func parseIdentifier() throws -> TclValue {
            var name = ""
            while let c = peek(), c.isLetter || c.isNumber || c == "_" {
                name.append(c)
                i += 1
            }
            skipSpace()
            if peek() == "(" {
                i += 1
                var args: [TclValue] = []
                skipSpace()
                if peek() != ")" {
                    while true {
                        args.append(try parseTernary())
                        skipSpace()
                        if peek() == "," {
                            i += 1
                            continue
                        }
                        break
                    }
                }
                guard peek() == ")" else { throw TclError(message: "missing ) after function arguments") }
                i += 1
                return try applyFunction(name, args)
            }
            switch name.lowercased() {
            case "true", "yes", "on": return .int(1)
            case "false", "no", "off": return .int(0)
            default:
                // A bare word (e.g. a substituted string value): treat as string.
                return .str(name)
            }
        }

        func applyFunction(_ name: String, _ args: [TclValue]) throws -> TclValue {
            func one() throws -> Double {
                guard args.count == 1 else { throw TclError(message: "\(name)() takes 1 argument") }
                return args[0].asDouble
            }
            func two() throws -> (Double, Double) {
                guard args.count == 2 else { throw TclError(message: "\(name)() takes 2 arguments") }
                return (args[0].asDouble, args[1].asDouble)
            }
            switch name {
            case "sin": return .dbl(sin(try one()))
            case "cos": return .dbl(cos(try one()))
            case "tan": return .dbl(tan(try one()))
            case "asin": return .dbl(asin(try one()))
            case "acos": return .dbl(acos(try one()))
            case "atan": return .dbl(atan(try one()))
            case "atan2":
                let (a, b) = try two()
                return .dbl(atan2(a, b))
            case "sqrt": return .dbl((try one()).squareRoot())
            case "exp": return .dbl(exp(try one()))
            case "log": return .dbl(log(try one()))
            case "log10": return .dbl(log10(try one()))
            case "pow":
                let (a, b) = try two()
                return .dbl(pow(a, b))
            case "hypot":
                let (a, b) = try two()
                return .dbl((a * a + b * b).squareRoot())
            case "fmod":
                let (a, b) = try two()
                return .dbl(fmod(a, b))
            case "abs":
                guard args.count == 1 else { throw TclError(message: "abs() takes 1 argument") }
                if case .int(let v) = normalize(args[0]) { return .int(abs(v)) }
                return .dbl(abs(args[0].asDouble))
            case "floor": return .dbl((try one()).rounded(.down))
            case "ceil": return .dbl((try one()).rounded(.up))
            case "round": return .int(Int((try one()).rounded()))
            case "int": return .int(Int(try one()))
            case "double": return .dbl(try one())
            case "min":
                guard !args.isEmpty else { throw TclError(message: "min() needs arguments") }
                return .dbl(args.map { $0.asDouble }.min()!)
            case "max":
                guard !args.isEmpty else { throw TclError(message: "max() needs arguments") }
                return .dbl(args.map { $0.asDouble }.max()!)
            case "rand":
                return .dbl(Double.random(in: 0..<1))
            case "srand":
                return .dbl(0)
            default:
                throw TclError(message: "unknown math function \"\(name)\"")
            }
        }
    }

    // Coerce a value to int/double when its string form is numeric.
    static func normalize(_ v: TclValue) -> TclValue {
        if case .str(let s) = v {
            if let i = Int(s) { return .int(i) }
            if let d = Double(s) { return .dbl(d) }
        }
        return v
    }

    static func numericOp(_ a: TclValue, _ b: TclValue,
                          _ intOp: (Int, Int) -> Int,
                          _ dblOp: (Double, Double) -> Double) -> TclValue {
        let na = normalize(a)
        let nb = normalize(b)
        if case .int(let x) = na, case .int(let y) = nb {
            return .int(intOp(x, y))
        }
        return .dbl(dblOp(na.asDouble, nb.asDouble))
    }

    static func equalValues(_ a: TclValue, _ b: TclValue) -> Bool {
        let na = normalize(a)
        let nb = normalize(b)
        if na.isNumeric && nb.isNumeric {
            return na.asDouble == nb.asDouble
        }
        return na.asString == nb.asString
    }
}

// Free-function helpers so the parser struct's methods can call them unqualified.
private func normalize(_ v: TclValue) -> TclValue { TclExpr.normalize(v) }
private func numericOp(_ a: TclValue, _ b: TclValue,
                       _ intOp: (Int, Int) -> Int,
                       _ dblOp: (Double, Double) -> Double) -> TclValue {
    TclExpr.numericOp(a, b, intOp, dblOp)
}
private func equalValues(_ a: TclValue, _ b: TclValue) -> Bool { TclExpr.equalValues(a, b) }
