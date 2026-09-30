import Testing
import WebKit
@testable import FocusBrowser

@MainActor
struct BrowserConfigurationTests {
    private final class NullHandler: NSObject, WKScriptMessageHandler {
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {}
    }

    @Test func applicationNameCarriesSafariToken() {
        #expect(BrowserConfiguration.applicationName(osMajorVersion: 18) == "Version/18.0 Mobile/15E148 Safari/604.1")
    }

    @Test func configurationMatchesDecisions() {
        let handler = NullHandler()
        let configuration = BrowserConfiguration.makeWebViewConfiguration(routeHandler: handler)
        #expect(configuration.websiteDataStore.isPersistent)
        #expect(configuration.allowsInlineMediaPlayback)
        #expect(configuration.mediaTypesRequiringUserActionForPlayback == .all)
        #expect(configuration.applicationNameForUserAgent?.contains("Safari/") == true)

        let scripts = configuration.userContentController.userScripts
        #if DEBUG
        #expect(scripts.count == 4)  // base, route hook, recon, focus engine
        #else
        #expect(scripts.count == 3)
        #endif
        #expect(scripts.allSatisfy { $0.injectionTime == .atDocumentStart && $0.isForMainFrameOnly })
    }

    @Test func bundledScriptsArePresent() {
        #expect(!BrowserConfiguration.scriptSource(named: "base").isEmpty)
        #expect(!BrowserConfiguration.scriptSource(named: "route-hook").isEmpty)
        #expect(!BrowserConfiguration.scriptSource(named: "focus-engine").isEmpty)
        #if DEBUG
        #expect(!BrowserConfiguration.scriptSource(named: "recon").isEmpty)
        #endif
    }
}
