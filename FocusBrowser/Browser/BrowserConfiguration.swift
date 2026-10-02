import WebKit

@MainActor
enum BrowserConfiguration {
    static let startURL = URL(string: "https://www.instagram.com/direct/inbox/")!
    static let focusWorld = WKContentWorld.world(name: "focus")

    /// Appended to the default user agent. The `Safari/` token matters: without it
    /// the site may serve a degraded page or "open the app" banners.
    static func applicationName(osMajorVersion: Int) -> String {
        "Version/\(osMajorVersion).0 Mobile/15E148 Safari/604.1"
    }

    /// `routeHandler` receives the page-world `route` messages and the focus-world `focusHealth` messages.
    static func makeWebViewConfiguration(
        routeHandler: WKScriptMessageHandler,
        filterConfig: FilterConfig = .bundledDefault()
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = applicationName(
            osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let controller = configuration.userContentController
        installUserScripts(on: controller, filterConfig: filterConfig)
        controller.add(routeHandler, contentWorld: .page, name: RouteMessage.handlerName)
        controller.add(routeHandler, contentWorld: focusWorld, name: FocusHealthMessage.handlerName)
        return configuration
    }

    /// Installs every user script. Also used to swap in a new filter config: call
    /// `removeAllUserScripts()` first, then this (message handlers are untouched).
    static func installUserScripts(on controller: WKUserContentController, filterConfig: FilterConfig) {
        controller.addUserScript(WKUserScript(
            source: scriptSource(named: "base"),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: focusWorld
        ))
        controller.addUserScript(WKUserScript(
            source: scriptSource(named: "route-hook"),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        ))
        #if DEBUG
        controller.addUserScript(WKUserScript(
            source: scriptSource(named: "recon"),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: focusWorld
        ))
        #endif
        // Engine source + one `__focus.apply(<json>)` call; the json is re-encoded from the
        // validated config, never raw file bytes.
        guard let engineSource = try? InjectionScripts.focusEngine(config: filterConfig) else {
            preconditionFailure("The filter config could not be encoded")
        }
        controller.addUserScript(WKUserScript(
            source: engineSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: focusWorld
        ))
    }

    /// Bundled scripts are part of the app: a missing one is a build error, not a runtime condition.
    static func scriptSource(named name: String) -> String {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { preconditionFailure("Missing bundled script \(name).js") }
        return source
    }
}
