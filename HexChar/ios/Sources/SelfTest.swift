import UIKit

/// Headless checks for the CLI workflow (ios/simulate.sh). Launch arguments:
///   -hexchar-selftest   correctness: data, layout round-trip, backspace, search
///   -hexchar-perftest   renders every category through the real draw(_:) path
///                       and fails if any full-board render exceeds the budget.
/// Both print HEXCHAR_* lines to stdout and exit(0)/exit(1) so the script can
/// gate on them via `simctl launch --console-pty`.
enum SelfTest {

    static let drawBudgetMilliseconds = 15.0

    static func runIfRequested(controller: KeyboardViewController) {
        let args = ProcessInfo.processInfo.arguments
        let wantSelf = args.contains("-hexchar-selftest")
        let wantPerf = args.contains("-hexchar-perftest")
        guard wantSelf || wantPerf else { return }

        // Give UIKit one turn of the run loop to finish the first layout.
        DispatchQueue.main.async {
            var ok = true
            if wantSelf { ok = runCorrectness(controller: controller) && ok }
            if wantPerf { ok = runPerf(controller: controller) && ok }
            print(ok ? "HEXCHAR_RESULT: PASS" : "HEXCHAR_RESULT: FAIL")
            fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                exit(ok ? 0 : 1)
            }
        }
    }

    private static func check(_ condition: Bool, _ name: String) -> Bool {
        print("HEXCHAR_TEST \(condition ? "pass" : "FAIL") \(name)")
        return condition
    }

    private static func runCorrectness(controller: KeyboardViewController) -> Bool {
        var ok = true
        let data = controller.data

        ok = check(data.groups.count == 2, "two groups") && ok
        ok = check(data.categories.count >= 20, "categories present") && ok
        ok = check(data.categories.allSatisfy { !$0.chars.isEmpty },
                   "no empty category") && ok

        // Layout round-trip: the centre of every key must hit-test back to
        // that key, at several board widths including odd fractions.
        for width in [320.0, 390.0, 430.5, 768.0] {
            let layout = HexLayout(boardWidth: CGFloat(width), count: 178)
            var misses = 0
            for (i, frame) in layout.frames.enumerated() {
                if layout.hitTest(CGPoint(x: frame.midX, y: frame.midY)) != i {
                    misses += 1
                }
            }
            ok = check(misses == 0, "hit-test round-trip width \(width)") && ok
            ok = check(layout.hitTest(CGPoint(x: -10, y: -10)) == nil,
                       "out of bounds is nil width \(width)") && ok
            // A corner tap inside a key's bounding box but outside its hexagon
            // must not land on that key: the top-left corner of an even-row key
            // belongs to nothing (row 0) — never to the key whose box it is in.
            if let first = layout.frames.first {
                let corner = CGPoint(x: first.minX + 1, y: first.minY + 1)
                ok = check(layout.hitTest(corner) != 0,
                           "corner outside hexagon width \(width)") && ok
            }
        }

        // Backspace removes one grapheme cluster (base + combining marks).
        let text = "iy\u{0325}"  // i, then y with combining ring below
        if let r = HexUnicode.deletingBackward(text, location: (text as NSString).length,
                                               length: 0) {
            ok = check(r.text == "i", "grapheme backspace drops cluster") && ok
        } else {
            ok = check(false, "grapheme backspace returned nil") && ok
        }
        ok = check(HexUnicode.deletingBackward("", location: 0, length: 0) == nil,
                   "backspace on empty is nil") && ok

        // Search: by name and by code point.
        let all = data.categories.flatMap { $0.chars }
        let schwa = HexSearch.search("schwa", in: all)
        ok = check(schwa.first?.c == "\u{0259}", "search schwa") && ok
        let place = HexSearch.search("U+2318", in: all)
        ok = check(place.first?.c == "\u{2318}", "search U+2318") && ok

        // Insert + display split for emoji-presentation characters.
        if let fuel = all.first(where: { $0.c == "\u{26FD}" }) {
            ok = check(HexUnicode.displayText(for: fuel).hasSuffix("\u{FE0E}"),
                       "emoji key drawn with text presentation") && ok
        }
        return ok
    }

    private static func runPerf(controller: KeyboardViewController) -> Bool {
        var ok = true
        var worst = 0.0
        var worstId = ""
        let board = controller.board
        let width = max(board.bounds.width, 366)

        var ids = controller.data.categories.map { $0.id }
        ids.append("recent")
        for id in ids {
            let entries = controller.entries(forCategoryId: id)
            board.setEntries(entries, boardWidth: width)
            let size = CGSize(width: width, height: max(board.contentHeight, 1))
            board.frame = CGRect(origin: .zero, size: size)

            // Render through the real draw(_:) path, full board, and take the
            // best of three runs so one scheduler hiccup doesn't fail the gate.
            var best = Double.greatestFiniteMagnitude
            let renderer = UIGraphicsImageRenderer(size: size)
            for _ in 0..<3 {
                _ = renderer.image { _ in board.draw(board.bounds) }
                best = min(best, board.lastDrawMilliseconds)
            }
            print(String(format: "HEXCHAR_PERF %@ keys=%d ms=%.2f",
                         id, entries.count, best))
            if best > worst { worst = best; worstId = id }
        }
        ok = worst < drawBudgetMilliseconds
        print(String(format: "HEXCHAR_PERF_RESULT max_ms=%.2f budget_ms=%.0f worst=%@ %@",
                     worst, drawBudgetMilliseconds, worstId, ok ? "PASS" : "FAIL"))
        return ok
    }
}
