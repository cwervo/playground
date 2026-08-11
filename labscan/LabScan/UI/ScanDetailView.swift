import SwiftUI
import CoreImage
import UIKit

/// What a tap on a scan wants inspected: a detected region's slice +
/// metadata, or the raw RGB slice under the finger.
struct Inspection: Identifiable {
    enum Subject {
        case detection(Detection)
        case slice(CGPoint)  // normalized, origin top-left
    }
    let id = UUID()
    var image: UIImage
    var subject: Subject
}

/// Full-screen pager over the original captures. Swipe between scans; tap a
/// highlighted region for its decode, tap anywhere else for the raw slice.
struct ScanDetailView: View {
    @ObservedObject var store: ScanStore
    let initialID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID
    @State private var inspection: Inspection?

    init(store: ScanStore, initialID: UUID) {
        self.store = store
        self.initialID = initialID
        _selection = State(initialValue: initialID)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(store.records) { record in
                    ScanPageView(store: store, recordID: record.id) { inspection = $0 }
                        .tag(record.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(.black)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $inspection) { insp in
                InspectionSheet(inspection: insp)
                    .presentationDetents([.medium, .large])
            }
        }
        .preferredColorScheme(.dark)
    }

    private var title: String {
        guard let r = store.records.first(where: { $0.id == selection }) else { return "Scan" }
        return r.date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// One scan: the original photo with detection outlines, then the decode
/// list. Analysis runs lazily (and offline) for records that predate it.
struct ScanPageView: View {
    @ObservedObject var store: ScanStore
    let recordID: UUID
    var inspect: (Inspection) -> Void

    @State private var image: UIImage?
    @State private var analyzing = false

    private var record: ScanRecord? { store.records.first { $0.id == recordID } }
    private var detections: [Detection] { record?.detections ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let image {
                    annotated(image)
                }
                decodeList
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 40)
        }
        .background(.black)
        .task {
            if image == nil, let r = record { image = store.image(for: r) }
            await analyzeIfNeeded()
        }
    }

    private func annotated(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geo in
                    ForEach(detections) { d in
                        Rectangle()
                            .stroke(d.kind.color, lineWidth: 1.5)
                            .frame(width: CGFloat(d.w) * geo.size.width,
                                   height: CGFloat(d.h) * geo.size.height)
                            .position(x: CGFloat(d.x + d.w / 2) * geo.size.width,
                                      y: CGFloat(d.y + d.h / 2) * geo.size.height)
                    }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { loc in
                            tapped(at: CGPoint(x: loc.x / geo.size.width,
                                               y: loc.y / geo.size.height), image: img)
                        }
                }
            }
    }

    /// Hit-test detections (smallest wins, with a touch margin); no hit
    /// means the raw RGB slice under the finger.
    private func tapped(at p: CGPoint, image: UIImage) {
        let margin = 0.01
        let hit = detections
            .filter { $0.rect.insetBy(dx: -margin, dy: -margin).contains(p) }
            .min { $0.w * $0.h < $1.w * $1.h }
        if let hit {
            inspect(Inspection(image: image, subject: .detection(hit)))
        } else {
            inspect(Inspection(image: image, subject: .slice(p)))
        }
    }

    @ViewBuilder
    private var decodeList: some View {
        if analyzing {
            HStack(spacing: 8) {
                ProgressView()
                Text("reading — OCR · codes · tags (offline)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        } else if detections.isEmpty {
            Text("nothing decoded in this capture")
                .font(.caption.monospaced()).foregroundStyle(.secondary)
        } else {
            ForEach(detections.sorted { $0.y < $1.y }) { d in
                Button {
                    if let image { inspect(Inspection(image: image, subject: .detection(d))) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(d.kind.badge)
                            .font(.caption2.monospaced().bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(d.kind.color.opacity(0.25), in: Capsule())
                            .foregroundStyle(d.kind.color)
                        Text(d.payload)
                            .font(d.kind == .text ? .footnote : .footnote.monospaced())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func analyzeIfNeeded() async {
        guard let r = record, r.detections == nil,
              let img = image ?? record.flatMap(store.image(for:)) else { return }
        analyzing = true
        let dets = await Task.detached(priority: .userInitiated) { StillAnalyzer.analyze(img) }.value
        await MainActor.run {
            if var rr = record { rr.detections = dets; store.update(rr) }
            analyzing = false
        }
    }
}

extension Detection.Kind {
    var badge: String {
        switch self {
        case .text: return "OCR"
        case .barcode: return "BAR"
        case .qr: return "QR"
        case .dataMatrix: return "DM"
        case .aprilTag: return "TAG"
        }
    }
    var color: Color {
        switch self {
        case .text: return .green
        case .barcode: return .orange
        case .qr: return .cyan
        case .dataMatrix: return .purple
        case .aprilTag: return .red
        }
    }
}

// MARK: - Inspectors

struct InspectionSheet: View {
    let inspection: Inspection

    var body: some View {
        switch inspection.subject {
        case .detection(let d): DetectionInspector(image: inspection.image, detection: d)
        case .slice(let p): SliceInspector(image: inspection.image, center: p)
        }
    }
}

/// The decoded region: its image slice, the payload (links tappable), and
/// where it came from.
struct DetectionInspector: View {
    let image: UIImage
    let detection: Detection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text(detection.kind.badge)
                        .font(.caption.monospaced().bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(detection.kind.color.opacity(0.25), in: Capsule())
                        .foregroundStyle(detection.kind.color)
                    if let detail = detection.detail {
                        Text(detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.0f%%", detection.confidence * 100))
                        .font(.caption.monospaced()).foregroundStyle(.tertiary)
                }

                if let slice = image.cropped(toNormalized: detection.rect, margin: 0.2) {
                    Image(uiImage: slice)
                        .resizable()
                        .interpolation(slice.size.width < 250 ? .none : .medium)
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(detection.kind.color.opacity(0.6), lineWidth: 1))
                }

                Text(detection.payload)
                    .font(detection.kind == .text ? .body : .body.monospaced())
                    .textSelection(.enabled)

                let links = detection.payload.detectedLinks
                if !links.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(links, id: \.absoluteString) { url in
                            Link(destination: url) {
                                Label(url.absoluteString, systemImage: "link")
                                    .font(.footnote.monospaced())
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                Button {
                    UIPasteboard.general.string = detection.payload
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationDragIndicator(.visible)
    }
}

/// No decode under the finger → the honest pixels: the slice itself, its
/// R/G/B channel separations, and the mean CIELAB of the patch.
struct SliceInspector: View {
    let image: UIImage
    let center: CGPoint

    var body: some View {
        let side = 0.28
        let rect = CGRect(x: min(max(center.x - side / 2, 0), 1 - side),
                          y: min(max(center.y - side / 2, 0), 1 - side),
                          width: side, height: side)
        let slice = image.cropped(toNormalized: rect, margin: 0)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(format: "raw slice @ (%.0f%%, %.0f%%) — no decode here",
                            center.x * 100, center.y * 100))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)

                if let slice {
                    Image(uiImage: slice)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { ch in
                            VStack(spacing: 4) {
                                if let img = slice.channelImage(ch) {
                                    Image(uiImage: img)
                                        .resizable().scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                Text(["R", "G", "B"][ch])
                                    .font(.caption2.monospaced().bold())
                                    .foregroundStyle([Color.red, .green, .blue][ch])
                            }
                        }
                    }

                    if let lab = slice.meanLab() {
                        Text(String(format: "mean L* %.1f · a* %.1f · b* %.1f",
                                    lab.L, lab.a, lab.b))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Pixel helpers

extension UIImage {
    /// Crop by a normalized (top-left origin) rect, optionally padded.
    func cropped(toNormalized r: CGRect, margin: CGFloat) -> UIImage? {
        guard let cg = cgImage else { return nil }
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        var rect = CGRect(x: r.minX * W, y: r.minY * H, width: r.width * W, height: r.height * H)
        rect = rect.insetBy(dx: -rect.width * margin, dy: -rect.height * margin)
            .intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard rect.width >= 1, rect.height >= 1, let out = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: out)
    }

    /// One channel of the image as grayscale.
    func channelImage(_ channel: Int) -> UIImage? {
        guard let cg = cgImage, let filter = CIFilter(name: "CIColorMatrix") else { return nil }
        let basis = [CIVector(x: 1, y: 0, z: 0, w: 0),
                     CIVector(x: 0, y: 1, z: 0, w: 0),
                     CIVector(x: 0, y: 0, z: 1, w: 0)][channel]
        filter.setValue(CIImage(cgImage: cg), forKey: kCIInputImageKey)
        filter.setValue(basis, forKey: "inputRVector")
        filter.setValue(basis, forKey: "inputGVector")
        filter.setValue(basis, forKey: "inputBVector")
        guard let out = filter.outputImage else { return nil }
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let ocg = ctx.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: ocg)
    }

    /// Mean CIELAB over the (downsampled) image.
    func meanLab() -> (L: Float, a: Float, b: Float)? {
        guard let cg = cgImage else { return nil }
        let n = 32
        var buf = [UInt8](repeating: 0, count: n * n * 4)
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: n, height: n,
                bitsPerComponent: 8, bytesPerRow: n * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard ok else { return nil }
        var sL: Float = 0, sA: Float = 0, sB: Float = 0
        for i in stride(from: 0, to: buf.count, by: 4) {
            let lab = CIELAB.lab(r: buf[i], g: buf[i + 1], b: buf[i + 2])
            sL += lab.L; sA += lab.a; sB += lab.b
        }
        let count = Float(n * n)
        return (sL / count, sA / count, sB / count)
    }
}

extension String {
    /// Offline link detection — NSDataDetector, nothing leaves the device.
    var detectedLinks: [URL] {
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }
        let range = NSRange(startIndex..., in: self)
        return detector.matches(in: self, range: range).compactMap { m in
            if let url = m.url { return url }
            if let phone = m.phoneNumber {
                return URL(string: "tel:\(phone.filter { !$0.isWhitespace })")
            }
            return nil
        }
    }
}
