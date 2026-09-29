import Foundation

/// Validation of what the page-world route hook posts. The `.page` world is
/// reachable by the site's own scripts, so the payload is untrusted.
enum RouteMessage {
    static let handlerName = "route"
    private static let maxLength = 2048

    /// Returns the path if `body` is a plausible `location.pathname`.
    static func path(from body: Any) -> String? {
        guard
            let path = body as? String,
            path.hasPrefix("/"),
            !path.hasPrefix("//"),
            path.utf8.count <= maxLength
        else { return nil }
        return path
    }
}
