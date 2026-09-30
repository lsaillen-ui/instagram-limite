import Observation
import WebKit

/// `WKUserContentController` retains its handlers strongly; this breaks the cycle.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Owns the single `WKWebView` of the app. Created once at launch by the `App`.
@MainActor
@Observable
final class BrowserEngine: NSObject {
    let webView: WKWebView

    /// Last `location.pathname` reported by the route hook. Step 2 feeds it to the route policy.
    private(set) var currentPath: String?
    /// Last route change reported by the route hook, with how the page got there.
    private(set) var lastRouteEvent: RouteEvent?
    /// Whether a non-empty `sessionid` cookie exists (read natively; HttpOnly, invisible to JS).
    private(set) var isLoggedIn = false

    private var lastAllowedURL = BrowserConfiguration.startURL
    private let openExternally: @MainActor (URL) -> Void
    #if DEBUG
    @ObservationIgnored private let recon = Recon()
    #endif

    /// `openExternally` shows a non-Instagram link; by default in `SFSafariViewController`.
    init(loadOnInit: Bool = true, openExternally: @escaping @MainActor (URL) -> Void = SafariPresenter.present) {
        self.openExternally = openExternally
        let handler = WeakScriptMessageHandler()
        let configuration = BrowserConfiguration.makeWebViewConfiguration(routeHandler: handler)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        handler.target = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        webView.isInspectable = true
        #endif

        configuration.websiteDataStore.httpCookieStore.add(self)
        Task { await refreshAuthState() }

        if loadOnInit {
            webView.load(URLRequest(url: BrowserConfiguration.startURL))
        }
    }

    private func refreshAuthState() async {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let loggedIn = cookies.contains {
            $0.name == "sessionid" && $0.domain.hasSuffix("instagram.com") && !$0.value.isEmpty
        }
        #if DEBUG
        if loggedIn != isLoggedIn { print("[FocusBrowser] isLoggedIn: \(isLoggedIn) -> \(loggedIn)") }
        #endif
        isLoggedIn = loggedIn
    }

    /// Applies navigation hygiene; returns whether the navigation may proceed in the web view.
    private func admit(_ url: URL?, isMainFrame: Bool, source: String) -> Bool {
        let verdict = NavigationHygiene.verdict(for: url, isMainFrame: isMainFrame)
        #if DEBUG
        print("[FocusBrowser] \(source) main=\(isMainFrame) \(recon.loggable(url)) -> \(loggable(verdict))")
        #endif
        switch verdict {
        case .allow:
            if isMainFrame, let url, url.scheme == "http" || url.scheme == "https" {
                lastAllowedURL = url
            }
            return true
        case .cancel:
            return false
        case .openInSafari(let external):
            openExternally(external)
            return false
        }
    }

    #if DEBUG
    /// Marks the current state in the recon log and snapshots the page immediately.
    func mark() {
        recon.mark(currentPath: currentPath, in: webView)
    }

    private func loggable(_ verdict: NavigationVerdict) -> String {
        switch verdict {
        case .allow: "allow"
        case .cancel: "cancel"
        case .openInSafari(let url): "openInSafari(\(recon.loggable(url)))"
        }
    }
    #endif
}

extension BrowserEngine: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        // A nil target frame means a new-window request (target=_blank): treat it as main frame.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        return admit(navigationAction.request.url, isMainFrame: isMainFrame, source: "decidePolicyFor") ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await refreshAuthState() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.load(URLRequest(url: lastAllowedURL))
    }
}

extension BrowserEngine: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Never open a second web view: same-site links load in ours, external ones go to Safari.
        if admit(navigationAction.request.url, isMainFrame: true, source: "createWebViewWith") {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

extension BrowserEngine: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == RouteMessage.handlerName, let event = RouteMessage.event(from: message.body) else { return }
        #if DEBUG
        print("[FocusBrowser] route: \(event.kind.rawValue) \(recon.redactor.redact(event.path)) (isLoggedIn: \(isLoggedIn))")
        recon.scheduleSnapshot(for: event, in: webView)
        #endif
        lastRouteEvent = event
        currentPath = event.path
    }
}

extension BrowserEngine: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { await refreshAuthState() }
    }
}
