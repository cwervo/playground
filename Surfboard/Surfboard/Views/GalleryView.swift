//
//  GalleryView.swift
//  Surfboard
//
//  The left-hand mini-gallery of saved clips. Scrolls vertically and shows a
//  compact preview cell for every kind of clip.
//

import SwiftUI

struct GalleryView: View {

    @EnvironmentObject private var store: ClipStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.clips.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.clips) { clip in
                            ClipCell(clip: clip)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.delete(clip)
                                    } label: {
                                        Label("Delete Clip", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Theme.peach)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.peachDeep, lineWidth: 1)
        )
        .padding(.leading, 16)
        .padding(.vertical, 16)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Surfboard")
                .titleStyle(20)
            Text("\(store.clips.count) clip\(store.clips.count == 1 ? "" : "s")")
                .instructionStyle(11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.inkMuted)
            Text("No clips yet")
                .bodyStyle(14)
            Text("// paste or type\n// in the middle\n// panel to save")
                .instructionStyle(11)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }
}

/// A single preview cell in the gallery.
struct ClipCell: View {

    @EnvironmentObject private var store: ClipStore
    let clip: Clip

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.previewTitle)
                    .font(clip.kind == .text || clip.kind == .link ? Theme.sans(13) : Theme.mono(12))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(clip.kind.label.uppercased())
                        .font(Theme.mono(9, weight: .medium))
                        .foregroundStyle(Theme.accent)
                    Text(relativeDate)
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.peachPale)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.peachDeep.opacity(0.6), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = store.thumbnail(for: clip) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.accent.opacity(0.10))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: clip.kind.symbolName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.accent)
                )
        }
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: clip.createdAt, relativeTo: Date())
    }
}
