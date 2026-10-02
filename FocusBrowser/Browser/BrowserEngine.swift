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

    /// Last `location.pathname` reported by the route hook.
    private(set) var currentPath: String?
    /// Last route change reported by the route hook, with how the page got there.
    private(set) var lastRouteEvent: RouteEvent?
    /// Whether a non-empty `sessionid` cookie exists (read natively; HttpOnly, invisible to JS).
    private(set) var isLoggedIn = false

    /// Rules the engine reported unhealthy (matched nothing where expected, or invalid). Newest last.
    private(set) var healthFailures: [HealthFailure] = []
    /// Called on every health failure; the app uses it to force a config refresh.
    @ObservationIgnored var onHealthFailure: (@MainActor () -> Void)?

    private var lastAllowedURL = BrowserConfiguration.startURL
    private let openExternally: @MainActor (URL) -> Void
    @ObservationIgnored private var policy: RoutePolicy
    @ObservationIgnored private var navigationState = NavigationState()
    #if DEBUG
    @ObservationIgnored private let recon = Recon()
    #endif

    /// `openExternally` shows a non-Instagram link; by default in `SFSafariViewController`.
    init(
        loadOnInit: Bool = true,
        openExternally: @escaping @MainActor (URL) -> Void = SafariPresenter.present,
        filterConfig: FilterConfig = .bundledDefault()
    ) {
        self.openExternally = openExternally
        self.policy = filterConfig.policy
        let handler = WeakScriptMessageHandler()
        let configuration = BrowserConfiguration.makeWebViewConfiguration(routeHandler: handler, filterConfig: filterConfig)
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

    /// Hot-applies a validated config: new route policy, scripts for future page loads, and the
    /// current page re-configured without a reload. The config reaches the page only as data
    /// (re-encoded from `FilterConfig`), never as source text.
    func apply(_ config: FilterConfig) async {
        policy = config.policy
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        BrowserConfiguration.installUserScripts(on: controller, filterConfig: config)

        guard
            let json = try? config.pageJSON(),
            let object = try? JSONSerialization.jsonObject(with: Data(json.utf8))
        else { return }
        _ = try? await webView.callAsyncJavaScript(
            "__focus.apply(cfg)",
            arguments: ["cfg": object],
            in: nil,
            contentWorld: BrowserConfiguration.focusWorld
        )
    }

    private func refreshAuthState() async {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let loggedIn = cookies.contains {
            $0.name == "sessionid" && $0.domain.hasSuffix("instagram.com") && !$0.value.isEmpty
        }
        #if DEBUG
        if loggedIn != isLoggedIn { print("[FocusBrowser] isLoggedIn: \(isLoggedIn) -> \(loggedIn)") }
        #endif
        let becameLoggedIn = loggedIn && !isLoggedIn
        isLoggedIn = loggedIn
        pushLoggedInToPage()
        // Logging in lands on `/`, often before the cookie change is seen: judge the current route again.
        if becameLoggedIn, let path = currentPath { handleRoute(RouteEvent(path: path, kind: .replace)) }
    }

    /// The session cookie is HttpOnly, so the page engine (click guard) is told natively.
    private func pushLoggedInToPage() {
        Task {
            _ = try? await webView.callAsyncJavaScript(
                "__focus.setLoggedIn(value)",
                arguments: ["value": isLoggedIn],
                in: nil,
                contentWorld: BrowserConfiguration.focusWorld
            )
        }
    }

    // MARK: Route policy

    private func handleRoute(_ event: RouteEvent) {
        lastRouteEvent = event
        currentPath = event.path
        let decision = policy.decide(event, isLoggedIn: isLoggedIn, state: &navigationState)
        #if DEBUG
        print("[FocusBrowser] route: \(event.kind.rawValue) \(recon.redactor.redact(event.path)) -> \(describe(decision)) (isLoggedIn: \(isLoggedIn))")
        if policy.kind(of: event.path) == .unknown { print("[FocusBrowser] unknown route \(recon.redactor.redact(event.path))") }
        #endif
        switch decision {
        case .allow:
            publishRouteClass(policy.kind(of: event.path))
        case .redirect(let path):
            redirect(to: path)
        case .goBack:
            if webView.canGoBack { webView.goBack() } else { redirect(to: policy.redirectTo) }
        }
    }

    private func redirect(to path: String) {
        Task {
            _ = try? await webView.callAsyncJavaScript(
                "location.replace(path)",
                arguments: ["path": path],
                in: nil,
                contentWorld: BrowserConfiguration.focusWorld
            )
        }
    }

    /// Sets `data-focus-route` on `<html>` (not React-owned) so route-scoped CSS rules can apply.
    private func publishRouteClass(_ kind: RouteKind) {
        Task {
            _ = try? await webView.callAsyncJavaScript(
                "__focus.setRoute(name)",
                arguments: ["name": kind.name],
                in: nil,
                contentWorld: BrowserConfiguration.focusWorld
            )
        }
    }

    /// Full-page navigations go through the same policy (kind `initial`), after navigation hygiene.
    /// Returns the URL to load instead, if the policy redirects.
    private enum PageNavigation { case proceed, cancel, redirect(URL) }

    private func judgePageNavigation(to url: URL) -> PageNavigation {
        guard let host = url.host, NavigationHygiene.isInstagramHost(host.lowercased()) else { return .proceed }
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
        guard !path.isEmpty else { return .proceed }
        let decision = policy.decide(RouteEvent(path: path, kind: .initial), isLoggedIn: isLoggedIn, state: &navigationState)
        #if DEBUG
        print("[FocusBrowser] page: \(recon.redactor.redact(path)) -> \(describe(decision))")
        #endif
        switch decision {
        case .allow: return .proceed
        case .goBack: return .cancel
        case .redirect(let target):
            var components = URLComponents()
            components.scheme = url.scheme
            components.host = url.host
            guard let redirected = URL(string: target, relativeTo: components.url)?.absoluteURL else { return .cancel }
            return .redirect(redirected)
        }
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
                switch judgePageNavigation(to: url) {
                case .proceed: lastAllowedURL = url
                case .cancel: return false
                case .redirect(let target):
                    webView.load(URLRequest(url: target))
                    return false
                }
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

    private func describe(_ decision: RouteDecision) -> String {
        switch decision {
        case .allow: "allow"
        case .goBack: "goBack"
        case .redirect(let path): "redirect(\(recon.redactor.redact(path)))"
        }
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

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        pushLoggedInToPage()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pushLoggedInToPage()
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
        switch message.name {
        case RouteMessage.handlerName:
            guard let event = RouteMessage.event(from: message.body) else { return }
            #if DEBUG
            recon.scheduleSnapshot(for: event, in: webView)
            #endif
            handleRoute(event)
        case FocusHealthMessage.handlerName:
            guard let failure = FocusHealthMessage.failure(from: message.body) else { return }
            healthFailures.append(failure)
            if healthFailures.count > 20 { healthFailures.removeFirst(healthFailures.count - 20) }
            #if DEBUG
            print("[FocusBrowser] health: rule \(failure.ruleId) \(failure.reason) on \(recon.redactor.redact(failure.path))")
            #endif
            onHealthFailure?()
        default:
            return
        }
    }
}

extension BrowserEngine: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { await refreshAuthState() }
    }
}
