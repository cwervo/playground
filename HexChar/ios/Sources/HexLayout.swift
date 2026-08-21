import Foundation
import CoreGraphics

/// The honeycomb geometry, kept identical to the web version: pointy-top
/// hexagons of width w and height 1.1547w, rows overlapping by a quarter of
/// the hexagon height, odd rows offset half a key and one key shorter.
/// Pure math — no UIKit — so it can be exercised by the in-app self-test.
struct HexLayout {
    let boardWidth: CGFloat
    let columns: Int
    let hexWidth: CGFloat
    let hexHeight: CGFloat
    let gap: CGFloat
    let count: Int
    private(set) var frames: [CGRect] = []
    private(set) var rowCol: [(row: Int, col: Int)] = []

    /// Vertical distance between successive row tops.
    var rowStride: CGFloat { hexHeight * 0.75 + gap * 0.866 }

    var contentHeight: CGFloat {
        frames.last.map { $0.maxY } ?? 0
    }

    init(boardWidth: CGFloat, count: Int, gap: CGFloat = 4) {
        self.boardWidth = max(boardWidth, 1)
        self.count = count
        self.gap = gap

        let minWidth: CGFloat = boardWidth < 380 ? 44 : (boardWidth < 620 ? 52 : 58)
        var cols = max(3, Int((boardWidth + gap) / (minWidth + gap)))
        var hw = (boardWidth + gap) / CGFloat(cols) - gap
        if hw > 76 {  // keep keys thumb-sized on wide layouts
            cols = Int(ceil((boardWidth + gap) / (76 + gap)))
            hw = (boardWidth + gap) / CGFloat(cols) - gap
        }
        self.columns = cols
        self.hexWidth = hw
        self.hexHeight = hw * 1.1547

        var i = 0, row = 0
        while i < count {
            let odd = row % 2 == 1
            let take = odd ? columns - 1 : columns
            let xOffset = odd ? (hexWidth + gap) / 2 : 0
            let y = CGFloat(row) * rowStride
            var col = 0
            while col < take && i < count {
                let x = xOffset + CGFloat(col) * (hexWidth + gap)
                frames.append(CGRect(x: x, y: y, width: hexWidth, height: hexHeight))
                rowCol.append((row, col))
                col += 1
                i += 1
            }
            row += 1
        }
    }

    /// A pointy-top hexagon path for a key of this layout, at the origin.
    func hexPath(inset: CGFloat = 1) -> CGPath {
        let w = hexWidth - inset * 2
        let h = hexHeight - inset * 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: inset + w / 2, y: inset))
        path.addLine(to: CGPoint(x: inset + w, y: inset + h * 0.25))
        path.addLine(to: CGPoint(x: inset + w, y: inset + h * 0.75))
        path.addLine(to: CGPoint(x: inset + w / 2, y: inset + h))
        path.addLine(to: CGPoint(x: inset, y: inset + h * 0.75))
        path.addLine(to: CGPoint(x: inset, y: inset + h * 0.25))
        path.closeSubpath()
        return path
    }

    /// Index of the key whose hexagon contains the point, or nil. The rows
    /// overlap, so a bounding-box test alone would hand corner taps to the
    /// wrong key; the hexagon inequality decides.
    func hitTest(_ point: CGPoint) -> Int? {
        let a = hexWidth / 2
        let b = hexHeight / 2
        for (i, frame) in frames.enumerated() {
            if !frame.insetBy(dx: -1, dy: -1).contains(point) { continue }
            let dx = abs(point.x - frame.midX)
            let dy = abs(point.y - frame.midY)
            if dx <= a && dy <= b - (b / 2) * (dx / a) {
                return i
            }
        }
        return nil
    }
}
