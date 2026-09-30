import Foundation

/// A rule the engine found unhealthy: it matched nothing where it must (`nomatch`), or its
/// selector is invalid (`invalid`).
struct HealthFailure: Equatable, Sendable {
    let ruleId: String
    let path: String
    let reason: String
}

/// Validation of what the focus-world engine posts on `focusHealth`. The site cannot reach the
/// focus world, but the payload is still validated like any message crossing into native code.
enum FocusHealthMessage {
    static let handlerName = "focusHealth"
    private static let reasons: Set<String> = ["nomatch", "invalid"]

    static func failure(from body: Any) -> HealthFailure? {
        guard
            let dictionary = body as? [String: Any],
            let ruleId = dictionary["ruleId"] as? String,
            ruleId.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil,
            let path = dictionary["path"] as? String,
            path.hasPrefix("/"), !path.hasPrefix("//"), path.utf8.count <= 2048
        else { return nil }
        let reason = (dictionary["reason"] as? String) ?? "nomatch"
        guard reasons.contains(reason) else { return nil }
        return HealthFailure(ruleId: ruleId, path: path, reason: reason)
    }
}
