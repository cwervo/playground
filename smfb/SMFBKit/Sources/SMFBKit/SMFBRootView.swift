#if canImport(SwiftUI)
import SwiftUI

/// The whole app: an arena the mouse scurries around, the brain schematic in
/// the corner, and a way to put crumbs down on every platform.
///
/// - iOS / watchOS: tap to drop a crumb.
/// - tvOS: swipe the remote to move the crosshair, click (or play/pause) to drop.
/// - macOS: click to drop; toolbar for pause / clear / new brain; speed slider.
/// - watchOS: the Digital Crown scrubs simulation speed.
public struct SMFBRootView: View {
    @ObservedObject private var sim: Simulation
    @Environment(\.scenePhase) private var scenePhase
    @State private var cursor = CGPoint(x: 0.5, y: 0.5)     // tvOS, normalized to width
    @State private var crown: Double = 1                     // watchOS speed
    @State private var speed: Double = 1                     // macOS speed

    public init(sim: Simulation) { self.sim = sim }

    private var style: ArenaStyle {
        #if os(watchOS)
        return .watch
        #elseif os(tvOS)
        return .television
        #elseif os(iOS)
        return .phone
        #else
        return .desktop
        #endif
    }

    public var body: some View {
        GeometryReader { geo in
            arena(in: geo.size)
                .onAppear { sim.setAspect(Float(geo.size.height / max(1, geo.size.width))) }
                .onChange(of: geo.size) { size in sim.setAspect(Float(size.height / max(1, size.width))) }
        }
        .ignoresSafeArea()
        .onAppear { sim.start() }
        .onDisappear { sim.stop() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { sim.start() } else { sim.stop() }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 380)
        .toolbar {
            ToolbarItemGroup {
                Button(sim.isPaused ? "Resume" : "Pause") { sim.togglePaused() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Clear crumbs") { sim.clearFood() }
                Button("New brain") { sim.reset() }
                Slider(value: $speed, in: 0.25...3) { Text("Speed") }
                    .frame(width: 120)
                    .onChange(of: speed) { sim.speed = $0 }
            }
        }
        #endif
        #if os(watchOS)
        .focusable(true)
        .digitalCrownRotation($crown, from: 0.25, through: 3, by: 0.05, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { sim.speed = $0 }
        #endif
    }

    @ViewBuilder
    private func arena(in size: CGSize) -> some View {
        let canvas = TimelineView(.animation) { timeline in
            Canvas(rendersAsynchronously: false) { context, canvasSize in
                let snapshot = sim.currentSnapshot()
                let now = timeline.date.timeIntervalSinceReferenceDate
                context.withCGContext { cg in
                    ArenaRenderer.draw(snapshot, in: cg, rect: CGRect(origin: .zero, size: canvasSize),
                                       style: style, cursor: cursorForRender, now: now)
                }
            }
        }
        #if os(tvOS)
        canvas
            .focusable()
            .onMoveCommand { direction in moveCursor(direction, size: size) }
            .onPlayPauseCommand { dropAtCursor(size: size) }
            .onTapGesture { dropAtCursor(size: size) }
            .onExitCommand { sim.clearFood() }
        #else
        canvas
            .onTapGesture(count: 1, coordinateSpace: .local) { location in
                sim.dropFood(at: location, in: size)
            }
        #endif
    }

    private var cursorForRender: CGPoint? {
        #if os(tvOS)
        return cursor
        #else
        return nil
        #endif
    }

    #if os(tvOS)
    private func moveCursor(_ direction: MoveCommandDirection, size: CGSize) {
        let step: CGFloat = 0.06
        let aspect = size.height / max(1, size.width)
        switch direction {
        case .left: cursor.x -= step
        case .right: cursor.x += step
        case .up: cursor.y -= step
        case .down: cursor.y += step
        @unknown default: break
        }
        cursor.x = min(0.98, max(0.02, cursor.x))
        cursor.y = min(aspect - 0.02, max(0.02, cursor.y))
    }

    private func dropAtCursor(size: CGSize) {
        sim.dropFood(x: Float(cursor.x), y: Float(cursor.y))
    }
    #endif
}
#endif
