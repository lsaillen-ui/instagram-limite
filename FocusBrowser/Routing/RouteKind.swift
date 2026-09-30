/// What a path is, as far as the route policy is concerned.
enum RouteKind: Equatable, Sendable {
    // Hubs: places the user reaches on purpose, and from which content may be opened.
    case inbox, thread, profile, post
    // Content: reachable only from a hub, never from another content item.
    case reel(id: String)
    case story(owner: String, id: String?)
    // Infinite surfaces.
    case homeFeed, reelsFeed, explore
    case auth
    case unknown

    /// Stable name, used in the config (`blocked`, `routeScope`) and as `data-focus-route`.
    var name: String {
        switch self {
        case .inbox: "inbox"
        case .thread: "thread"
        case .profile: "profile"
        case .post: "post"
        case .reel: "reel"
        case .story: "story"
        case .homeFeed: "homeFeed"
        case .reelsFeed: "reelsFeed"
        case .explore: "explore"
        case .auth: "auth"
        case .unknown: "unknown"
        }
    }

    static let allNames: Set<String> = [
        "inbox", "thread", "profile", "post", "reel", "story",
        "homeFeed", "reelsFeed", "explore", "auth", "unknown",
    ]

    var isHub: Bool {
        switch self {
        case .inbox, .thread, .profile, .post: true
        default: false
        }
    }

    var isContent: Bool {
        switch self {
        case .reel, .story: true
        default: false
        }
    }

    /// Two content values are the same item when they share the reel id or the story owner
    /// (the next story of the same person is not a new item).
    func isSameContent(as other: RouteKind) -> Bool {
        switch (self, other) {
        case (.reel(let a), .reel(let b)): a == b
        case (.story(let a, _), .story(let b, _)): a == b
        default: false
        }
    }
}
