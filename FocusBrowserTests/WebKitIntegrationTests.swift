import Testing
import WebKit
@testable import FocusBrowser

/// Runs the bundled scripts in a real (offline) WKWebView.
@MainActor
struct WebKitIntegrationTests {
    private final class Harness: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var events: [RouteEvent] = []
        var healthFailures: [HealthFailure] = []
        private var loadContinuation: CheckedContinuation<Void, Never>?

        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            if let event = RouteMessage.event(from: m.body) { events.append(event) }
            if let failure = FocusHealthMessage.failure(from: m.body) { healthFailures.append(failure) }
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

        func waitForHealth(_ count: Int) async {
            for _ in 0..<100 where healthFailures.count < count {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }

        func waitForEvents(_ count: Int) async {
            for _ in 0..<100 where events.count < count {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func makeWebView(_ harness: Harness, config: FilterConfig = .bundledDefault()) -> WKWebView {
        let configuration = BrowserConfiguration.makeWebViewConfiguration(routeHandler: harness, filterConfig: config)
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

    // MARK: focus engine

    private func config(rules: [FilterConfig.Rule]) -> FilterConfig {
        var config = FilterConfig.bundledDefault()
        config.rules = rules
        return config
    }

    private func focusValue(_ script: String, arguments: [String: Any] = [:], in webView: WKWebView) async throws -> Any? {
        try await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: BrowserConfiguration.focusWorld)
    }

    private func display(of id: String, in webView: WKWebView) async throws -> String? {
        try await webView.evaluateJavaScript("getComputedStyle(document.getElementById('\(id)')).display") as? String
    }

    @Test func hiddenRulesComputeToDisplayNone() async throws {
        let harness = Harness()
        let webView = makeWebView(harness, config: config(rules: [
            .init(id: "hide.a", hide: "#a"),
            .init(id: "hide.wrapper", hide: "*:has(> #b:only-child)"),
        ]))
        await harness.load("<html><head></head><body><p id='a'>a</p><div id='w'><span id='b'>b</span></div><p id='c'>c</p></body></html>", in: webView)
        #expect(try await display(of: "a", in: webView) == "none")
        #expect(try await display(of: "w", in: webView) == "none")
        #expect(try await display(of: "c", in: webView) == "block")
    }

    @Test func rulesAlsoApplyToNodesAddedLater() async throws {
        let harness = Harness()
        let webView = makeWebView(harness, config: config(rules: [.init(id: "hide.late", hide: "a[href='/explore/']")]))
        await harness.load("<html><head></head><body></body></html>", in: webView)
        _ = try await webView.evaluateJavaScript("document.body.innerHTML = \"<a id='late' href='/explore/'>x</a>\"; 0")
        #expect(try await display(of: "late", in: webView) == "none")
    }

    @Test func anInvalidSelectorIsSkippedAndReportedWithoutBreakingTheOthers() async throws {
        let harness = Harness()
        let webView = makeWebView(harness, config: config(rules: [
            .init(id: "hide.first", hide: "#a"),
            .init(id: "broken", hide: "a["),
            .init(id: "hide.last", hide: "#c"),
        ]))
        await harness.load("<html><head></head><body><p id='a'>a</p><p id='c'>c</p></body></html>", in: webView)
        #expect(try await display(of: "a", in: webView) == "none")
        #expect(try await display(of: "c", in: webView) == "none")
        await harness.waitForHealth(1)
        #expect(harness.healthFailures == [HealthFailure(ruleId: "broken", path: "/direct/inbox/", reason: "invalid")])
    }

    @Test func applyReportsWhatItAppliedAndSkipped() async throws {
        let harness = Harness()
        let webView = makeWebView(harness)
        await harness.load("<html><head></head><body></body></html>", in: webView)
        let json = try config(rules: [.init(id: "ok", hide: "#a"), .init(id: "bad", hide: "a[")]).pageJSON()
        let cfg = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let report = try await focusValue("return __focus.apply(cfg);", arguments: ["cfg": cfg], in: webView) as? [String: Any]
        #expect(report?["applied"] as? Int == 1)
        #expect(report?["skipped"] as? [String] == ["bad"])
    }

    @Test func routeScopedRulesApplyOnlyOnTheirRoute() async throws {
        let harness = Harness()
        let webView = makeWebView(harness, config: config(rules: [.init(id: "reel.only", hide: "#x", routeScope: ["reel", "story"])]))
        await harness.load("<html><head></head><body><p id='x'>x</p></body></html>", in: webView)
        #expect(try await display(of: "x", in: webView) == "block")  // no route published yet
        _ = try await focusValue("__focus.setRoute('reel');", in: webView)
        #expect(try await display(of: "x", in: webView) == "none")
        _ = try await focusValue("__focus.setRoute('story');", in: webView)
        #expect(try await display(of: "x", in: webView) == "none")
        _ = try await focusValue("__focus.setRoute('post');", in: webView)
        #expect(try await display(of: "x", in: webView) == "block")
    }

    @Test func setRoutePublishesTheRouteClassOnHtml() async throws {
        let harness = Harness()
        let webView = makeWebView(harness)
        await harness.load("<html><head></head><body></body></html>", in: webView)
        _ = try await focusValue("__focus.setRoute('thread');", in: webView)
        let value = try await webView.evaluateJavaScript("document.documentElement.getAttribute('data-focus-route')") as? String
        #expect(value == "thread")
    }

    private static let clickFixture = """
    <html><head></head><body>
    <a id="explore" href="/explore/"><span id="inner">Explore</span></a>
    <a id="tag" href="/explore/tags/cats/">tag</a>
    <a id="reels" href="/reels/">reels</a>
    <a id="home" href="/">home</a>
    <a id="audio" href="/reels/audio/123/">audio</a>
    <a id="dm" href="/direct/t/1/">dm</a>
    <a id="profile" href="/bob/">profile</a>
    <a id="external" href="https://example.com/explore/">external</a>
    </body></html>
    """

    /// Whether a click on `id` got past the engine to the site's own (bubbling) handlers.
    private func clickReachesTheSite(_ id: String, in webView: WKWebView) async throws -> Bool {
        let script = """
        window.__reached = false;
        var listener = function (e) { window.__reached = true; e.preventDefault(); };  // stands in for the site, and avoids a real navigation
        document.addEventListener('click', listener);
        document.getElementById('\(id)').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
        document.removeEventListener('click', listener);
        window.__reached;
        """
        return try await webView.evaluateJavaScript(script) as? Bool ?? false
    }

    @Test func clickGuardBlocksBlockedRoutesAndOnlyThose() async throws {
        let harness = Harness()
        let webView = makeWebView(harness)
        await harness.load(Self.clickFixture, in: webView)
        _ = try await focusValue("__focus.setLoggedIn(true);", in: webView)

        for blocked in ["explore", "inner", "tag", "reels", "home", "audio"] {
            #expect(try await clickReachesTheSite(blocked, in: webView) == false, "\(blocked) should be blocked")
        }
        for allowed in ["dm", "profile", "external"] {
            #expect(try await clickReachesTheSite(allowed, in: webView) == true, "\(allowed) should be allowed")
        }
    }

    @Test func clickGuardDoesNothingWhileLoggedOut() async throws {
        let harness = Harness()
        let webView = makeWebView(harness)
        await harness.load(Self.clickFixture, in: webView)
        #expect(try await clickReachesTheSite("explore", in: webView) == true)
        _ = try await focusValue("__focus.setLoggedIn(true);", in: webView)
        _ = try await focusValue("__focus.setLoggedIn(false);", in: webView)
        #expect(try await clickReachesTheSite("home", in: webView) == true)
    }

    @Test func clickGuardFollowsTheConfigsBlockedKinds() async throws {
        var custom = FilterConfig.bundledDefault()
        custom.routes.blocked = ["explore"]
        let harness = Harness()
        let webView = makeWebView(harness, config: custom)
        await harness.load(Self.clickFixture, in: webView)
        _ = try await focusValue("__focus.setLoggedIn(true);", in: webView)
        #expect(try await clickReachesTheSite("explore", in: webView) == false)
        #expect(try await clickReachesTheSite("reels", in: webView) == true)
    }

    @Test func aRuleThatMatchesNothingWhereItMustIsReported() async throws {
        let harness = Harness()
        let webView = makeWebView(harness, config: config(rules: [
            .init(id: "healthy", hide: "#here", expectOn: ["^/direct/"]),
            .init(id: "missing", hide: "#nope", expectOn: ["^/direct/"]),
            .init(id: "elsewhere", hide: "#nope", expectOn: ["^/p/"]),
            .init(id: "no.expectation", hide: "#nope"),
        ]))
        await harness.load("<html><head></head><body><p id='here'>x</p></body></html>", in: webView)
        _ = try await focusValue("__focus.setHealthDelay(50); __focus.setRoute('inbox');", in: webView)
        await harness.waitForHealth(1)
        try? await Task.sleep(for: .milliseconds(300))  // room for wrong extra reports
        #expect(harness.healthFailures == [HealthFailure(ruleId: "missing", path: "/direct/inbox/", reason: "nomatch")])
    }

    private static let feedFixture = """
    <html><head><style>body { margin: 0 }</style></head><body>
    <div id="chat" style="height:400px;overflow-y:auto">
      <div style="height:300px"><video style="width:120px;height:200px"></video></div>
      <div style="height:900px"></div>
    </div>
    <div id="overlay" style="position:fixed;top:0;left:0;width:100%;height:100%">
      <div id="feed" style="height:100%;overflow-y:auto">
        <div style="height:800px"><video style="width:100%;height:100%"></video></div>
        <div style="height:800px"><video style="width:100%;height:100%"></video></div>
        <div style="height:800px"><video style="width:100%;height:100%"></video></div>
      </div>
    </div>
    </body></html>
    """

    @Test func aReelFeedIsLockedAndAChatWithVideosIsNot() async throws {
        let harness = Harness()
        let webView = makeWebView(harness)
        await harness.load(Self.feedFixture, in: webView)

        var locked = false
        for _ in 0..<40 where !locked {
            locked = try await webView.evaluateJavaScript("document.getElementById('feed').hasAttribute('data-focus-lock')") as? Bool ?? false
            if !locked { try? await Task.sleep(for: .milliseconds(50)) }
        }
        #expect(locked)
        #expect(try await webView.evaluateJavaScript("document.getElementById('chat').hasAttribute('data-focus-lock')") as? Bool == false)
        #expect(try await webView.evaluateJavaScript("getComputedStyle(document.getElementById('feed')).overflowY") as? String == "hidden")
        #expect(try await webView.evaluateJavaScript("getComputedStyle(document.getElementById('chat')).overflowY") as? String == "auto")
    }

    @Test func aLockedReelFeedSnapsBackFromScriptedScrolling() async throws {
        let harness = Harness()
        let webView = makeWebView(harness)
        await harness.load(Self.feedFixture, in: webView)
        for _ in 0..<40 {
            if try await webView.evaluateJavaScript("document.getElementById('feed').hasAttribute('data-focus-lock')") as? Bool == true { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        _ = try await webView.evaluateJavaScript("document.getElementById('feed').scrollTop = 800; 0")
        var top = -1
        for _ in 0..<40 where top != 0 {
            try? await Task.sleep(for: .milliseconds(50))
            top = try await webView.evaluateJavaScript("document.getElementById('feed').scrollTop") as? Int ?? -1
        }
        #expect(top == 0)
    }

    @Test func aFeedThatAppearsLaterIsLockedToo() async throws {
        let harness = Harness()
        let webView = makeWebView(harness)
        await harness.load("<html><head></head><body></body></html>", in: webView)
        _ = try await webView.evaluateJavaScript("""
        document.body.innerHTML = "<div id='feed' style='position:fixed;top:0;left:0;width:100%;height:100%;overflow-y:auto'>" +
          "<div style='height:800px'><video style='width:100%;height:100%'></video></div>" +
          "<div style='height:800px'><video style='width:100%;height:100%'></video></div></div>"; 0
        """)
        var locked = false
        for _ in 0..<40 where !locked {
            locked = try await webView.evaluateJavaScript("document.getElementById('feed').hasAttribute('data-focus-lock')") as? Bool ?? false
            if !locked { try? await Task.sleep(for: .milliseconds(50)) }
        }
        #expect(locked)
    }

    @Test func aConfigCanOnlyCarryData() async throws {
        // Even a config whose strings look like code (it never passed `decode`) reaches the page as
        // JSON string literals: nothing runs, and the engine still loads.
        let hostile = "\"});window.__pwned = 1;//"
        var bad = FilterConfig.bundledDefault()
        bad.revision = hostile
        bad.rules = [.init(id: hostile, hide: hostile, routeScope: [hostile], expectOn: [hostile])]
        bad.i18n = ["en": [hostile: hostile]]

        let harness = Harness()
        let webView = makeWebView(harness, config: bad)
        await harness.load("<html><head></head><body></body></html>", in: webView)
        #expect(try await focusValue("return typeof __focus;", in: webView) as? String == "object")
        #expect(try await focusValue("return typeof window.__pwned;", in: webView) as? String == "undefined")
        #expect(try await webView.evaluateJavaScript("typeof window.__pwned") as? String == "undefined")
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

    private static let overlayFixture = """
    <html><head></head><body style="margin:0">
    <main><a href="/direct/t/98765/">chat</a><a href="/bob/" aria-label="Open the profile page of bob">bob</a></main>
    <div id="feed-overlay" style="position:fixed;top:0;left:0;width:100%;height:100%;z-index:5">
      <div id="reel-scroller" style="height:100%;overflow-y:auto">
        <div style="height:800px"><video style="width:80%;height:100%"></video><a href="/bob/reels/" aria-label="bob reels">r</a></div>
        <div style="height:800px"><video style="width:80%;height:100%"></video><a href="/dave/reels/" aria-label="dave reels">r</a></div>
        <div style="height:800px"><video style="width:80%;height:100%"></video></div>
      </div>
      <button aria-label="Close">x</button>
      <div role="button" aria-label="React to message from carol">y</div>
      <div role="button" aria-label="View Summer 2024 highlight">y</div>
    </div>
    </body></html>
    """

    @Test func reconMasksNamesInLabelsAndDescribesOverlays() async throws {
        let harness = Harness()
        let webView = makeWebView(harness)
        await harness.load(Self.overlayFixture, in: webView)

        let redactor = PathRedactor(salt: "s2")
        let raw = try await focusResult("return __focusRecon.snapshot(salt);", arguments: ["salt": redactor.salt], in: webView)
        let snapshot = try #require(raw as? [String: Any])
        let json = String(decoding: try JSONSerialization.data(withJSONObject: snapshot), as: UTF8.self)

        // Names from hrefs ("bob", "dave") and from label patterns ("carol", highlight title) are gone.
        for leaked in ["bob", "dave", "carol", "Summer"] { #expect(!json.contains(leaked), "leaked \(leaked)") }
        let labels = try #require(snapshot["labels"] as? [String])
        #expect(labels.contains("button:Close"))
        #expect(labels.contains("div:React to message from @\(redactor.token(for: "carol"))"))
        #expect(labels.contains("div:View #highlight highlight"))
        let links = try #require(snapshot["links"] as? [[String: Any]])
        #expect(links.contains { $0["label"] as? String == "Open the profile page of @\(redactor.token(for: "bob"))" })
        #expect(links.contains { $0["label"] as? String == "@\(redactor.token(for: "dave")) reels" })

        let overlays = try #require(snapshot["overlays"] as? [[String: Any]])
        #expect(overlays.count == 1)
        #expect(overlays.first?["video"] as? Bool == true)

        let scrollers = try #require(snapshot["scrollers"] as? [[String: Any]])
        let scroller = try #require(scrollers.first { $0["video"] as? Bool == true })
        #expect(scroller["children"] as? Int == 3)
        #expect(scroller["videoChildren"] as? Int == 3)
        #expect(scroller["scrollTop"] as? Int == 0)
        let ancestors = try #require(scroller["ancestors"] as? [String])
        #expect(ancestors.first == "div@fixed")

        let videos = try #require(snapshot["videos"] as? [String: Any])
        #expect(videos["count"] as? Int == 3)
        #expect(videos["inView"] as? Int == 0)

        // A swipe changes what is in view and the scroll position.
        _ = try await focusResult("document.getElementById('reel-scroller').scrollTop = 800; return 0;", in: webView)
        let after = try #require(try await focusResult("return __focusRecon.snapshot(salt);", arguments: ["salt": redactor.salt], in: webView) as? [String: Any])
        let afterVideos = try #require(after["videos"] as? [String: Any])
        #expect(afterVideos["inView"] as? Int == 1)
        let afterScroller = try #require((after["scrollers"] as? [[String: Any]])?.first { $0["video"] as? Bool == true })
        #expect(afterScroller["scrollTop"] as? Int == 800)
    }

    @Test func reconStillListsAFeedTheEngineLocked() async throws {
        let harness = Harness()
        let webView = makeWebView(harness)
        await harness.load(Self.feedFixture, in: webView)
        for _ in 0..<40 {
            if try await webView.evaluateJavaScript("document.getElementById('feed').hasAttribute('data-focus-lock')") as? Bool == true { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        let snapshot = try #require(try await focusResult("return __focusRecon.snapshot('s');", in: webView) as? [String: Any])
        let scrollers = try #require(snapshot["scrollers"] as? [[String: Any]])
        let feed = try #require(scrollers.first { $0["locked"] as? Bool == true })
        #expect(feed["video"] as? Bool == true)
        #expect(scrollers.contains { $0["locked"] == nil })  // the chat, still a plain scroller
    }
    #endif
}
