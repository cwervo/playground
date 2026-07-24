import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraController()
    @StateObject private var store = ScanStore()
    @State private var showGallery = false
    @State private var flashSaved = false

    var body: some View {
        ZStack {
            if camera.authorized {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                QuadOverlay(quads: camera.quads)
                    .ignoresSafeArea()
                RedBarOverlay(scanline: camera.scanline, centerY: $camera.barCenterY)
                    .ignoresSafeArea()
            } else {
                ContentUnavailableView(
                    "Camera access needed",
                    systemImage: "camera",
                    description: Text("LabScan only ever uses the camera locally. Enable it in Settings."))
            }

            VStack {
                decodeBanner
                Spacer()
                controls
            }
        }
        .statusBarHidden()
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .sheet(isPresented: $showGallery) { GalleryView(store: store) }
    }

    @ViewBuilder
    private var decodeBanner: some View {
        if let d = camera.confirmedDecode {
            VStack(spacing: 2) {
                Text(d.value)
                    .font(.title3.monospaced().bold())
                    .textSelection(.enabled)
                Text(d.symbology)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var controls: some View {
        HStack(spacing: 40) {
            Button {
                showGallery = true
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.title2)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Button {
                if let img = camera.snapshot() {
                    store.save(image: img, decode: camera.confirmedDecode, quads: camera.quads)
                    withAnimation(.easeOut(duration: 0.15)) { flashSaved = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation { flashSaved = false }
                    }
                }
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 72, height: 72)
                    Circle().fill(flashSaved ? Color.red : .white).frame(width: 58, height: 58)
                }
            }

            // Airplane-mode badge: a reminder this tool owes nothing to the network.
            Image(systemName: "airplane")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
        }
        .foregroundStyle(.white)
        .padding(.bottom, 24)
    }
}

/// Local captures — thumbnails, decode metadata, swipe to delete.
struct GalleryView: View {
    @ObservedObject var store: ScanStore
    @Environment(\.dismiss) private var dismiss
    @State private var opened: ScanRecord?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.records) { record in
                    Button {
                        opened = record
                    } label: {
                        row(for: record)
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { idx in
                    idx.map { store.records[$0] }.forEach(store.delete)
                }
            }
            .overlay {
                if store.records.isEmpty {
                    ContentUnavailableView(
                        "No scans yet",
                        systemImage: "doc.viewfinder",
                        description: Text("Captures live in this app's local storage only."))
                }
            }
            .navigationTitle("Scans (local)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(item: $opened) { record in
                ScanDetailView(store: store, initialID: record.id)
            }
        }
    }

    private func row(for record: ScanRecord) -> some View {
        HStack(spacing: 12) {
            if let img = store.image(for: record) {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                if let decode = record.decode {
                    Text(decode).font(.body.monospaced())
                    Text(record.symbology ?? "")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("no decode").font(.caption).foregroundStyle(.secondary)
                }
                if let summary = detectionSummary(record) {
                    Text(summary).font(.caption2).foregroundStyle(.secondary)
                } else if !record.quadLabels.isEmpty {
                    Text(record.quadLabels.joined(separator: ", "))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(record.date, style: .date).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    /// "4 text · 1 QR · tag36h11 #17" — what the offline read found.
    private func detectionSummary(_ record: ScanRecord) -> String? {
        guard let dets = record.detections, !dets.isEmpty else { return nil }
        var parts: [String] = []
        let count = { (k: Detection.Kind) in dets.filter { $0.kind == k }.count }
        if count(.text) > 0 { parts.append("\(count(.text)) text") }
        if count(.qr) > 0 { parts.append("\(count(.qr)) QR") }
        if count(.dataMatrix) > 0 { parts.append("\(count(.dataMatrix)) DataMatrix") }
        if count(.barcode) > 0 { parts.append("\(count(.barcode)) barcode") }
        parts += dets.filter { $0.kind == .aprilTag }.map(\.payload)
        return parts.joined(separator: " · ")
    }
}
