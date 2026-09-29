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
    /// Whether a non-empty `sessionid` cookie exists (read natively; HttpOnly, invisible to JS).
    private(set) var isLoggedIn = false
    /// Set to present an external link in `SFSafariViewController`.
    var safariRequest: SafariRequest?

    private var lastAllowedURL = BrowserConfiguration.startURL

    init(loadOnInit: Bool = true) {
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
        isLoggedIn = cookies.contains {
            $0.name == "sessionid" && $0.domain.hasSuffix("instagram.com") && !$0.value.isEmpty
        }
    }

    /// Applies navigation hygiene; returns whether the navigation may proceed in the web view.
    private func admit(_ url: URL?, isMainFrame: Bool) -> Bool {
        switch NavigationHygiene.verdict(for: url, isMainFrame: isMainFrame) {
        case .allow:
            if isMainFrame, let url, url.scheme == "http" || url.scheme == "https" {
                lastAllowedURL = url
            }
            return true
        case .cancel:
            return false
        case .openInSafari(let external):
            safariRequest = SafariRequest(url: external)
            return false
        }
    }
}

extension BrowserEngine: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        // A nil target frame means a new-window request (target=_blank): treat it as main frame.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        return admit(navigationAction.request.url, isMainFrame: isMainFrame) ? .allow : .cancel
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
        if admit(navigationAction.request.url, isMainFrame: true) {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

extension BrowserEngine: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == RouteMessage.handlerName, let path = RouteMessage.path(from: message.body) else { return }
        currentPath = path
    }
}

extension BrowserEngine: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { await refreshAuthState() }
    }
}
