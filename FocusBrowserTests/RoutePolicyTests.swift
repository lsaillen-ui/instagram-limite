import Foundation
import Testing
@testable import FocusBrowser

struct RoutePolicyTests {
    /// A logged-in browsing session; `go` advances the clock (default: outside the loop-guard window).
    private struct Session {
        let policy = RoutePolicy()
        var state = NavigationState()
        var now = Date(timeIntervalSince1970: 1_000)
        var loggedIn = true

        @discardableResult
        mutating func go(_ kind: RouteEventKind, _ path: String, after seconds: TimeInterval = 5) -> RouteDecision {
            now.addTimeInterval(seconds)
            return policy.decide(RouteEvent(path: path, kind: kind), isLoggedIn: loggedIn, state: &state, now: now)
        }

        /// A session that starts on the inbox, like the app does.
        static func atInbox() -> Session {
            var session = Session()
            session.go(.initial, "/direct/inbox/")
            return session
        }
    }

    private let inbox = RouteDecision.redirect("/direct/inbox/")

    // MARK: logged out

    @Test func loggedOutAllowsEveryRoute() {
        var session = Session()
        session.loggedIn = false
        for path in ["/", "/accounts/login/", "/challenge/x/", "/explore/", "/reels/", "/reel/abc/", "/direct/inbox/"] {
            #expect(session.go(.push, path) == .allow, "path: \(path)")
        }
    }

    @Test func homeAfterLoginIsRedirected() {
        var session = Session()
        session.loggedIn = false
        #expect(session.go(.initial, "/accounts/login/") == .allow)
        #expect(session.go(.push, "/") == .allow)
        session.loggedIn = true
        #expect(session.go(.replace, "/") == inbox)
    }

    // MARK: blocked surfaces

    @Test(arguments: ["/", "/reels/", "/reels/audio/123/", "/explore/", "/explore/search/", "/explore/tags/cats/"])
    func blockedSurfacesRedirectToTheInbox(path: String) {
        var session = Session.atInbox()
        #expect(session.go(.push, path) == inbox)
    }

    @Test func blockedIsRedirectedWhateverTheKind() {
        var session = Session.atInbox()
        for kind in [RouteEventKind.push, .replace, .pop, .initial] {
            #expect(session.go(kind, "/explore/") == inbox)
        }
    }

    // MARK: hubs and content

    @Test func hubsAreAlwaysAllowed() {
        var session = Session.atInbox()
        for path in ["/direct/t/1/", "/direct/inbox/", "/bob/", "/p/abc/", "/bob/reels/", "/bob/p/abc/"] {
            #expect(session.go(.push, path) == .allow, "path: \(path)")
        }
    }

    @Test(arguments: [
        ("/direct/t/1/", "/reel/aaa/"),
        ("/bob/", "/bob/reel/aaa/"),
        ("/p/abc/", "/reels/aaa/"),
        ("/direct/t/1/", "/stories/bob/1/"),
        ("/bob/", "/stories/highlights/9/"),
    ])
    func contentFromAHubIsAllowed(hub: String, content: String) {
        var session = Session.atInbox()
        session.go(.push, hub)
        #expect(session.go(.push, content) == .allow)
    }

    @Test func contentToOtherContentGoesBack() {
        var session = Session.atInbox()
        session.go(.push, "/bob/")
        #expect(session.go(.push, "/bob/reel/aaa/") == .allow)
        #expect(session.go(.push, "/bob/reel/bbb/") == .goBack)      // push
        #expect(session.go(.replace, "/bob/reel/ccc/") == .goBack)   // replace
        #expect(session.go(.push, "/stories/bob/1/") == .goBack)     // reel → story
    }

    @Test func sameContentAgainIsAllowed() {
        var session = Session.atInbox()
        session.go(.push, "/bob/")
        session.go(.push, "/bob/reel/aaa/")
        #expect(session.go(.replace, "/bob/reel/aaa/") == .allow)
        #expect(session.go(.initial, "/bob/reel/aaa/") == .allow)
    }

    @Test func storiesAdvanceWithinAPersonButNotToTheNextPerson() {
        var session = Session.atInbox()
        session.go(.push, "/direct/t/1/")
        #expect(session.go(.push, "/stories/bob/") == .allow)         // as observed: push, then
        #expect(session.go(.replace, "/stories/bob/11/") == .allow)   // replace adds the item id
        #expect(session.go(.replace, "/stories/bob/12/") == .allow)   // next story of the same person
        #expect(session.go(.replace, "/stories/eve/21/") == .goBack)  // auto-advance to another person
    }

    // MARK: cold content

    @Test func contentOnTheFirstRouteOfTheSessionGoesToTheInbox() {
        var session = Session()
        #expect(session.go(.initial, "/bob/reel/aaa/") == inbox)
    }

    @Test func contentRightAfterABlockedRouteGoesToTheInbox() {
        var session = Session.atInbox()
        session.go(.push, "/bob/")
        #expect(session.go(.push, "/explore/") == inbox)
        #expect(session.go(.push, "/reel/aaa/") == inbox)
        // The redirect lands on the inbox, a hub again.
        #expect(session.go(.replace, "/direct/inbox/") == .allow)
        #expect(session.go(.push, "/reel/aaa/") == .allow)
    }

    @Test func contentFromASettingsPageIsNotFromAHub() {
        var session = Session.atInbox()
        session.go(.push, "/accounts/edit/")
        #expect(session.go(.push, "/reel/aaa/") == inbox)
    }

    // MARK: pop

    @Test func popToAHubIsAlwaysAllowedAndClosesTheContent() {
        var session = Session.atInbox()
        session.go(.push, "/bob/")
        session.go(.push, "/bob/reel/aaa/")
        #expect(session.go(.pop, "/bob/") == .allow)
        // The content is gone: popping to it again is no longer allowed.
        #expect(session.go(.pop, "/bob/reel/aaa/") == inbox)
    }

    @Test func popToTheRememberedContentIsAllowed() {
        var session = Session.atInbox()
        session.go(.push, "/bob/")
        session.go(.push, "/bob/reel/aaa/")
        #expect(session.go(.pop, "/bob/reel/aaa/") == .allow)
    }

    @Test func popToOtherContentRedirectsAndNeverGoesBack() {
        var session = Session.atInbox()
        session.go(.push, "/bob/")
        session.go(.push, "/bob/reel/aaa/")
        #expect(session.go(.pop, "/bob/reel/zzz/") == inbox)
        var cold = Session()
        #expect(cold.go(.pop, "/bob/reel/aaa/") == inbox)
    }

    @Test func goBackLandsOnTheRememberedContentWithoutLooping() {
        var session = Session.atInbox()
        session.go(.push, "/bob/")
        session.go(.push, "/bob/reel/aaa/")
        #expect(session.go(.push, "/bob/reel/bbb/") == .goBack)
        // The page goes back to reel A: a pop to the remembered content.
        #expect(session.go(.pop, "/bob/reel/aaa/") == .allow)
    }

    @Test func aStoryReplaceThenGoBackEndsOnTheHub() {
        var session = Session.atInbox()
        session.go(.push, "/bob/")
        session.go(.push, "/stories/bob/")
        #expect(session.go(.replace, "/stories/eve/2/") == .goBack)
        // `replace` swapped the story's history entry, so going back lands on the profile.
        #expect(session.go(.pop, "/bob/") == .allow)
    }

    // MARK: hub → hub, unknown, auth

    @Test func hubToHubChainsAreFine() {
        var session = Session.atInbox()
        session.go(.push, "/direct/t/1/")
        session.go(.push, "/bob/reel/aaa/")
        #expect(session.go(.push, "/p/abc/") == .allow)           // reel → post (manual tap)
        #expect(session.go(.push, "/eve/") == .allow)             // post → profile
        #expect(session.go(.push, "/eve/reel/bbb/") == .allow)    // and a new content from there
    }

    @Test func unknownRoutesAreAllowedAndTransparent() {
        var session = Session.atInbox()
        session.go(.push, "/direct/t/1/")
        session.go(.push, "/reel/aaa/")
        #expect(session.go(.push, "/about/") == .allow)
        // The open content is still remembered.
        #expect(session.go(.pop, "/reel/aaa/") == .allow)
        #expect(session.go(.push, "/reel/bbb/") == .goBack)
    }

    @Test func authRoutesAreAllowedWhileLoggedIn() {
        var session = Session.atInbox()
        #expect(session.go(.push, "/accounts/edit/") == .allow)
        #expect(session.go(.push, "/challenge/x/") == .allow)
    }

    // MARK: loop guard

    @Test func loopGuardStopsForcingAndLandsOnTheInboxOnce() {
        var session = Session.atInbox()
        session.go(.push, "/bob/")
        session.go(.push, "/bob/reel/aaa/")
        // Three forced navigations within two seconds are tolerated…
        #expect(session.go(.push, "/bob/reel/b1/", after: 0.1) == .goBack)
        #expect(session.go(.push, "/bob/reel/b2/", after: 0.1) == .goBack)
        #expect(session.go(.push, "/bob/reel/b3/", after: 0.1) == .goBack)
        #expect(session.state.loopGuardTrips == 0)
        // …the fourth trips the guard: one redirect to the inbox.
        #expect(session.go(.push, "/bob/reel/b4/", after: 0.1) == inbox)
        #expect(session.state.loopGuardTrips == 1)
        // While the guard is suppressing, nothing is forced.
        #expect(session.go(.push, "/bob/reel/b5/", after: 0.1) == .allow)
        #expect(session.go(.push, "/explore/", after: 0.1) == .allow)
        #expect(session.state.loopGuardTrips == 1)
    }

    @Test func forcedNavigationsSpreadOverTimeNeverTrip() {
        var session = Session.atInbox()
        for _ in 0..<10 {
            #expect(session.go(.push, "/explore/", after: 1) == inbox)  // one per second: outside the window
        }
        #expect(session.state.loopGuardTrips == 0)
    }

    @Test func forcingResumesAfterTheSuppressionWindow() {
        var session = Session.atInbox()
        for _ in 0..<4 { session.go(.push, "/explore/", after: 0.1) }
        #expect(session.state.loopGuardTrips == 1)
        #expect(session.go(.push, "/explore/", after: 3) == inbox)
        #expect(session.state.loopGuardTrips == 1)
    }

    // MARK: from a config

    @Test func aConfigDrivesRedirectTargetAndBlockedKinds() {
        let config = FilterConfig.bundledDefault()
        #expect(config.policy.redirectTo == "/direct/inbox/")
        #expect(config.policy.blocked == ["homeFeed", "reelsFeed", "explore"])

        var custom = config
        custom.routes.redirectHomeTo = "/direct/t/1/"
        custom.routes.blocked = ["explore"]
        var state = NavigationState()
        let policy = custom.policy
        #expect(policy.decide(RouteEvent(path: "/explore/", kind: .push), isLoggedIn: true, state: &state) == .redirect("/direct/t/1/"))
        #expect(policy.decide(RouteEvent(path: "/", kind: .push), isLoggedIn: true, state: &state) == .allow)
    }
}
