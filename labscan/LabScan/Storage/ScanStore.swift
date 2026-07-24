import Foundation
import UIKit

/// A captured scan: JPEG + JSON sidecar, both local-only.
struct ScanRecord: Identifiable, Codable {
    var id: UUID
    var date: Date
    var decode: String?
    var symbology: String?
    var quadLabels: [String]
    /// Offline OCR / barcode / AprilTag results; nil until analyzed.
    var detections: [Detection]?

    var imageFilename: String { "\(id.uuidString).jpg" }
    var sidecarFilename: String { "\(id.uuidString).json" }
}

/// Saves captures under Documents/Scans and keeps them out of iCloud/device
/// backups — the photos never leave the phone unless you export them yourself.
final class ScanStore: ObservableObject {
    @Published private(set) var records: [ScanRecord] = []

    static let directory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var dir = docs.appendingPathComponent("Scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }()

    init() { load() }

    func load() {
        let dir = Self.directory
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        records = files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(ScanRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    func save(image: UIImage, decode: BarcodeDecode?, quads: [PaperQuad]) {
        let record = ScanRecord(
            id: UUID(), date: Date(),
            decode: decode?.value, symbology: decode?.symbology,
            quadLabels: quads.map(\.label))
        let dir = Self.directory
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        do {
            try jpeg.write(to: dir.appendingPathComponent(record.imageFilename))
            try encoder.encode(record).write(to: dir.appendingPathComponent(record.sidecarFilename))
            records.insert(record, at: 0)
        } catch {
            // Local disk write failed; nothing else to do offline.
            return
        }

        // Full offline read (OCR, codes, AprilTags) off the main thread;
        // results land back in the sidecar.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let detections = StillAnalyzer.analyze(image)
            DispatchQueue.main.async {
                guard let self, var updated = self.records.first(where: { $0.id == record.id }) else { return }
                updated.detections = detections
                self.update(updated)
            }
        }
    }

    /// Rewrite a record's sidecar (e.g. after analysis) and republish it.
    func update(_ record: ScanRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(record).write(to: Self.directory.appendingPathComponent(record.sidecarFilename))
        if let i = records.firstIndex(where: { $0.id == record.id }) {
            records[i] = record
        }
    }

    func delete(_ record: ScanRecord) {
        let dir = Self.directory
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(record.imageFilename))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(record.sidecarFilename))
        records.removeAll { $0.id == record.id }
    }

    func image(for record: ScanRecord) -> UIImage? {
        UIImage(contentsOfFile: Self.directory.appendingPathComponent(record.imageFilename).path)
    }
}
