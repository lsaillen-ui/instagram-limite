import Testing
@testable import FocusBrowser

struct PathRedactorTests {
    private let redactor = PathRedactor(salt: "test-salt")

    @Test func keepsReservedStructureReadable() {
        #expect(redactor.redact("/") == "/")
        #expect(redactor.redact("/direct/inbox/") == "/direct/inbox/")
        #expect(redactor.redact("/reels/") == "/reels/")
        #expect(redactor.redact("/explore/") == "/explore/")
        #expect(redactor.redact("/explore/search/") == "/explore/search/")
        #expect(redactor.redact("/accounts/login/") == "/accounts/login/")
    }

    @Test func tokenizesIdentifyingSegments() {
        let thread = redactor.token(for: "178412")
        #expect(redactor.redact("/direct/t/178412/") == "/direct/t/\(thread)/")
        let reel = redactor.token(for: "Cx9aB")
        #expect(redactor.redact("/reel/Cx9aB/") == "/reel/\(reel)/")
        let post = redactor.token(for: "Dp3")
        #expect(redactor.redact("/p/Dp3/") == "/p/\(post)/")
        let user = redactor.token(for: "louis")
        let story = redactor.token(for: "3301")
        #expect(redactor.redact("/stories/louis/3301/") == "/stories/\(user)/\(story)/")
    }

    @Test func profilesAreMarkedAndKeepTheirTabs() {
        let user = redactor.token(for: "louis")
        #expect(redactor.redact("/louis/") == "/@\(user)/")
        #expect(redactor.redact("/louis/reels/") == "/@\(user)/reels/")
        #expect(redactor.redact("/louis") == "/@\(user)")
    }

    @Test func tokensAreStableAndDistinguishIds() {
        let a = redactor.redact("/reel/aaa/")
        let b = redactor.redact("/reel/bbb/")
        #expect(a == redactor.redact("/reel/aaa/"))
        #expect(a != b)
        // Same segment, same token, wherever it appears.
        #expect(redactor.token(for: "louis") == redactor.token(for: "louis"))
    }

    @Test func tokensDependOnTheSessionSalt() {
        #expect(PathRedactor(salt: "one").token(for: "louis") != PathRedactor(salt: "two").token(for: "louis"))
    }

    @Test func tokenShape() {
        let token = redactor.token(for: "anything")
        #expect(token.count == 5)
        #expect(token.first == "#")
        #expect(token.dropFirst().allSatisfy { $0.isHexDigit })
    }

    @Test func neverLeaksTheOriginalSegment() {
        let out = redactor.redact("/louis/reel/secretreel/178412/")
        for leaked in ["louis", "secretreel", "178412"] { #expect(!out.contains(leaked)) }
    }

    @Test func dropsQueryAndFragment() {
        #expect(redactor.redact("/direct/inbox/?token=abc#frag") == "/direct/inbox/")
    }

    @Test func caseInsensitiveReservedMatchStillKeepsOriginalSpelling() {
        #expect(redactor.redact("/Direct/Inbox/") == "/Direct/Inbox/")
    }
}
