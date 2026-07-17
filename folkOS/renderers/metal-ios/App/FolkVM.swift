// FolkVM.swift — Swift wrapper around the embedded Jim Tcl folk
// engine (CSources/folk_jim.c + Engine/folk-engine.tcl).

import Foundation

struct FolkOp: Decodable, Equatable {
    let op: String
    let text: String?
    let color: String?
    let thickness: Double?
    let radius: Double?
    let x: Double?
    let y: Double?
    let filled: Bool?
}

struct FolkFrame: Decodable, Equatable {
    let ok: Bool
    let error: String?
    let statementCount: Int
    let display: [FolkOp]

    static func failure(_ message: String) -> FolkFrame {
        FolkFrame(ok: false, error: message, statementCount: 0, display: [
            FolkOp(op: "error", text: message, color: "red",
                   thickness: nil, radius: nil, x: nil, y: nil, filled: nil),
        ])
    }
}

final class FolkVM {
    static let shared = FolkVM()

    private let ready: Bool

    private init() {
        guard let url = Bundle.main.url(forResource: "folk-engine", withExtension: "tcl"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            ready = false
            return
        }
        ready = folk_init(source) == 0
    }

    func eval(_ code: String) -> FolkFrame {
        guard ready else {
            return .failure("folk engine failed to start: \(String(cString: folk_last_error()))")
        }
        guard let cJson = folk_eval_program(code) else {
            return .failure("engine returned no frame")
        }
        let json = String(cString: cJson)
        do {
            return try JSONDecoder().decode(FolkFrame.self, from: Data(json.utf8))
        } catch {
            return .failure("bad frame from engine: \(error)")
        }
    }
}
