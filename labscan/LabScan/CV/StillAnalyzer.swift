import Foundation
import UIKit
import Vision

/// Something found in a captured still. Boxes are normalized to the image,
/// origin top-left (converted from Vision's bottom-left on the way in).
struct Detection: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case text, barcode, qr, dataMatrix, aprilTag
    }
    var id = UUID()
    var kind: Kind
    var payload: String
    /// Symbology / family detail ("EAN-13", "AprilTag tag36h11"…).
    var detail: String?
    var confidence: Float
    var x: Double, y: Double, w: Double, h: Double

    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }

    init(kind: Kind, payload: String, detail: String?, confidence: Float, visionBox bb: CGRect) {
        self.kind = kind
        self.payload = payload
        self.detail = detail
        self.confidence = confidence
        x = bb.minX
        y = 1 - bb.maxY
        w = bb.width
        h = bb.height
    }
}

/// The full offline read of a captured still: Apple-native OCR and barcode
/// detection (Vision, entirely on-device) plus the hand-rolled AprilTag
/// decoder. Runs once per capture; results land in the JSON sidecar.
enum StillAnalyzer {
    static func analyze(_ image: UIImage) -> [Detection] {
        guard let cg = image.cgImage else { return [] }
        var out: [Detection] = []

        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true

        let codes = VNDetectBarcodesRequest()
        codes.symbologies = [
            .qr, .microQR, .dataMatrix, .aztec, .pdf417,
            .ean13, .ean8, .upce, .code39, .code93, .code128, .itf14, .codabar,
        ]

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([text, codes])

        for obs in text.results ?? [] {
            guard let top = obs.topCandidates(1).first, !top.string.isEmpty else { continue }
            out.append(Detection(kind: .text, payload: top.string, detail: nil,
                                 confidence: top.confidence, visionBox: obs.boundingBox))
        }
        for obs in codes.results ?? [] {
            guard let value = obs.payloadStringValue else { continue }
            let kind: Detection.Kind
            switch obs.symbology {
            case .qr, .microQR: kind = .qr
            case .dataMatrix: kind = .dataMatrix
            default: kind = .barcode
            }
            out.append(Detection(kind: kind, payload: value, detail: name(obs.symbology),
                                 confidence: obs.confidence, visionBox: obs.boundingBox))
        }
        out += AprilTagDetector.detect(cgImage: cg)
        return out
    }

    private static func name(_ s: VNBarcodeSymbology) -> String {
        switch s {
        case .qr: return "QR"
        case .microQR: return "Micro QR"
        case .dataMatrix: return "DataMatrix"
        case .aztec: return "Aztec"
        case .pdf417: return "PDF417"
        case .ean13: return "EAN-13"
        case .ean8: return "EAN-8"
        case .upce: return "UPC-E"
        case .code39: return "Code 39"
        case .code93: return "Code 93"
        case .code128: return "Code 128"
        case .itf14: return "ITF-14"
        case .codabar: return "Codabar"
        default: return s.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
        }
    }
}
