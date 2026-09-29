import Testing
@testable import FocusBrowser

struct RouteMessageTests {
    @Test func acceptsPaths() {
        #expect(RouteMessage.path(from: "/direct/inbox/") == "/direct/inbox/")
        #expect(RouteMessage.path(from: "/") == "/")
    }

    @Test func rejectsMalformedPayloads() {
        #expect(RouteMessage.path(from: 42) == nil)
        #expect(RouteMessage.path(from: ["a": 1]) == nil)
        #expect(RouteMessage.path(from: "") == nil)
        #expect(RouteMessage.path(from: "no-slash") == nil)
        #expect(RouteMessage.path(from: "//evil.example/x") == nil)
        #expect(RouteMessage.path(from: "/" + String(repeating: "a", count: 3000)) == nil)
    }
}
