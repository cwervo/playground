// GameBoyKeyboard.swift — the bottom half of the FolkBoy shell: a
// Game Boy-styled on-screen keyboard (in place of the d-pad and A/B),
// plus SELECT/START pills for CLEAR and RUN.

import SwiftUI

struct GameBoyKeyboard: View {
    enum Action {
        case insert(String)
        case backspace
        case newline
        case clear
        case run
    }

    var onAction: (Action) -> Void

    @State private var shifted = false
    @State private var symbols = false

    private let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private let symbolRows = ["1234567890", "$\"'(){}[]#", ";:,./-_=<>"]

    private var rows: [String] { symbols ? symbolRows : letterRows }

    var body: some View {
        VStack(spacing: 5) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    if i == 2 && !symbols {
                        modifierKey(shifted ? "⬆" : "⇧", active: shifted) {
                            shifted.toggle()
                        }
                    }
                    ForEach(Array(rows[i]).map(String.init), id: \.self) { ch in
                        key(display(ch)) {
                            onAction(.insert(display(ch)))
                            shifted = false
                        }
                    }
                    if i == 2 {
                        modifierKey("⌫", active: false) { onAction(.backspace) }
                    }
                }
            }
            HStack(spacing: 4) {
                modifierKey(symbols ? "abc" : "#$1", active: symbols) {
                    symbols.toggle()
                }
                key("$") { onAction(.insert("$")) }
                spaceKey
                key("\"") { onAction(.insert("\"")) }
                modifierKey("⏎", active: false) { onAction(.newline) }
            }
            HStack(spacing: 24) {
                pill("SELECT · CLEAR") { onAction(.clear) }
                pill("START · RUN") { onAction(.run) }
            }
            .padding(.top, 8)
        }
    }

    private func display(_ ch: String) -> String {
        (shifted && !symbols) ? ch.uppercased() : ch
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.28, green: 0.28, blue: 0.33))
                )
        }
    }

    private func modifierKey(_ label: String, active: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 42, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active
                              ? Color(red: 0.62, green: 0.16, blue: 0.42)
                              : Color(red: 0.19, green: 0.19, blue: 0.24))
                )
        }
    }

    private var spaceKey: some View {
        Button(action: { onAction(.insert(" ")) }) {
            Text("space")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .frame(minWidth: 110, maxWidth: .infinity, minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.28, green: 0.28, blue: 0.33))
                )
        }
        .layoutPriority(1)
    }

    private func pill(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 0.16, green: 0.16, blue: 0.42))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color(red: 0.56, green: 0.56, blue: 0.53)))
        }
        .rotationEffect(.degrees(-10))
    }
}
