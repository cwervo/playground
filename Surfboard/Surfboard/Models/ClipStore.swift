//
//  ClipStore.swift
//  Surfboard
//
//  Owns the collection of saved clips and all persistence. Metadata is kept
//  in a single JSON index; binary payloads live as individual files in a
//  "Clips" directory inside Application Support. Everything here uses only
//  Foundation / UIKit / UniformTypeIdentifiers — no third party code.
//

import Foundation
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ClipStore: ObservableObject {

    /// Newest first.
    @Published private(set) var clips: [Clip] = []

    private let fileManager = FileManager.default

    /// Directory that holds the binary payloads.
    private lazy var clipsDirectory: URL = {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Surfboard/Clips", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// JSON index of all clip metadata.
    private lazy var indexURL: URL = {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Surfboard", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("index.json")
    }()

    init() {
        load()
    }

    // MARK: - Reads

    func payloadURL(for clip: Clip) -> URL? {
        guard let name = clip.fileName else { return nil }
        return clipsDirectory.appendingPathComponent(name)
    }

    func payloadData(for clip: Clip) -> Data? {
        guard let url = payloadURL(for: clip) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// A thumbnail image for image clips (or a video poster frame if present).
    func thumbnail(for clip: Clip) -> UIImage? {
        guard clip.kind == .image, let data = payloadData(for: clip) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Adding clips

    /// Save a plain string typed by the user.
    func addText(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let kind: ClipKind = looksLikeURL(trimmed) ? .link : .text
        let clip = Clip(kind: kind, inlineText: trimmed, uti: kind == .link ? UTType.url.identifier : UTType.plainText.identifier)
        insert(clip)
    }

    /// Pull whatever is currently on the system pasteboard and save it.
    /// Handles images, URLs, strings and arbitrary file item providers so we
    /// can capture "any and all content save-able to the iOS keyboard".
    /// Returns a short description of what was captured, or nil if empty.
    @discardableResult
    func addFromPasteboard() -> String? {
        let pb = UIPasteboard.general

        // 1. Images (screenshots, copied photos).
        if pb.hasImages, let image = pb.image, let data = image.pngData() {
            let clip = writeBinary(data, kind: .image, uti: UTType.png.identifier, suggestedName: "Pasted Image.png")
            insert(clip)
            return "image"
        }

        // 2. URLs / links.
        if pb.hasURLs, let url = pb.url {
            addText(url.absoluteString)
            return "link"
        }

        // 3. Arbitrary typed data via item providers (files, video, audio…).
        if let provider = pb.itemProviders.first,
           let typeID = provider.registeredTypeIdentifiers.first,
           let type = UTType(typeID),
           !type.conforms(to: .plainText) {
            if let data = pb.data(forPasteboardType: typeID) {
                let kind = ClipKind.kind(for: type)
                let ext = type.preferredFilenameExtension.map { "." + $0 } ?? ""
                let clip = writeBinary(data, kind: kind, uti: typeID, suggestedName: "Pasted \(kind.label)\(ext)")
                insert(clip)
                return kind.label.lowercased()
            }
        }

        // 4. Plain text fallback.
        if pb.hasStrings, let string = pb.string {
            addText(string)
            return looksLikeURL(string) ? "link" : "text"
        }

        return nil
    }

    /// Save raw data with an explicit kind — used by the share/photo importers.
    func addBinary(_ data: Data, kind: ClipKind, uti: String, suggestedName: String) {
        insert(writeBinary(data, kind: kind, uti: uti, suggestedName: suggestedName))
    }

    // MARK: - Deleting

    func delete(_ clip: Clip) {
        if let url = payloadURL(for: clip) {
            try? fileManager.removeItem(at: url)
        }
        clips.removeAll { $0.id == clip.id }
        save()
    }

    /// Nuke everything: metadata index and every stored payload.
    func deleteAllData() {
        for clip in clips {
            if let url = payloadURL(for: clip) {
                try? fileManager.removeItem(at: url)
            }
        }
        clips.removeAll()
        try? fileManager.removeItem(at: indexURL)
        // Recreate the (now empty) clips directory.
        try? fileManager.removeItem(at: clipsDirectory)
        try? fileManager.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
        save()
    }

    // MARK: - Persistence

    private func insert(_ clip: Clip) {
        clips.insert(clip, at: 0)
        save()
    }

    private func writeBinary(_ data: Data, kind: ClipKind, uti: String, suggestedName: String) -> Clip {
        let id = UUID()
        let ext = (suggestedName as NSString).pathExtension
        let storedName = ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)"
        let url = clipsDirectory.appendingPathComponent(storedName)
        try? data.write(to: url, options: .atomic)
        return Clip(
            id: id,
            kind: kind,
            inlineText: suggestedName,
            fileName: storedName,
            uti: uti,
            byteSize: data.count
        )
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Clip].self, from: data) {
            clips = decoded.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(clips) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: - Helpers

    private func looksLikeURL(_ string: String) -> Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return false
        }
        let range = NSRange(string.startIndex..., in: string)
        if let match = detector.firstMatch(in: string, options: [], range: range) {
            return match.range == range && match.url != nil
        }
        return false
    }
}
