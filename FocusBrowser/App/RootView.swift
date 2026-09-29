import SwiftUI

/// Placeholder shell: just the web view.
struct RootView: View {
    let engine: BrowserEngine

    var body: some View {
        WebViewContainer(webView: engine.webView)
            .background(Color(.systemBackground))
    }
}
