import Foundation
import Testing
@testable import FocusBrowser

struct NavigationHygieneTests {
    private func verdict(_ string: String, main: Bool = true) -> NavigationVerdict {
        NavigationHygiene.verdict(for: URL(string: string), isMainFrame: main)
    }

    @Test func nilURLIsCancelled() {
        #expect(NavigationHygiene.verdict(for: nil, isMainFrame: true) == .cancel)
    }

    @Test(arguments: [
        "instagram://user?username=foo",
        "itms-apps://apps.apple.com/app/id1",
        "https://apps.apple.com/app/instagram/id389801252",
        "mailto:a@b.c",
        "tel:123",
    ])
    func appLaunchingURLsAreCancelled(_ url: String) {
        #expect(verdict(url) == .cancel)
        #expect(verdict(url, main: false) == .cancel)
    }

    @Test(arguments: [
        "https://www.instagram.com/direct/inbox/",
        "https://instagram.com/",
        "https://i.instagram.com/x",
        "about:blank",
        "blob:https://www.instagram.com/abc",
    ])
    func instagramAndInternalURLsAreAllowed(_ url: String) {
        #expect(verdict(url) == .allow)
    }

    @Test func lookalikeHostsAreNotInstagram() {
        let url = URL(string: "https://evilinstagram.com/")!
        #expect(verdict(url.absoluteString) == .openInSafari(url))
        let url2 = URL(string: "https://instagram.com.evil.example/")!
        #expect(verdict(url2.absoluteString) == .openInSafari(url2))
    }

    @Test func externalHostsOpenInSafari() {
        let url = URL(string: "https://example.com/page?a=1")!
        #expect(verdict(url.absoluteString) == .openInSafari(url))
    }

    @Test func externalSubframesAreAllowed() {
        #expect(verdict("https://example.com/embed", main: false) == .allow)
    }

    @Test func linkShimIsUnwrapped() {
        let shim = "https://l.instagram.com/?u=https%3A%2F%2Fexample.com%2Fa%3Fb%3D1&e=xyz"
        #expect(verdict(shim) == .openInSafari(URL(string: "https://example.com/a?b=1")!))
    }

    @Test(arguments: [
        "https://l.instagram.com/",
        "https://l.instagram.com/?u=javascript%3Aalert(1)",
        "https://l.instagram.com/?u=instagram%3A%2F%2Fuser",
        "https://l.instagram.com/?u=not%20a%20url",
    ])
    func invalidLinkShimIsCancelled(_ url: String) {
        #expect(verdict(url) == .cancel)
    }
}
