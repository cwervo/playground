import Foundation
import Vision
import UIKit

struct RecognizedTextBlock {
    let text: String
    let boundingBox: CGRect // Normalized coordinates
}

class OCRManager: ObservableObject {
    @Published var recognizedTexts: [RecognizedTextBlock] = []
    @Published var isProcessing: Bool = false

    func processImage(_ image: UIImage) {
        guard let cgImage = image.cgImage else {
            return
        }

        self.isProcessing = true
        self.recognizedTexts = []

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                print("OCR Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
                return
            }

            var blocks: [RecognizedTextBlock] = []
            for observation in observations {
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                blocks.append(RecognizedTextBlock(text: topCandidate.string, boundingBox: observation.boundingBox))
            }

            DispatchQueue.main.async {
                self.recognizedTexts = blocks
                self.isProcessing = false
            }
        }

        request.recognitionLevel = .accurate

        do {
            try requestHandler.perform([request])
        } catch {
            print("Failed to perform OCR: \(error)")
            DispatchQueue.main.async {
                self.isProcessing = false
            }
        }
    }
}
