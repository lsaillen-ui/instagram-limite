#if DEBUG
import Foundation
import WebKit

/// DEBUG-only reconnaissance for Step 2: redacted route logging and DOM snapshots printed to the
/// Xcode console (`[FocusRecon] …`). Never compiled into Release.
@MainActor
final class Recon {
    static let snapshotDelay: Duration = .milliseconds(1500)

    let redactor = PathRedactor()
    private var markCount = 0

    /// scheme://host/path with the path redacted; query strings and fragments can carry tokens.
    func loggable(_ url: URL?) -> String {
        guard let url else { return "nil" }
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        return "\(url.scheme ?? "?")://\(url.host ?? "")\(redactor.redact(path))"
    }

    /// One snapshot line, 1.5 s after a route event (the page needs time to render its new state).
    func scheduleSnapshot(for event: RouteEvent, in webView: WKWebView) {
        Task { [weak webView] in
            try? await Task.sleep(for: Self.snapshotDelay)
            guard let webView else { return }
            await printSnapshot(label: event.kind.rawValue, path: event.path, in: webView)
        }
    }

    /// Prints a MARK separator and snapshots immediately.
    func mark(currentPath: String?, in webView: WKWebView) {
        markCount += 1
        print("[FocusRecon] ---- MARK \(markCount) ----")
        Task { [weak webView] in
            guard let webView else { return }
            await printSnapshot(label: "mark", path: currentPath ?? webView.url?.path ?? "/", in: webView)
        }
    }

    private func printSnapshot(label: String, path: String, in webView: WKWebView) async {
        let json = await snapshot(in: webView)
        print("[FocusRecon] \(label) \(redactor.redact(path)) \(json)")
    }

    private func snapshot(in webView: WKWebView) async -> String {
        do {
            let result = try await webView.callAsyncJavaScript(
                "return __focusRecon.snapshot(salt);",
                arguments: ["salt": redactor.salt],
                in: nil,
                contentWorld: BrowserConfiguration.focusWorld
            )
            guard
                let result,
                JSONSerialization.isValidJSONObject(result),
                let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes])
            else { return #"{"error":"snapshot returned no JSON"}"# }
            return String(decoding: data, as: UTF8.self)
        } catch {
            return #"{"error":"snapshot failed"}"#
        }
    }
}
#endif
