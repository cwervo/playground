// FolkEngine.swift
// Bridges the FolkVM to SwiftUI: owns the VM, ticks it once per rendered
// frame (driven by the Surface's draw loop), and publishes the results.

import Foundation
import CoreGraphics
import Combine

final class FolkEngine: ObservableObject {

    let vm = FolkVM()
    private let startDate = Date()

    @Published private(set) var frame = FolkFrame()

    /// Errors from the user's program, keyed for the input box.
    var userProgramError: String? {
        frame.errors.first(where: { $0.program == FolkEngine.userProgramID })?.message
    }

    static let userProgramID = "input-box"

    init() {
        for (id, code) in FolkBuiltins.programs {
            vm.setProgram(id: id, code: code)
        }
    }

    /// Run one VM evaluation. Called from the Surface's per-frame callback
    /// (main thread), so published changes drive the SwiftUI overlays too.
    func tick(surfaceSize: CGSize) {
        let now = Date()
        let newFrame = vm.tick(now: now,
                               uptime: now.timeIntervalSince(startDate),
                               surfaceSize: surfaceSize)
        frame = newFrame
    }

    func setUserProgram(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            vm.removeProgram(id: FolkEngine.userProgramID)
        } else {
            vm.setProgram(id: FolkEngine.userProgramID, code: code)
        }
    }
}
