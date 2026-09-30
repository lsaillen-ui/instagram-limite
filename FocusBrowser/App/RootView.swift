import SwiftUI

/// Placeholder shell: just the web view.
struct RootView: View {
    let engine: BrowserEngine

    var body: some View {
        WebViewContainer(webView: engine.webView)
            .background(Color(.systemBackground))
        #if DEBUG
            .overlay { ReconMarkButton(action: engine.mark) }
        #endif
    }
}

#if DEBUG
/// Step 2 recon: a draggable button that marks the log and snapshots the page.
private struct ReconMarkButton: View {
    let action: () -> Void
    @State private var offset = CGSize(width: 130, height: 60)
    @GestureState private var drag = CGSize.zero

    var body: some View {
        Button(action: action) {
            Text("Mark")
                .font(.footnote.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.orange, in: Capsule())
                .foregroundStyle(.white)
        }
        .opacity(0.85)
        .offset(x: offset.width + drag.width, y: offset.height + drag.height)
        .gesture(
            DragGesture()
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    offset.width += value.translation.width
                    offset.height += value.translation.height
                }
        )
    }
}
#endif
