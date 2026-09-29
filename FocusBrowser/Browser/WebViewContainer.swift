import SwiftUI
import WebKit

/// Hosts the engine's single `WKWebView`. It never creates or recreates one.
struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
