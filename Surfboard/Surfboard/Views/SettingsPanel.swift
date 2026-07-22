//
//  SettingsPanel.swift
//  Surfboard
//
//  The right-hand settings drawer. Collapsed, only a 10%-wide "tab" peeks in
//  from the right edge; the parent view slides the rest in when it is dragged
//  open (or when the tab is tapped). Contains all app settings including the
//  guarded "Delete All Data" flow.
//

import SwiftUI

struct SettingsPanel: View {

    @EnvironmentObject private var store: ClipStore

    /// Width of the always-visible peek tab.
    let peekWidth: CGFloat
    /// Whether the drawer is currently expanded (drives the chevron + hint).
    let isOpen: Bool
    /// Called when the peek tab is tapped.
    let onToggle: () -> Void

    // Settings state (persisted to UserDefaults).
    @AppStorage("autoSaveOnPaste") private var autoSaveOnPaste = true
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("showRelativeDates") private var showRelativeDates = true
    @AppStorage("compactGallery") private var compactGallery = false

    // Delete-all flow.
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 0) {
            peekTab
            panelBody
        }
        .background(Theme.peachDeep)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.peach, lineWidth: 1)
        )
        .padding(.vertical, 16)
        .shadow(color: .black.opacity(0.12), radius: 16, x: -6, y: 4)
    }

    // MARK: - Peek tab (the always-visible 10%)

    private var peekTab: some View {
        Button(action: onToggle) {
            VStack(spacing: 14) {
                Image(systemName: isOpen ? "chevron.right" : "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                Text("SETTINGS")
                    .font(Theme.mono(12, weight: .medium))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(90))
                    .fixedSize()
                    .frame(height: 90)

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: peekWidth)
            .frame(maxHeight: .infinity)
            .background(Theme.accent)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Full panel body

    private var panelBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .titleStyle(26)
                    Text("// swipe the tab or tap it to open")
                        .instructionStyle(12)
                }

                section("Capture") {
                    toggleRow("Auto-save on paste",
                              detail: "Pasted clips go straight to the gallery.",
                              isOn: $autoSaveOnPaste)
                    toggleRow("Confirm before deleting a clip",
                              detail: "Ask before removing an individual clip.",
                              isOn: $confirmBeforeDelete)
                }

                section("Gallery") {
                    toggleRow("Relative dates",
                              detail: "Show \"2m ago\" instead of timestamps.",
                              isOn: $showRelativeDates)
                    toggleRow("Compact cells",
                              detail: "Fit more clips on screen.",
                              isOn: $compactGallery)
                }

                section("Storage") {
                    HStack {
                        Text("Saved clips")
                            .bodyStyle(15)
                        Spacer()
                        Text("\(store.clips.count)")
                            .font(Theme.mono(15, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                }

                dangerZone

                Text("Surfboard · v1.0")
                    .instructionStyle(11)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Danger zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Danger Zone")
                .font(Theme.sans(13, weight: .bold))
                .foregroundStyle(Theme.danger)
                .tracking(1)

            if showDeleteConfirm {
                // Red confirmation card — deliberately two-step so nobody
                // nukes their Surfboard data by accident.
                VStack(alignment: .leading, spacing: 14) {
                    Label("This deletes every saved clip and cannot be undone.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(.white)

                    HStack(spacing: 12) {
                        Button {
                            withAnimation { showDeleteConfirm = false }
                        } label: {
                            Text("Cancel")
                                .font(Theme.sans(14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.deleteAllData()
                            withAnimation { showDeleteConfirm = false }
                        } label: {
                            Label("Delete Everything", systemImage: "trash.fill")
                                .font(Theme.sans(14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Color(hex: 0x8A0000))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.danger)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Button {
                    withAnimation { showDeleteConfirm = true }
                } label: {
                    Label("Delete All Data", systemImage: "trash")
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Theme.danger, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(Theme.mono(11, weight: .medium))
                .foregroundStyle(Theme.inkMuted)
                .tracking(1.5)
            content()
        }
    }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bodyStyle(15)
                Text(detail)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .tint(Theme.accent)
    }
}
