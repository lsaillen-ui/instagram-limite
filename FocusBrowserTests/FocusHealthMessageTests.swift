import Testing
@testable import FocusBrowser

struct FocusHealthMessageTests {
    @Test func acceptsAFailure() {
        let failure = FocusHealthMessage.failure(from: ["ruleId": "nav.home", "path": "/p/abc/", "reason": "nomatch"])
        #expect(failure == HealthFailure(ruleId: "nav.home", path: "/p/abc/", reason: "nomatch"))
    }

    @Test func reasonDefaultsToNoMatchAndAcceptsInvalid() {
        #expect(FocusHealthMessage.failure(from: ["ruleId": "a", "path": "/"])?.reason == "nomatch")
        #expect(FocusHealthMessage.failure(from: ["ruleId": "a", "path": "/", "reason": "invalid"])?.reason == "invalid")
    }

    @Test func rejectsMalformedPayloads() {
        #expect(FocusHealthMessage.failure(from: "nav.home") == nil)
        #expect(FocusHealthMessage.failure(from: ["path": "/"]) == nil)
        #expect(FocusHealthMessage.failure(from: ["ruleId": "a"]) == nil)
        #expect(FocusHealthMessage.failure(from: ["ruleId": "has space", "path": "/"]) == nil)
        #expect(FocusHealthMessage.failure(from: ["ruleId": "a", "path": "//evil"]) == nil)
        #expect(FocusHealthMessage.failure(from: ["ruleId": "a", "path": "no-slash"]) == nil)
        #expect(FocusHealthMessage.failure(from: ["ruleId": "a", "path": "/", "reason": "boom"]) == nil)
        #expect(FocusHealthMessage.failure(from: ["ruleId": 1, "path": "/"]) == nil)
    }
}
