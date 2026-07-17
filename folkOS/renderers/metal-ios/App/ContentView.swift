// ContentView.swift — the FolkBoy shell.
//
// Layout (portrait, Game Boy-ish):
//   ┌───────────────────────────────┐
//   │ ● POWER              OK/ERROR │  screen bezel
//   │ ┌────────────┬──────────────┐ │
//   │ │  editor    │  Metal out   │ │  top ~45%: left code,
//   │ │  (code)    │  (the table) │ │  right simulated output
//   │ └────────────┴──────────────┘ │
//   │  FOLK BOY · folkOS            │
//   │ [q][w][e][r][t][y][u][i][o][p]│  keyboard instead of
//   │  [a][s][d][f][g][h][j][k][l]  │  d-pad and A/B
//   │ [⇧][z][x][c][v][b][n][m][⌫]  │
//   │ [#$1][$][  space  ]["][⏎]    │
//   │   (SELECT·CLEAR) (START·RUN)  │
//   └───────────────────────────────┘

import SwiftUI

struct ContentView: View {
    @State private var code =
        "Wish $this is outlined green\nWish $this is labelled \"hello from iOS\""
    @State private var folkFrame: FolkFrame?

    private let shellColor = Color(red: 0.76, green: 0.75, blue: 0.71)
    private let bezelColor = Color(red: 0.21, green: 0.21, blue: 0.26)
    private let logoColor = Color(red: 0.16, green: 0.16, blue: 0.42)
    private let dmgScreenGreen = Color(red: 0.61, green: 0.74, blue: 0.06)
    private let dmgScreenDark = Color(red: 0.06, green: 0.13, blue: 0.06)

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 10) {
                screen(height: geo.size.height * 0.42)
                logo
                GameBoyKeyboard { handle($0) }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shellColor.ignoresSafeArea())
        }
        .onAppear { run() }
        .onChange(of: code) { _ in run() }
    }

    private func screen(height: CGFloat) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 7, height: 7)
                Text("POWER")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.gray)
                Spacer()
                Text(statusText)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(folkFrame?.ok == false ? .red : .green)
            }
            HStack(spacing: 8) {
                editorPane
                MetalScreenView(folkFrame: folkFrame)
                    .cornerRadius(6)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16).fill(bezelColor))
        .frame(height: height)
    }

    private var statusText: String {
        guard let frame = folkFrame else { return "·" }
        if !frame.ok { return "ERROR" }
        return "OK · \(frame.statementCount) stmts · \(frame.display.count) ops"
    }

    private var editorPane: some View {
        ScrollView {
            Text(code + "▊")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(dmgScreenGreen)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        }
        .background(dmgScreenDark)
        .cornerRadius(6)
    }

    private var logo: some View {
        Text("FOLK BOY · folkOS")
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .italic()
            .foregroundColor(logoColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
    }

    private func handle(_ action: GameBoyKeyboard.Action) {
        switch action {
        case .insert(let s): code += s
        case .backspace: if !code.isEmpty { code.removeLast() }
        case .newline: code += "\n"
        case .clear: code = ""
        case .run: run()
        }
    }

    private func run() {
        folkFrame = FolkVM.shared.eval(code)
    }
}
