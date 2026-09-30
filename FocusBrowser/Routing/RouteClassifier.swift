import Foundation

/// Path → `RouteKind`. Pure, no WebKit. Patterns come from the filter config; a kind the config
/// does not define (or defines with patterns that do not compile) uses `defaultPatterns`.
///
/// Capture groups: `reel` group 1 = id; `story` group 1 = owner, group 2 (optional) = item id.
/// `profile` has no pattern: a first segment that is not a reserved site word and looks like a username.
struct RouteClassifier: Sendable {
    /// The kinds a config may override.
    static let configurableKinds = ["homeFeed", "thread", "inbox", "reelsFeed", "reel", "story", "post", "explore", "auth"]

    /// Observed on the real site (docs/RECON_STEP2.md): reels of a profile live at
    /// `/{user}/reel/{id}/`, posts also at `/{user}/p/{id}/`, `/reels/audio/{id}/` is a reels feed.
    static let defaultPatterns: [String: [String]] = [
        "homeFeed": ["^/$"],
        "thread": ["^/direct/t/[^/]+"],
        "inbox": ["^/direct(/|$)"],
        "reelsFeed": ["^/reels(/audio(/.*)?)?/?$"],
        "reel": ["^/reels?/([^/]+)/?$", "^/[^/]+/reel/([^/]+)/?$"],
        "story": ["^/stories/(highlights)/([^/]+)/?$", "^/stories/([^/]+)(?:/([^/]+))?/?$"],
        "post": ["^/p/[^/]+", "^/[^/]+/p/[^/]+"],
        "explore": ["^/explore(/|$)"],
        "auth": ["^/(accounts|challenge)(/|$)"],
    ]

    /// Evaluation order matters: `reelsFeed` before `reel` (`/reels/audio/` would look like a reel id),
    /// `thread` before `inbox`.
    private static let order = ["homeFeed", "thread", "inbox", "reelsFeed", "reel", "story", "post", "explore", "auth"]

    private let compiled: [String: [NSRegularExpression]]

    init(patterns overrides: [String: [String]] = [:]) {
        var compiled: [String: [NSRegularExpression]] = [:]
        for kind in Self.order {
            let custom = overrides[kind] ?? []
            let customCompiled = custom.compactMap { try? NSRegularExpression(pattern: $0) }
            // A kind is overridden only when every one of its patterns compiles.
            let chosen = !custom.isEmpty && customCompiled.count == custom.count
                ? custom
                : (Self.defaultPatterns[kind] ?? [])
            compiled[kind] = chosen.compactMap { try? NSRegularExpression(pattern: $0) }
        }
        self.compiled = compiled
    }

    func classify(_ path: String) -> RouteKind {
        let range = NSRange(path.startIndex..., in: path)
        func firstMatch(_ kind: String) -> NSTextCheckingResult? {
            for regex in compiled[kind] ?? [] {
                if let match = regex.firstMatch(in: path, range: range) { return match }
            }
            return nil
        }
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            guard index < match.numberOfRanges, let r = Range(match.range(at: index), in: path), !r.isEmpty else { return nil }
            return String(path[r])
        }

        for kind in Self.order {
            guard let match = firstMatch(kind) else { continue }
            switch kind {
            case "homeFeed": return .homeFeed
            case "thread": return .thread
            case "inbox": return .inbox
            case "reelsFeed": return .reelsFeed
            case "reel": return group(match, 1).map { .reel(id: $0) } ?? .unknown
            case "story": return group(match, 1).map { .story(owner: $0, id: group(match, 2)) } ?? .unknown
            case "post": return .post
            case "explore": return .explore
            default: return .auth
            }
        }
        return isProfile(path) ? .profile : .unknown
    }

    private func isProfile(_ path: String) -> Bool {
        guard let first = path.split(separator: "/", omittingEmptySubsequences: true).first else { return false }
        let segment = String(first)
        return !ReservedSegments.firstSegments.contains(segment.lowercased())
            && segment.range(of: "^[A-Za-z0-9._]{1,30}$", options: .regularExpression) != nil
    }
}
