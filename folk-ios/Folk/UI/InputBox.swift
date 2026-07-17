// InputBox.swift
// A draggable code card: type Folk (Tcl) code, press Run, and it becomes a
// live program in the VM. Drag the title bar to move it anywhere on screen.

import SwiftUI

struct InputBox: View {
    @ObservedObject var engine: FolkEngine

    @State private var code: String = FolkBuiltins.sampleUserProgram
    @State private var position = CGPoint(x: 200, y: 220)
    @State private var dragOffset = CGSize.zero
    @State private var collapsed = false

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            if !collapsed {
                editor
            }
        }
        .frame(width: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(red: 0.83, green: 0.68, blue: 0.21).opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .position(x: position.x + dragOffset.width, y: position.y + dragOffset.height)
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundColor(Color(red: 0.83, green: 0.68, blue: 0.21))
                .font(.system(size: 13))
            Text("folk program")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() }
            } label: {
                Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.25))
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    position.x += value.translation.width
                    position.y += value.translation.height
                    dragOffset = .zero
                }
        )
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $code)
                .font(.system(size: 12, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .scrollContentBackground(.hidden)
                .foregroundColor(.white)
                .frame(height: 170)
                .padding(6)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            if let error = engine.userProgramError {
                Text(error)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(red: 1.0, green: 0.5, blue: 0.45))
                    .lineLimit(3)
            }

            HStack {
                Button("Clear") {
                    code = ""
                    engine.setUserProgram(code: "")
                }
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))

                Spacer()

                Button {
                    engine.setUserProgram(code: code)
                } label: {
                    Label("Run", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.83, green: 0.68, blue: 0.21), in: Capsule())
                }
            }
        }
        .padding(10)
    }
}
