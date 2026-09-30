import Testing
import WebKit
@testable import FocusBrowser

/// Runs the bundled scripts in a real (offline) WKWebView.
@MainActor
struct WebKitIntegrationTests {
    private final class Harness: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var events: [RouteEvent] = []
        private var loadContinuation: CheckedContinuation<Void, Never>?

        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            if let event = RouteMessage.event(from: m.body) { events.append(event) }
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

        func waitForEvents(_ count: Int) async {
            for _ in 0..<100 where events.count < count {
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
        await harness.waitForEvents(1)
        #expect(harness.events.first == RouteEvent(path: "/direct/inbox/", kind: .initial))

        _ = try? await webView.evaluateJavaScript("history.pushState({}, '', '/direct/t/123/'); 0")
        _ = try? await webView.evaluateJavaScript("history.replaceState({}, '', '/p/abc/'); 0")
        // A synthetic popstate: a real history traversal in an offline page is slow and flaky.
        _ = try? await webView.evaluateJavaScript("window.dispatchEvent(new PopStateEvent('popstate')); 0")
        await harness.waitForEvents(4)
        #expect(harness.events == [
            RouteEvent(path: "/direct/inbox/", kind: .initial),
            RouteEvent(path: "/direct/t/123/", kind: .push),
            RouteEvent(path: "/p/abc/", kind: .replace),
            RouteEvent(path: "/p/abc/", kind: .pop),
        ])
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

    #if DEBUG
    // MARK: recon.js (DEBUG only)

    private static let reconFixture = """
    <html><head></head><body>
    <main><a href="/direct/t/98765/" aria-label="Open chat">chat</a></main>
    <nav>
      <a href="/"><svg aria-label="Home"></svg></a>
      <a href="/explore/"><svg aria-label="Explore"></svg></a>
      <a href="/reels/"><svg aria-label="Reels"></svg></a>
      <a href="/bob/"></a>
    </nav>
    <div role="dialog"><div role="presentation"><button aria-label="Close">x</button></div></div>
    <div style="height:100px;overflow-y:auto"><div style="height:500px"><video></video></div></div>
    <a href="https://l.instagram.com/?u=https%3A%2F%2Fsecret.example%2Fpath">external</a>
    </body></html>
    """

    private func focusResult(_ script: String, arguments: [String: Any] = [:], in webView: WKWebView) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            script, arguments: arguments, in: nil, contentWorld: BrowserConfiguration.focusWorld
        )
    }

    @Test func reconSnapshotDescribesTheStructureWithoutLeakingIdentifiers() async throws {
        let harness = Harness()
        let webView = makeWebView(harness)
        await harness.load(Self.reconFixture, in: webView)

        let redactor = PathRedactor(salt: "s1")
        let raw = try await focusResult("return __focusRecon.snapshot(salt);", arguments: ["salt": redactor.salt], in: webView)
        let snapshot = try #require(raw as? [String: Any])
        let json = String(decoding: try JSONSerialization.data(withJSONObject: snapshot), as: UTF8.self)

        #expect(snapshot["path"] as? String == "/direct/inbox/")
        #expect(snapshot["historyLength"] as? Int != nil)
        for leaked in ["bob", "98765", "secret"] { #expect(!json.contains(leaked)) }

        let links = try #require(snapshot["links"] as? [[String: Any]])
        // Navigation links are listed first.
        #expect((links.first?["in"] as? [String])?.contains("nav") == true)
        let hrefs = links.compactMap { $0["href"] as? String }
        #expect(hrefs.contains("/explore/"))
        #expect(hrefs.contains("/reels/"))
        #expect(hrefs.contains("/@\(redactor.token(for: "bob"))/"))
        #expect(hrefs.contains("/direct/t/\(redactor.token(for: "98765"))/"))
        #expect(hrefs.contains("l.instagram.com/…?"))
        let home = try #require(links.first { $0["href"] as? String == "/" })
        #expect(home["label"] as? String == "Home")

        let labels = try #require(snapshot["labels"] as? [String])
        #expect(labels.contains("svg:Home"))
        #expect(labels.contains("button:Close"))

        let dialogs = try #require(snapshot["dialogs"] as? [String: Any])
        #expect(dialogs["count"] as? Int == 1)
        #expect((dialogs["structure"] as? [[String: Any]])?.first?["role"] as? String == "dialog")

        let scrollers = try #require(snapshot["scrollers"] as? [[String: Any]])
        #expect(scrollers.contains { $0["video"] as? Bool == true && $0["scrollHeight"] as? Int == 500 })

        let videos = try #require(snapshot["videos"] as? [String: Any])
        #expect(videos["count"] as? Int == 1)
        #expect(videos["playing"] as? Int == 0)
    }

    @Test func reconRedactionMatchesSwift() async throws {
        let harness = Harness()
        let webView = makeWebView(harness)
        await harness.load("<html><head></head><body></body></html>", in: webView)

        let redactor = PathRedactor(salt: "parity-salt")
        var paths = [
            "/", "/direct/inbox/", "/direct/t/178412/", "/reel/Cx9aB/", "/reels/", "/p/Dp3/",
            "/stories/louis/3301/", "/louis/", "/louis/reels/", "/louis", "/explore/tags/cats/",
            "/accounts/password/reset/confirm/abc/def/", "/Direct/Inbox/", "//", "/a//b/", "/é/",
            "/direct/inbox/?x=1#y",
        ]
        paths += ReservedSegments.firstSegments.map { "/\($0)/x/" }
        paths += ReservedSegments.knownSubsegments.map { "/somebody/\($0)/x/" }

        for path in paths {
            let js = try await focusResult(
                "return __focusRecon.redactPath(path, salt);",
                arguments: ["path": path, "salt": redactor.salt],
                in: webView
            ) as? String
            #expect(js == redactor.redact(path), "path: \(path)")
        }
    }
    #endif
}
