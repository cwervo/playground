//
//  Clip.swift
//  Surfboard
//
//  A "Clip" is any piece of content that can live on the iOS clipboard /
//  keyboard: text, links, images, video, audio and arbitrary files.
//  Everything is normalised into this single value type so the gallery can
//  display them uniformly regardless of their underlying payload.
//

import Foundation
import UniformTypeIdentifiers

/// The broad family a clip belongs to. Used to pick an icon, a preview style
/// and a sensible label in the gallery.
enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text
    case link
    case image
    case video
    case audio
    case file

    /// SF Symbol used when there is no visual thumbnail to show.
    var symbolName: String {
        switch self {
        case .text:  return "text.alignleft"
        case .link:  return "link"
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .file:  return "doc"
        }
    }

    var label: String {
        switch self {
        case .text:  return "Text"
        case .link:  return "Link"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .file:  return "File"
        }
    }

    /// Best-effort mapping from a Uniform Type Identifier to a clip kind.
    static func kind(for type: UTType) -> ClipKind {
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .url) { return .link }
        if type.conforms(to: .text) { return .text }
        return .file
    }
}

/// A single saved item in the gallery.
///
/// Small payloads (text, links) are stored inline in `inlineText`. Larger
/// binary payloads (images, video, files) are written to disk and referenced
/// by `fileName`, keeping the metadata index cheap to load.
struct Clip: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: ClipKind
    var createdAt: Date

    /// Inline textual payload for `.text` / `.link` clips, or a caption /
    /// original filename for binary clips.
    var inlineText: String?

    /// Name of the on-disk payload inside the Clips directory, if any.
    var fileName: String?

    /// The original Uniform Type Identifier of the payload, when known.
    var uti: String?

    /// Size of the on-disk payload in bytes, when known.
    var byteSize: Int?

    init(
        id: UUID = UUID(),
        kind: ClipKind,
        createdAt: Date = Date(),
        inlineText: String? = nil,
        fileName: String? = nil,
        uti: String? = nil,
        byteSize: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.inlineText = inlineText
        self.fileName = fileName
        self.uti = uti
        self.byteSize = byteSize
    }

    /// A short, human friendly one-liner describing the clip for the gallery.
    var previewTitle: String {
        if let text = inlineText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let single = text.replacingOccurrences(of: "\n", with: " ")
            return String(single.prefix(80))
        }
        if let name = fileName { return name }
        return kind.label
    }

    /// Whether this clip carries an on-disk binary payload.
    var hasPayloadFile: Bool { fileName != nil }
}
