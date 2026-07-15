import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// The hub's on-device photo store: gallery grid + detail viewer with a
// simple "hub processing" demo (edge extraction).

struct GalleryView: View {
    @ObservedObject var sim: SimModel
    @State private var selected: PhotoRecord? = nil
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HUB — PHOTO STORE (PERSISTED ON DEVICE)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Label("clear", systemImage: "trash").font(.caption)
                }
                .disabled(sim.store.photos.isEmpty)
            }

            if sim.store.photos.isEmpty {
                Text("no photos yet — the hub stores each received JPEG here")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(sim.store.photos.reversed()) { rec in
                        Button { selected = rec } label: {
                            VStack(spacing: 2) {
                                thumbnail(rec)
                                Text("#\(rec.id) · \(rec.bytes / 1024) KB")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 10))
        .sheet(item: $selected) { rec in
            PhotoDetailView(rec: rec, store: sim.store)
        }
        .confirmationDialog("Delete all stored photos from this device?",
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { sim.store.clear() }
        }
    }

    @ViewBuilder
    private func thumbnail(_ rec: PhotoRecord) -> some View {
        if let img = sim.store.image(for: rec) {
            Image(uiImage: img)
                .resizable()
                .interpolation(.none)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.3)))
        } else {
            RoundedRectangle(cornerRadius: 4).fill(.black)
                .aspectRatio(4 / 3, contentMode: .fit)
        }
    }
}

struct PhotoDetailView: View {
    let rec: PhotoRecord
    let store: PhotoStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let img = store.image(for: rec) {
                        HStack(alignment: .top, spacing: 16) {
                            labeled("stored JPEG (as received by hub)") {
                                pixelImage(img)
                            }
                            labeled("hub processing: edge extraction") {
                                pixelImage(edges(of: img) ?? img)
                            }
                        }
                        ShareLink(item: Image(uiImage: img),
                                  preview: SharePreview("photo #\(rec.id)", image: Image(uiImage: img))) {
                            Label("share / save image", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                    Text(meta)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(role: .destructive) {
                        store.delete(rec)
                        dismiss()
                    } label: {
                        Label("delete photo", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("photo #\(rec.id) — frame \(rec.frame)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var meta: String {
        """
        received : \(rec.date.formatted(date: .abbreviated, time: .standard))
        link     : \(rec.link) · \(rec.pkts) packets · \(rec.retries) retries
        size     : \(rec.bytes) B · jpeg q=\(String(format: "%.2f", rec.quality)) · 160×120 mono
        """
    }

    private func labeled<Content: View>(_ caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) {
            content()
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func pixelImage(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .interpolation(.none)
            .aspectRatio(4 / 3, contentMode: .fit)
            .frame(maxWidth: 280)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.4)))
    }

    private func edges(of img: UIImage) -> UIImage? {
        guard let ci = CIImage(image: img) else { return nil }
        let filter = CIFilter.edges()
        filter.inputImage = ci
        filter.intensity = 4
        guard let out = filter.outputImage else { return nil }
        let context = CIContext()
        guard let cg = context.createCGImage(out, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
