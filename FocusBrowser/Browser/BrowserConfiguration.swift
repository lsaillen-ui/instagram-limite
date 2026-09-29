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

    static func makeWebViewConfiguration(routeHandler: WKScriptMessageHandler) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = applicationName(
            osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let controller = configuration.userContentController
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
        controller.add(routeHandler, contentWorld: .page, name: RouteMessage.handlerName)
        return configuration
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
