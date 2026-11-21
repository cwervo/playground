import Foundation

/// EAN-13 / UPC-A decoder over run lengths — the textbook 1980s algorithm:
/// find the 1-1-1 guard, normalize every digit's 4 runs to 7 modules,
/// nearest-pattern match with L/G/R parity tables, verify the checksum.
enum EANUPCDecoder {
    /// L-code digit patterns as element widths (space,bar,space,bar), 7 modules.
    /// R runs are identical (colors swapped); G runs are these reversed.
    static let L: [[Float]] = [
        [3, 2, 1, 1], [2, 2, 2, 1], [2, 1, 2, 2], [1, 4, 1, 1], [1, 1, 3, 2],
        [1, 2, 3, 1], [1, 1, 1, 4], [1, 3, 1, 2], [1, 2, 1, 3], [3, 1, 1, 2],
    ]
    /// First digit from the left-half parity pattern (true = G/even).
    static let parityToFirstDigit: [String: Int] = [
        "OOOOOO": 0, "OOEOEE": 1, "OOEEOE": 2, "OOEEEO": 3, "OEOOEE": 4,
        "OEEOOE": 5, "OEEEOO": 6, "OEOEOE": 7, "OEOEEO": 8, "OEEOEO": 9,
    ]

    static func decode(runs: [Int]) -> BarcodeDecode? {
        // runs[0] is a space run; bar runs sit at odd indices.
        var i = 1
        while i + 58 < runs.count {
            defer { i += 2 }
            // Start guard: three roughly equal runs, after a quiet zone.
            let g0 = runs[i], g1 = runs[i + 1], g2 = runs[i + 2]
            let m0 = Float(g0 + g1 + g2) / 3
            guard m0 >= 1,
                  ratioOK(Float(g0), m0), ratioOK(Float(g1), m0), ratioOK(Float(g2), m0),
                  Float(runs[i - 1]) > 5 * m0  // quiet zone
            else { continue }

            // Whole symbol is 59 runs / 95 modules; re-estimate the module.
            let symbolRuns = Array(runs[i..<(i + 59)])
            let total = Float(symbolRuns.reduce(0, +))
            let m = total / 95
            guard ratioOK(m0, m) else { continue }

            // Middle guard (runs 27..31) and end guard (runs 56..58): all 1 module.
            guard (27...31).allSatisfy({ ratioOK(Float(symbolRuns[$0]), m) }),
                  (56...58).allSatisfy({ ratioOK(Float(symbolRuns[$0]), m) })
            else { continue }

            var digits: [Int] = []
            var parity = ""
            var ok = true
            for d in 0..<6 {  // left half: runs 3+4d ..< 7+4d, space-first
                let e = normalize(Array(symbolRuns[(3 + 4 * d)..<(7 + 4 * d)]))
                if let (digit, isG) = matchLeft(e) {
                    digits.append(digit); parity += isG ? "E" : "O"
                } else { ok = false; break }
            }
            guard ok, let first = parityToFirstDigit[parity] else { continue }
            for d in 0..<6 {  // right half: runs 32+4d ..< 36+4d, bar-first
                let e = normalize(Array(symbolRuns[(32 + 4 * d)..<(36 + 4 * d)]))
                if let digit = matchR(e) { digits.append(digit) } else { ok = false; break }
            }
            guard ok else { continue }

            let all = [first] + digits
            guard checksumOK(all) else { continue }
            let value = all.map(String.init).joined()
            return first == 0
                ? BarcodeDecode(symbology: "UPC-A", value: String(value.dropFirst()))
                : BarcodeDecode(symbology: "EAN-13", value: value)
        }
        return nil
    }

    @inline(__always) static func ratioOK(_ a: Float, _ b: Float) -> Bool {
        a > 0.4 * b && a < 1.9 * b
    }

    /// Normalize a digit's 4 element widths to 7 modules.
    static func normalize(_ runs: [Int]) -> [Float] {
        let sum = Float(runs.reduce(0, +))
        return runs.map { Float($0) * 7 / sum }
    }

    static func score(_ e: [Float], _ pattern: [Float]) -> Float {
        zip(e, pattern).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
    }

    /// Left half: try L (odd) and G (= reversed L, even) tables.
    static func matchLeft(_ e: [Float]) -> (digit: Int, isG: Bool)? {
        var best: (Int, Bool)? = nil
        var bestScore: Float = 1.2  // reject anything worse than this
        for d in 0..<10 {
            let sL = score(e, L[d])
            if sL < bestScore { bestScore = sL; best = (d, false) }
            let sG = score(e, L[d].reversed())
            if sG < bestScore { bestScore = sG; best = (d, true) }
        }
        return best
    }

    /// Right half: R run lengths equal L run lengths (bar-first).
    static func matchR(_ e: [Float]) -> Int? {
        var best: Int? = nil
        var bestScore: Float = 1.2
        for d in 0..<10 {
            let s = score(e, L[d])
            if s < bestScore { bestScore = s; best = d }
        }
        return best
    }

    static func checksumOK(_ d: [Int]) -> Bool {
        guard d.count == 13 else { return false }
        var sum = 0
        for i in 0..<12 { sum += d[i] * (i % 2 == 0 ? 1 : 3) }
        return (10 - sum % 10) % 10 == d[12]
    }
}

/// Code 39: 9 elements per character (bar-first), exactly 3 wide.
/// Wide/narrow classification straight off the run lengths.
enum Code39Decoder {
    static let table: [String: Character] = [
        "000110100": "0", "100100001": "1", "001100001": "2", "101100000": "3",
        "000110001": "4", "100110000": "5", "001110000": "6", "000100101": "7",
        "100100100": "8", "001100100": "9", "100001001": "A", "001001001": "B",
        "101001000": "C", "000011001": "D", "100011000": "E", "001011000": "F",
        "000001101": "G", "100001100": "H", "001001100": "I", "000011100": "J",
        "100000011": "K", "001000011": "L", "101000010": "M", "000010011": "N",
        "100010010": "O", "001010010": "P", "000000111": "Q", "100000110": "R",
        "001000110": "S", "000010110": "T", "110000001": "U", "011000001": "V",
        "111000000": "W", "010010001": "X", "110010000": "Y", "011010000": "Z",
        "010000101": "-", "110000100": ".", "011000100": " ", "010010100": "*",
        "010101000": "$", "010100010": "/", "010001010": "+", "000101010": "%",
    ]

    static func decode(runs: [Int]) -> BarcodeDecode? {
        var i = 1  // first bar run
        while i + 8 < runs.count {
            defer { i += 2 }
            if let text = tryFrom(runs: runs, start: i) {
                return BarcodeDecode(symbology: "Code 39", value: text)
            }
        }
        return nil
    }

    static func tryFrom(runs: [Int], start: Int) -> String? {
        var chars: [Character] = []
        var i = start
        while i + 8 < runs.count {
            guard let c = matchChar(Array(runs[i..<(i + 9)])) else { break }
            chars.append(c)
            i += 9
            // Inter-character narrow space (skip; end of data if huge).
            if i < runs.count, chars.last == "*", chars.count > 1 { break }
            i += 1
        }
        guard chars.count >= 3, chars.first == "*", chars.last == "*" else { return nil }
        let body = String(chars.dropFirst().dropLast())
        return body.contains("*") ? nil : body
    }

    static func matchChar(_ runs9: [Int]) -> Character? {
        let sorted = runs9.sorted()
        let narrow = Float(sorted[0..<6].reduce(0, +)) / 6
        let wide = Float(sorted[6..<9].reduce(0, +)) / 3
        guard narrow > 0, wide / narrow > 1.4, wide / narrow < 4.5 else { return nil }
        let mid = (narrow + wide) / 2
        let key = String(runs9.map { Float($0) > mid ? "1" : "0" }.joined())
        return table[key]
    }
}
