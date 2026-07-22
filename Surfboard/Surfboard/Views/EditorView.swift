//
//  EditorView.swift
//  Surfboard
//
//  The middle text-input surface. You can:
//    • type with the normal keyboard and tap "Append" to save the text, or
//    • double-tap the text area to be offered a paste from the clipboard.
//

import SwiftUI

struct EditorView: View {

    @EnvironmentObject private var store: ClipStore

    @State private var draft: String = ""
    @State private var showPastePrompt = false
    @State private var lastCaptured: String?
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            instructions

            editorCard

            actionRow
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Double-tap anywhere on the surface offers a paste.
        .confirmationDialog(
            "Paste from clipboard?",
            isPresented: $showPastePrompt,
            titleVisibility: .visible
        ) {
            Button("Paste & Save to Gallery") { pasteFromClipboard() }
            Button("Paste into Editor") { pasteIntoEditor() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Surfboard can capture whatever is on your clipboard — text, links, images, files and more.")
        }
    }

    // MARK: - Sections

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Capture")
                .titleStyle(26)
            Text("""
            // double-tap the box below to paste a clip
            // or type text and press APPEND to save it
            // saved clips appear in the gallery on the left
            """)
                .instructionStyle(13)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editorCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.peach)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(editorFocused ? Theme.accent : Theme.peachDeep,
                                      lineWidth: editorFocused ? 2 : 1)
                )

            if draft.isEmpty {
                Text("Type here…")
                    .font(Theme.sans(18))
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $draft)
                .font(Theme.sans(18))
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($editorFocused)
                .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Double-tap gesture to offer a paste, per the spec.
        .highPriorityGesture(
            TapGesture(count: 2).onEnded { showPastePrompt = true }
        )
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            if let captured = lastCaptured {
                Label("Saved \(captured)", systemImage: "checkmark.circle.fill")
                    .font(Theme.mono(12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .transition(.opacity)
            }

            Spacer()

            Button {
                showPastePrompt = true
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
                    .font(Theme.sans(15, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
            .buttonStyle(SurfboardSecondaryButton())

            Button {
                appendDraft()
            } label: {
                Label("Append", systemImage: "plus")
                    .font(Theme.sans(15, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
            }
            .buttonStyle(SurfboardPrimaryButton())
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
    }

    // MARK: - Actions

    private func appendDraft() {
        store.addText(draft)
        flash("text")
        draft = ""
        editorFocused = false
    }

    private func pasteFromClipboard() {
        if let kind = store.addFromPasteboard() {
            flash(kind)
        } else {
            flash("nothing")
        }
    }

    private func pasteIntoEditor() {
        if let string = UIPasteboard.general.string {
            draft += (draft.isEmpty ? "" : "\n") + string
        } else if let url = UIPasteboard.general.url {
            draft += (draft.isEmpty ? "" : "\n") + url.absoluteString
        }
        editorFocused = true
    }

    private func flash(_ what: String) {
        withAnimation { lastCaptured = what }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { lastCaptured = nil }
        }
    }
}

// MARK: - Button styles

struct SurfboardPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(Capsule())
    }
}

struct SurfboardSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.accent)
            .background(Theme.peachPale.opacity(configuration.isPressed ? 0.6 : 1))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 1.5))
    }
}
