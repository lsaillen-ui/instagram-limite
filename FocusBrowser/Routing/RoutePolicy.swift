import Foundation

enum RouteDecision: Equatable, Sendable {
    case allow
    case redirect(String)
    case goBack
}

/// What the policy remembers between route events.
struct NavigationState: Sendable {
    /// Last allowed route that mattered (hubs, content, auth). `unknown` routes are transparent.
    var current: RouteKind?
    /// The content item currently open, if any.
    var content: RouteKind?
    /// The previous route was blocked: content right after it has no hub to come from.
    var afterBlocked = false
    fileprivate var forcedAt: [Date] = []
    fileprivate var suppressForcedUntil: Date?
    private(set) var loopGuardTrips = 0

    fileprivate mutating func trip() { loopGuardTrips += 1 }
}

/// The route policy (CLAUDE.md, "Route guard"). Pure: it never touches WebKit.
///
/// One hop: content (a reel, a story) is reachable only from a hub (inbox, conversation, profile,
/// post), never from another content item.
struct RoutePolicy: Sendable {
    static let loopLimit = 3
    static let loopWindow: TimeInterval = 2

    let classifier: RouteClassifier
    let redirectTo: String
    /// Kind names (`homeFeed`, `reelsFeed`, `explore`) redirected to `redirectTo`.
    let blocked: Set<String>

    init(classifier: RouteClassifier = RouteClassifier(), redirectTo: String = "/direct/inbox/",
         blocked: Set<String> = ["homeFeed", "reelsFeed", "explore"]) {
        self.classifier = classifier
        self.redirectTo = redirectTo
        self.blocked = blocked
    }

    /// The route class `data-focus-route` should carry after an allowed decision.
    func kind(of path: String) -> RouteKind { classifier.classify(path) }

    func decide(_ event: RouteEvent, isLoggedIn: Bool, state: inout NavigationState, now: Date = Date()) -> RouteDecision {
        let kind = classifier.classify(event.path)

        // Logged out: the login flow (`/`, `/accounts/*`, `/challenge/*`) is never redirected.
        guard isLoggedIn else {
            state.current = kind
            state.content = nil
            state.afterBlocked = false
            return .allow
        }

        if blocked.contains(kind.name) {
            state.afterBlocked = true
            return force(.redirect(redirectTo), state: &state, now: now)
        }
        if kind.isContent {
            return decideContent(kind, event: event, state: &state, now: now)
        }
        if kind == .unknown { return .allow }

        // Hub → hub is fine (manual taps); only automatic chaining is blocked. `pop` is always allowed.
        state.current = kind
        state.content = nil
        state.afterBlocked = false
        return .allow
    }

    private func decideContent(_ kind: RouteKind, event: RouteEvent, state: inout NavigationState, now: Date) -> RouteDecision {
        if event.kind == .pop {
            // Never answer a `pop` with `goBack` (it would loop).
            if let open = state.content, open.isSameContent(as: kind) {
                remember(kind, in: &state)
                return .allow
            }
            state.afterBlocked = true
            return force(.redirect(redirectTo), state: &state, now: now)
        }

        if let open = state.content {
            if open.isSameContent(as: kind) {  // replace noise, next story of the same person
                remember(kind, in: &state)
                return .allow
            }
            return force(.goBack, state: &state, now: now)  // content → other content
        }

        guard let origin = state.current, origin.isHub, !state.afterBlocked else {
            // First route of the session, or right after a blocked route: no hub to come from.
            state.afterBlocked = true
            return force(.redirect(redirectTo), state: &state, now: now)
        }
        remember(kind, in: &state)
        return .allow
    }

    private func remember(_ kind: RouteKind, in state: inout NavigationState) {
        state.current = kind
        state.content = kind
        state.afterBlocked = false
    }

    /// Loop guard: more than `loopLimit` forced navigations within `loopWindow` seconds means the
    /// site and the policy are fighting. Stop forcing for a while and land on the inbox once.
    private func force(_ decision: RouteDecision, state: inout NavigationState, now: Date) -> RouteDecision {
        if let until = state.suppressForcedUntil, now < until { return .allow }
        state.forcedAt = state.forcedAt.filter { now.timeIntervalSince($0) <= Self.loopWindow }
        state.forcedAt.append(now)
        guard state.forcedAt.count > Self.loopLimit else { return decision }

        state.forcedAt = []
        state.suppressForcedUntil = now.addingTimeInterval(Self.loopWindow)
        state.content = nil
        state.trip()
        return .redirect(redirectTo)
    }
}
