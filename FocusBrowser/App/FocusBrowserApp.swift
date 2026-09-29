import SwiftUI

@main
struct FocusBrowserApp: App {
    @State private var engine: BrowserEngine

    init() {
        // Created at launch so the WebContent process start is paid here, not on first render.
        _engine = State(initialValue: BrowserEngine())
    }

    var body: some Scene {
        WindowGroup {
            RootView(engine: engine)
        }
    }
}
