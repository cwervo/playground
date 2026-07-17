// DrawInstruction.swift
// The Surface's instruction set. Folk programs emit these via display wishes
// ("Wish to draw a circle at {x y} radius r color gold"); the Surface plays
// the role of Folk's Vulkan render context and translates each instruction
// into Metal draw calls.

import Foundation
import simd

struct RGBA: Equatable {
    var r: Float
    var g: Float
    var b: Float
    var a: Float

    var simd: SIMD4<Float> { SIMD4(r, g, b, a) }

    static let white = RGBA(r: 1, g: 1, b: 1, a: 1)
    static let black = RGBA(r: 0, g: 0, b: 0, a: 1)
    static let gold = RGBA(r: 0.83, g: 0.68, b: 0.21, a: 1)

    static let named: [String: RGBA] = [
        "white": .white,
        "black": .black,
        "gold": .gold,
        "red": RGBA(r: 0.92, g: 0.26, b: 0.21, a: 1),
        "green": RGBA(r: 0.30, g: 0.77, b: 0.36, a: 1),
        "blue": RGBA(r: 0.25, g: 0.48, b: 0.94, a: 1),
        "cyan": RGBA(r: 0.25, g: 0.85, b: 0.90, a: 1),
        "magenta": RGBA(r: 0.90, g: 0.30, b: 0.85, a: 1),
        "yellow": RGBA(r: 0.98, g: 0.86, b: 0.25, a: 1),
        "orange": RGBA(r: 0.98, g: 0.60, b: 0.20, a: 1),
        "purple": RGBA(r: 0.62, g: 0.35, b: 0.90, a: 1),
        "gray": RGBA(r: 0.55, g: 0.55, b: 0.55, a: 1),
        "grey": RGBA(r: 0.55, g: 0.55, b: 0.55, a: 1),
    ]

    /// Parse "gold" or "{r g b}" / "{r g b a}" (components 0..1).
    static func parse(_ s: String) -> RGBA? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if let c = named[trimmed.lowercased()] { return c }
        let parts = TclInterp.parseList(trimmed).compactMap { Float($0) }
        if parts.count == 3 {
            return RGBA(r: parts[0], g: parts[1], b: parts[2], a: 1)
        }
        if parts.count == 4 {
            return RGBA(r: parts[0], g: parts[1], b: parts[2], a: parts[3])
        }
        return nil
    }
}

enum DrawInstruction: Equatable {
    case clear(RGBA)
    case line(from: SIMD2<Float>, to: SIMD2<Float>, thickness: Float, color: RGBA)
    case rect(origin: SIMD2<Float>, size: SIMD2<Float>, color: RGBA)
    case circle(center: SIMD2<Float>, radius: Float, thickness: Float?, color: RGBA)  // nil thickness = filled
    case text(String, position: SIMD2<Float>, size: Float, color: RGBA)
    case metaballs(centers: [SIMD2<Float>], radius: Float, color: RGBA)

    /// Parse the words of a display wish into an instruction.
    /// Recognized forms (words after "Wish"):
    ///   the surface is cleared with color C
    ///   to draw a line from {x y} to {x y} color C ?thickness T?
    ///   to draw a circle at {x y} radius R color C ?thickness T?
    ///   to draw a rectangle at {x y} size {w h} color C
    ///   to draw text T at {x y} ?size S? ?color C?
    ///   to draw metaballs at {x y} {x y} {x y} {x y} radius R color C
    static func parse(wishWords words: [String]) -> DrawInstruction? {
        if words.count >= 7,
           words[0] == "the", words[1] == "surface", words[2] == "is", words[3] == "cleared",
           words[4] == "with", words[5] == "color",
           let c = RGBA.parse(words[6]) {
            return .clear(c)
        }

        guard words.count >= 3, words[0] == "to", words[1] == "draw" else { return nil }
        let rest = Array(words.dropFirst(2))
        guard let head = rest.first else { return nil }

        func point(_ s: String) -> SIMD2<Float>? {
            let parts = TclInterp.parseList(s).compactMap { Float($0) }
            guard parts.count == 2 else { return nil }
            return SIMD2(parts[0], parts[1])
        }

        // Pull "key value" options off the tail into a dictionary.
        func takeOptions(_ keys: Set<String>, from items: inout [String]) -> [String: String] {
            var opts: [String: String] = [:]
            while items.count >= 2, keys.contains(items[items.count - 2]) {
                let value = items.removeLast()
                let key = items.removeLast()
                opts[key] = value
            }
            return opts
        }

        switch head {
        case "a" where rest.count >= 2 && rest[1] == "line":
            // a line from {x y} to {x y} color C ?thickness T?
            var items = Array(rest.dropFirst(2))
            let opts = takeOptions(["color", "thickness"], from: &items)
            guard items.count == 4, items[0] == "from", items[2] == "to",
                  let p1 = point(items[1]), let p2 = point(items[3]),
                  let c = RGBA.parse(opts["color"] ?? "white") else { return nil }
            let t = Float(opts["thickness"] ?? "2") ?? 2
            return .line(from: p1, to: p2, thickness: t, color: c)

        case "a" where rest.count >= 2 && rest[1] == "circle":
            // a circle at {x y} radius R color C ?thickness T?
            var items = Array(rest.dropFirst(2))
            let opts = takeOptions(["color", "thickness", "radius"], from: &items)
            guard items.count == 2, items[0] == "at",
                  let p = point(items[1]),
                  let r = Float(opts["radius"] ?? ""),
                  let c = RGBA.parse(opts["color"] ?? "white") else { return nil }
            let thickness = opts["thickness"].flatMap { Float($0) }
            return .circle(center: p, radius: r, thickness: thickness, color: c)

        case "a" where rest.count >= 2 && (rest[1] == "rectangle" || rest[1] == "rect"):
            // a rectangle at {x y} size {w h} color C
            var items = Array(rest.dropFirst(2))
            let opts = takeOptions(["color", "size"], from: &items)
            guard items.count == 2, items[0] == "at",
                  let p = point(items[1]),
                  let sz = point(opts["size"] ?? ""),
                  let c = RGBA.parse(opts["color"] ?? "white") else { return nil }
            return .rect(origin: p, size: sz, color: c)

        case "text":
            // text T at {x y} ?size S? ?color C?
            var items = Array(rest.dropFirst(1))
            let opts = takeOptions(["color", "size"], from: &items)
            guard items.count == 3, items[1] == "at",
                  let p = point(items[2]) else { return nil }
            let size = Float(opts["size"] ?? "17") ?? 17
            let color = RGBA.parse(opts["color"] ?? "white") ?? .white
            return .text(items[0], position: p, size: size, color: color)

        case "metaballs":
            // metaballs at {x y} {x y} {x y} {x y} radius R color C
            var items = Array(rest.dropFirst(1))
            let opts = takeOptions(["color", "radius"], from: &items)
            guard items.count >= 2, items[0] == "at" else { return nil }
            let centers = items.dropFirst().compactMap { point($0) }
            guard !centers.isEmpty,
                  let r = Float(opts["radius"] ?? ""),
                  let c = RGBA.parse(opts["color"] ?? "gold") else { return nil }
            return .metaballs(centers: Array(centers.prefix(8)), radius: r, color: c)

        default:
            return nil
        }
    }
}
