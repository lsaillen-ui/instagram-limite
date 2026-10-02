import Testing
import WebKit
@testable import FocusBrowser

/// `BrowserEngine.apply(_:)` swaps the config of a live web view, offline.
@MainActor
struct HotApplyTests {
    private let page = "<html><head></head><body><p id='a'>a</p><p id='b'>b</p></body></html>"

    private func config(hiding selector: String, revision: String, redirectTo: String = "/direct/inbox/") -> FilterConfig {
        var config = FilterConfig.bundledDefault()
        config.revision = revision
        config.routes.redirectHomeTo = redirectTo
        config.rules = [.init(id: "hide.test", hide: selector)]
        return config
    }

    private func display(of id: String, in webView: WKWebView) async -> String? {
        try? await webView.evaluateJavaScript("getComputedStyle(document.getElementById('\(id)')).display") as? String
    }

    private func waitUntil(_ id: String, is expected: String, in webView: WKWebView) async -> Bool {
        for _ in 0..<100 {
            if await display(of: id, in: webView) == expected { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private func load(_ html: String, in webView: WKWebView) {
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.instagram.com/direct/inbox/"))
    }

    @Test func appliesTheNewRulesToTheCurrentPageWithoutReloading() async {
        let engine = BrowserEngine(loadOnInit: false, filterConfig: config(hiding: "#a", revision: "1"))
        load(page, in: engine.webView)
        #expect(await waitUntil("a", is: "none", in: engine.webView))
        #expect(await display(of: "b", in: engine.webView) == "block")

        _ = try? await engine.webView.evaluateJavaScript("window.marker = 42; 0")
        await engine.apply(config(hiding: "#b", revision: "2"))

        #expect(await waitUntil("a", is: "block", in: engine.webView))
        #expect(await display(of: "b", in: engine.webView) == "none")
        let marker = try? await engine.webView.evaluateJavaScript("window.marker") as? Int
        #expect(marker == 42)  // same document: no reload
    }

    @Test func theNewRulesAlsoApplyToTheNextPageLoad() async {
        let engine = BrowserEngine(loadOnInit: false, filterConfig: config(hiding: "#a", revision: "1"))
        load(page, in: engine.webView)
        #expect(await waitUntil("a", is: "none", in: engine.webView))

        await engine.apply(config(hiding: "#b", revision: "2"))
        load(page + " ", in: engine.webView)

        #expect(await waitUntil("b", is: "none", in: engine.webView))
        #expect(await display(of: "a", in: engine.webView) == "block")
    }
}
