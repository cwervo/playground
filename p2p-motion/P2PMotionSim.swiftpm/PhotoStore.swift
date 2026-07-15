import UIKit

// Network-last, on-device photo store for the hub.
// JPEGs live as files in Documents/p2p-motion/ with a JSON index; nothing ever
// leaves the device. Oldest photos are evicted when the storage budget fills.

struct PhotoRecord: Codable, Identifiable {
    let id: Int
    let date: Date
    let frame: Int
    let bytes: Int
    let pkts: Int
    let retries: Int
    let link: String
    let quality: Double
    let filename: String
}

@MainActor
final class PhotoStore: ObservableObject {
    @Published private(set) var photos: [PhotoRecord] = []

    static let budgetBytes = 4_200_000

    private let dir: URL
    private let indexURL: URL
    private var nextId = 1
    private var imageCache: [Int: UIImage] = [:]   // gallery re-renders often; avoid per-frame disk reads

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("p2p-motion", isDirectory: true)
        indexURL = dir.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let recs = try? JSONDecoder().decode([PhotoRecord].self, from: data) {
            photos = recs
        }
        nextId = (photos.map(\.id).max() ?? 0) + 1
    }

    var totalBytes: Int { photos.reduce(0) { $0 + $1.bytes } }

    func add(jpeg: Data, frame: Int, pkts: Int, retries: Int, link: String, quality: Double) -> PhotoRecord {
        let rec = PhotoRecord(id: nextId, date: Date(), frame: frame, bytes: jpeg.count,
                              pkts: pkts, retries: retries, link: link, quality: quality,
                              filename: "photo-\(nextId).jpg")
        nextId += 1
        try? jpeg.write(to: dir.appendingPathComponent(rec.filename))
        photos.append(rec)
        while totalBytes > Self.budgetBytes, photos.count > 1 {
            delete(photos[0])
        }
        saveIndex()
        return rec
    }

    func image(for rec: PhotoRecord) -> UIImage? {
        if let cached = imageCache[rec.id] { return cached }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(rec.filename)),
              let img = UIImage(data: data) else { return nil }
        imageCache[rec.id] = img
        return img
    }

    func delete(_ rec: PhotoRecord) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(rec.filename))
        photos.removeAll { $0.id == rec.id }
        imageCache[rec.id] = nil
        saveIndex()
    }

    func clear() {
        for rec in photos {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(rec.filename))
        }
        photos = []
        imageCache = [:]
        saveIndex()
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(photos) {
            try? data.write(to: indexURL)
        }
    }
}
