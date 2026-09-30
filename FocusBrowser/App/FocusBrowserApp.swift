import SwiftUI

@main
struct FocusBrowserApp: App {
    /// Created when the first scene appears, not in `init`: a `WKWebView` built before UIKit has a
    /// window makes every touch on it crash in `UIGestureRecognizer _delayTouchesForEvent:inPhase:`.
    @State private var engine: BrowserEngine?

    var body: some Scene {
        WindowGroup {
            if let engine {
                RootView(engine: engine)
            } else {
                Color(.systemBackground).onAppear { engine = BrowserEngine() }
            }
        }
    }
}
