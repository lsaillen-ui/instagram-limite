import Testing
@testable import FocusBrowser

struct RouteClassifierTests {
    private let classifier = RouteClassifier()

    @Test(arguments: [
        ("/", RouteKind.homeFeed),
        ("/direct/inbox/", .inbox),
        ("/direct/new/", .inbox),
        ("/direct/t/178412/", .thread),
        ("/p/Dp3/", .post),
        ("/p/Dp3/comments/", .post),
        ("/p/Dp3/liked_by/", .post),
        ("/bob/p/Dp3/", .post),
        ("/reel/Cx9/", .reel(id: "Cx9")),
        ("/reels/Cx9/", .reel(id: "Cx9")),
        ("/bob/reel/Cx9/", .reel(id: "Cx9")),
        ("/reels/", .reelsFeed),
        ("/reels/audio/123/", .reelsFeed),
        ("/stories/bob/", .story(owner: "bob", id: nil)),
        ("/stories/bob/3301/", .story(owner: "bob", id: "3301")),
        ("/stories/highlights/55/", .story(owner: "highlights", id: "55")),
        ("/explore/", .explore),
        ("/explore/search/", .explore),
        ("/explore/tags/cats/", .explore),
        ("/explore/locations/1/name/", .explore),
        ("/accounts/login/", .auth),
        ("/accounts/password/reset/", .auth),
        ("/challenge/action/", .auth),
        ("/bob/", .profile),
        ("/bob", .profile),
        ("/bob/reels/", .profile),
        ("/bob/tagged/", .profile),
        ("/bob/followers/", .profile),
        ("/about/", .unknown),
        ("/api/v1/thing", .unknown),
        ("/has space/", .unknown),
    ])
    func classifiesObservedPaths(path: String, expected: RouteKind) {
        #expect(classifier.classify(path) == expected)
    }

    @Test func hubsAndContent() {
        for kind in [RouteKind.inbox, .thread, .profile, .post] { #expect(kind.isHub && !kind.isContent) }
        for kind in [RouteKind.reel(id: "a"), .story(owner: "b", id: nil)] { #expect(kind.isContent && !kind.isHub) }
        for kind in [RouteKind.homeFeed, .reelsFeed, .explore, .auth, .unknown] { #expect(!kind.isHub && !kind.isContent) }
    }

    @Test func sameContent() {
        #expect(RouteKind.reel(id: "a").isSameContent(as: .reel(id: "a")))
        #expect(!RouteKind.reel(id: "a").isSameContent(as: .reel(id: "b")))
        // The next story of the same person is the same item; another person's is not.
        #expect(RouteKind.story(owner: "bob", id: "1").isSameContent(as: .story(owner: "bob", id: "2")))
        #expect(!RouteKind.story(owner: "bob", id: "1").isSameContent(as: .story(owner: "eve", id: "1")))
        #expect(!RouteKind.reel(id: "a").isSameContent(as: .story(owner: "a", id: nil)))
    }

    @Test func kindNamesAreTheConfigVocabulary() {
        let kinds: [RouteKind] = [.inbox, .thread, .profile, .post, .reel(id: "a"), .story(owner: "b", id: nil),
                                  .homeFeed, .reelsFeed, .explore, .auth, .unknown]
        #expect(Set(kinds.map(\.name)) == RouteKind.allNames)
    }

    @Test func configPatternsOverrideTheirKind() {
        let custom = RouteClassifier(patterns: ["explore": ["^/discover/"]])
        #expect(custom.classify("/discover/x") == .explore)
        #expect(custom.classify("/explore/") == .unknown)  // "explore" is a reserved word, not a username
        // Kinds the config does not mention keep the built-in patterns.
        #expect(custom.classify("/direct/inbox/") == .inbox)
        #expect(custom.classify("/reels/") == .reelsFeed)
    }

    @Test func aPatternThatDoesNotCompileFallsBackToTheDefaults() {
        let custom = RouteClassifier(patterns: ["explore": ["("], "reelsFeed": ["^/feed/$", "["]])
        #expect(custom.classify("/explore/") == .explore)
        #expect(custom.classify("/reels/") == .reelsFeed)
    }

    @Test func reelPatternWithoutCaptureGroupCannotIdentifyContent() {
        let custom = RouteClassifier(patterns: ["reel": ["^/clip/[^/]+"]])
        #expect(custom.classify("/clip/x") == .unknown)
    }
}
