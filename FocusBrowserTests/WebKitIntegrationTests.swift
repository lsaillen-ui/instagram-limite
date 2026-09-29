import Testing
import WebKit
@testable import FocusBrowser

/// Runs the bundled scripts in a real (offline) WKWebView.
@MainActor
struct WebKitIntegrationTests {
    private final class Harness: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var paths: [String] = []
        private var loadContinuation: CheckedContinuation<Void, Never>?

        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            if let path = RouteMessage.path(from: m.body) { paths.append(path) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadContinuation?.resume()
            loadContinuation = nil
        }

        func load(_ html: String, in webView: WKWebView) async {
            await withCheckedContinuation { continuation in
                loadContinuation = continuation
                webView.loadHTMLString(html, baseURL: URL(string: "https://www.instagram.com/direct/inbox/"))
            }
        }

        func waitForPaths(_ count: Int) async {
            for _ in 0..<100 where paths.count < count {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func makeWebView(_ harness: Harness) -> WKWebView {
        let configuration = BrowserConfiguration.makeWebViewConfiguration(routeHandler: harness)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
        webView.navigationDelegate = harness
        return webView
    }

    @Test func routeHookReportsInitialAndClientSideRoutes() async {
        let harness = Harness()
        let webView = makeWebView(harness)
        await harness.load("<html><head></head><body></body></html>", in: webView)
        await harness.waitForPaths(1)
        #expect(harness.paths.first == "/direct/inbox/")

        _ = try? await webView.evaluateJavaScript("history.pushState({}, '', '/direct/t/123/'); 0")
        _ = try? await webView.evaluateJavaScript("history.replaceState({}, '', '/p/abc/'); 0")
        await harness.waitForPaths(3)
        #expect(harness.paths == ["/direct/inbox/", "/direct/t/123/", "/p/abc/"])
    }

    @Test func baseScriptForcesViewportAndInstallsCSS() async throws {
        let harness = Harness()
        let webView = makeWebView(harness)
        await harness.load(
            "<html><head><meta name='viewport' content='width=500'></head><body><input id='i'></body></html>",
            in: webView
        )
        let content = try await webView.evaluateJavaScript(
            "document.querySelector('meta[name=viewport]').getAttribute('content')"
        ) as? String
        #expect(content?.contains("user-scalable=no") == true)
        #expect(content?.contains("viewport-fit=cover") == true)

        let fontSize = try await webView.evaluateJavaScript(
            "getComputedStyle(document.getElementById('i')).fontSize"
        ) as? String
        #expect(fontSize == "16px")
    }
}
