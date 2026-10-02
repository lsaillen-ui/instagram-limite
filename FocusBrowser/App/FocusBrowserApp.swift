import SwiftUI

@main
struct FocusBrowserApp: App {
    /// Created when the first scene appears, not in `init`: a `WKWebView` built before UIKit has a
    /// window makes every touch on it crash in `UIGestureRecognizer _delayTouchesForEvent:inPhase:`.
    @State private var engine: BrowserEngine?
    @State private var updater: RemoteConfigUpdater?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if let engine {
                RootView(engine: engine)
            } else {
                Color(.systemBackground).onAppear(perform: start)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { updater?.refreshIfStale() }
        }
    }

    /// Starts with the cached config (else the bundled one) and loads the page at once; the
    /// network fetch happens afterwards, in the background.
    private func start() {
        let store = ConfigStore.standard()
        let startup = store.startupConfig(bundled: .bundledDefault())
        let engine = BrowserEngine(filterConfig: startup.config)
        let updater = RemoteConfigUpdater(
            store: store,
            fetcher: URLSessionConfigFetcher(baseURL: RemoteConfigEndpoint.baseURL),
            current: startup,
            apply: { [weak engine] config in await engine?.apply(config) }
        )
        engine.onHealthFailure = { [weak updater] in updater?.refreshAfterHealthFailure() }
        self.engine = engine
        self.updater = updater
        updater.refreshAtLaunch()
    }
}
