import Foundation

/// How the page reached a route, as reported by the route hook.
enum RouteEventKind: String, Sendable {
    case push, replace, pop, initial
}

/// A validated route change reported by the page.
struct RouteEvent: Equatable, Sendable {
    let path: String
    let kind: RouteEventKind
}

/// Validation of what the page-world route hook posts. The `.page` world is
/// reachable by the site's own scripts, so the payload is untrusted.
enum RouteMessage {
    static let handlerName = "route"
    private static let maxLength = 2048

    /// Returns the event if `body` is `{ path, kind }` with a plausible `location.pathname`
    /// and a known kind.
    static func event(from body: Any) -> RouteEvent? {
        guard
            let dictionary = body as? [String: Any],
            let path = dictionary["path"] as? String,
            let rawKind = dictionary["kind"] as? String,
            let kind = RouteEventKind(rawValue: rawKind),
            isPlausible(path)
        else { return nil }
        return RouteEvent(path: path, kind: kind)
    }

    private static func isPlausible(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.hasPrefix("//") && path.utf8.count <= maxLength
    }
}
