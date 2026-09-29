import SwiftUI

/// Placeholder shell: the web view, plus a cover for external links.
struct RootView: View {
    @Bindable var engine: BrowserEngine

    var body: some View {
        WebViewContainer(webView: engine.webView)
            .background(Color(.systemBackground))
            .fullScreenCover(item: $engine.safariRequest) { request in
                SafariView(url: request.url).ignoresSafeArea()
            }
    }
}
