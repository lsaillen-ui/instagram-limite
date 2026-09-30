import Testing
@testable import FocusBrowser

struct RouteMessageTests {
    private func body(_ path: Any, _ kind: Any) -> [String: Any] { ["path": path, "kind": kind] }

    @Test func acceptsEveryKind() {
        for kind in ["push", "replace", "pop", "initial"] {
            let event = RouteMessage.event(from: body("/direct/inbox/", kind))
            #expect(event == RouteEvent(path: "/direct/inbox/", kind: RouteEventKind(rawValue: kind)!))
        }
        #expect(RouteMessage.event(from: body("/", "initial"))?.path == "/")
    }

    @Test func ignoresExtraKeys() {
        let event = RouteMessage.event(from: ["path": "/p/abc/", "kind": "push", "extra": 1])
        #expect(event == RouteEvent(path: "/p/abc/", kind: .push))
    }

    @Test func rejectsMalformedPayloads() {
        #expect(RouteMessage.event(from: 42) == nil)
        #expect(RouteMessage.event(from: "/direct/inbox/") == nil)  // the old bare-string shape
        #expect(RouteMessage.event(from: ["path": "/x"]) == nil)
        #expect(RouteMessage.event(from: ["kind": "push"]) == nil)
        #expect(RouteMessage.event(from: body(42, "push")) == nil)
        #expect(RouteMessage.event(from: body("/x", 42)) == nil)
    }

    @Test func rejectsUnknownKinds() {
        #expect(RouteMessage.event(from: body("/x", "reload")) == nil)
        #expect(RouteMessage.event(from: body("/x", "PUSH")) == nil)
        #expect(RouteMessage.event(from: body("/x", "")) == nil)
    }

    @Test func rejectsImplausiblePaths() {
        #expect(RouteMessage.event(from: body("", "push")) == nil)
        #expect(RouteMessage.event(from: body("no-slash", "push")) == nil)
        #expect(RouteMessage.event(from: body("//evil.example/x", "push")) == nil)
        #expect(RouteMessage.event(from: body("/" + String(repeating: "a", count: 3000), "push")) == nil)
    }
}
