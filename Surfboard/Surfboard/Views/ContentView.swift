//
//  ContentView.swift
//  Surfboard
//
//  Lays out the three components:
//    • Gallery      — left, 20% width / 90% height, vertically centred.
//    • Editor       — the middle text-input surface.
//    • SettingsPanel — right, a drawer that only peeks 10% of the screen
//                      until it is dragged / scrolled open.
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var store: ClipStore

    /// How far the settings drawer is currently pulled open, as an offset in
    /// points from its collapsed (peeking) position. 0 == collapsed.
    @State private var drawerDrag: CGFloat = 0
    @State private var drawerOpen = false

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height

            // Column geometry from the spec.
            let galleryWidth  = W * 0.20            // 20% vw
            let galleryHeight = H * 0.90            // 90% vh
            let peekWidth     = W * 0.10            // 10% of the settings panel
            let panelWidth    = W * 0.42            // full expanded settings width
            let editorWidth   = W - galleryWidth - peekWidth

            ZStack(alignment: .topLeading) {
                Theme.peachPale.ignoresSafeArea()

                // Base row: gallery + editor. The right 10% is reserved for the
                // settings peek so the editor never sits under the drawer tab.
                HStack(spacing: 0) {
                    GalleryView()
                        .frame(width: galleryWidth, height: galleryHeight)
                        .frame(maxHeight: .infinity)          // vertically centre

                    EditorView()
                        .frame(width: editorWidth)
                        .frame(maxHeight: .infinity)

                    Spacer(minLength: peekWidth)              // room for the drawer
                }

                // Settings drawer, anchored to the right edge. Collapsed it
                // shows only `peekWidth`; dragging left reveals `panelWidth`.
                settingsDrawer(
                    fullWidth: panelWidth,
                    peekWidth: peekWidth,
                    screenWidth: W
                )
            }
        }
    }

    // MARK: - Settings drawer

    @ViewBuilder
    private func settingsDrawer(fullWidth: CGFloat, peekWidth: CGFloat, screenWidth: CGFloat) -> some View {
        // When collapsed the drawer is pushed right so only `peekWidth` shows.
        let hiddenAmount = fullWidth - peekWidth
        let base = drawerOpen ? 0 : hiddenAmount
        let offset = max(0, min(hiddenAmount, base + drawerDrag))

        SettingsPanel(peekWidth: peekWidth, isOpen: drawerOpen) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                drawerOpen.toggle()
            }
        }
        .frame(width: fullWidth)
        .frame(maxHeight: .infinity)
        .offset(x: (screenWidth - fullWidth) + offset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Dragging left (negative) opens; right closes.
                    drawerDrag = value.translation.width
                }
                .onEnded { value in
                    drawerDrag = 0
                    let opened = -value.translation.width
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        if drawerOpen {
                            // Close if dragged right far enough.
                            if value.translation.width > hiddenAmount * 0.3 { drawerOpen = false }
                        } else {
                            // Open if dragged left far enough.
                            if opened > hiddenAmount * 0.3 { drawerOpen = true }
                        }
                    }
                }
        )
    }
}

#Preview {
    ContentView().environmentObject(ClipStore())
}
