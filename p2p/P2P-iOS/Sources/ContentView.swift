import SwiftUI
import UniformTypeIdentifiers
import WebKit
import PhotosUI

struct ContentView: View {
    @StateObject private var ocrManager = OCRManager()
    @StateObject private var cameraManager = CameraManager()
    @State private var image: UIImage?
    @State private var htmlContent: String = ""
    @State private var showText: Bool = true
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var shareURL: URL?
    @State private var showShareSheet: Bool = false

    let webView = WKWebView()

    var body: some View {
        ZStack {
            // Main Area
            if image == nil {
                // Camera View
                if let cgImage = cameraManager.currentFrame {
                    Image(uiImage: UIImage(cgImage: cgImage))
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            processNewImage(UIImage(cgImage: cgImage))
                        }
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { value in
                                    if abs(value.translation.width) > abs(value.translation.height) {
                                        cameraManager.switchCamera(next: value.translation.width < 0)
                                    }
                                }
                        )
                } else {
                    VStack {
                        ProgressView()
                        Text(cameraManager.isAuthorized ? "Loading Camera..." : "Camera access is required")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .ignoresSafeArea()
                }
            } else {
                // WebView with OCR Content
                ZStack {
                    WebView(htmlContent: $htmlContent, showText: $showText, webView: webView)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()

                    if ocrManager.isProcessing {
                        ProgressView("Analyzing Image...")
                            .padding()
                            .background(Color(UIColor.systemBackground).opacity(0.8))
                            .cornerRadius(8)
                    }
                }
                .onChange(of: ocrManager.recognizedTexts.count) { _, _ in
                    if let image = image, !ocrManager.isProcessing {
                        htmlContent = HTMLTemplate.generateHTML(for: image, texts: ocrManager.recognizedTexts, showText: showText)
                    }
                }
            }

            // Floating UI Bottom
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    if image != nil {
                        Toggle("Show Text", isOn: $showText)
                            .toggleStyle(.switch)
                            .labelsHidden()
                        Text("Text").font(.caption).foregroundColor(.white)

                        Button("Clear") {
                            self.image = nil
                            self.htmlContent = ""
                        }
                        .foregroundColor(.white)

                        Menu {
                            Button("Export as HTML") { export(format: .html) }
                            Button("Export as PNG") { export(format: .png) }
                            Button("Export as JPG") { export(format: .jpg) }
                            Button("Export as PDF") { export(format: .pdf) }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.white)
                        }
                    } else {
                        Text("Tap to capture")
                            .font(.caption)
                            .foregroundColor(.white)

                        Button(action: { cameraManager.switchCamera(next: true) }) {
                            Image(systemName: "camera.rotate")
                                .foregroundColor(.white)
                        }

                        PhotosPicker(selection: $photoPickerItem, matching: .images) {
                            Image(systemName: "photo")
                                .foregroundColor(.white)
                        }

                        Button(action: { pasteFromClipboard() }) {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .tint(.white)
        .preferredColorScheme(.dark)
        .onChange(of: photoPickerItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let newImage = UIImage(data: data) {
                    processNewImage(newImage)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                ActivityView(activityItems: [shareURL])
            }
        }
    }

    private func processNewImage(_ newImage: UIImage) {
        self.image = newImage
        self.htmlContent = ""
        ocrManager.processImage(newImage)
    }

    private func pasteFromClipboard() {
        if let pasteboardImage = UIPasteboard.general.image {
            processNewImage(pasteboardImage)
        }
    }

    enum ExportFormat {
        case html, png, jpg, pdf
    }

    private func export(format: ExportFormat) {
        let tmpDir = FileManager.default.temporaryDirectory
        switch format {
        case .html:
            webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                let htmlString = (result as? String) ?? htmlContent
                let url = tmpDir.appendingPathComponent("ExportedImage.html")
                try? htmlString.write(to: url, atomically: true, encoding: .utf8)
                presentShare(url: url)
            }
        case .png:
            webView.takeSnapshot(with: nil) { image, error in
                guard let image, let data = image.pngData() else { return }
                let url = tmpDir.appendingPathComponent("ExportedImage.png")
                try? data.write(to: url)
                presentShare(url: url)
            }
        case .jpg:
            webView.takeSnapshot(with: nil) { image, error in
                guard let image, let data = image.jpegData(compressionQuality: 0.9) else { return }
                let url = tmpDir.appendingPathComponent("ExportedImage.jpg")
                try? data.write(to: url)
                presentShare(url: url)
            }
        case .pdf:
            let pdfConfig = WKPDFConfiguration()
            webView.createPDF(configuration: pdfConfig) { result in
                switch result {
                case .success(let data):
                    let url = tmpDir.appendingPathComponent("ExportedImage.pdf")
                    try? data.write(to: url)
                    presentShare(url: url)
                case .failure(let error):
                    print("PDF creation failed: \(error)")
                }
            }
        }
    }

    private func presentShare(url: URL) {
        DispatchQueue.main.async {
            self.shareURL = url
            self.showShareSheet = true
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
