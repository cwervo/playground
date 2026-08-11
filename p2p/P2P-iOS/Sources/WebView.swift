import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    @Binding var htmlContent: String
    @Binding var showText: Bool
    var webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url == nil && !htmlContent.isEmpty {
            uiView.loadHTMLString(htmlContent, baseURL: nil)
        } else if uiView.url != nil {
            let js = "window.toggleTextVisibility && window.toggleTextVisibility(\(showText));"
            uiView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
