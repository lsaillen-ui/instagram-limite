import Foundation
import Testing
@testable import FocusBrowser

@MainActor
struct FilterConfigTests {
    private func validObject() throws -> [String: Any] {
        let url = try #require(Bundle.main.url(forResource: "filters.default", withExtension: "json"))
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// The valid config with one edit applied, as raw JSON bytes.
    private func data(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try validObject()
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func expectFailure(_ edit: (inout [String: Any]) -> Void, _ expected: FilterConfig.ValidationError? = nil) throws {
        let bytes = try data(edit)
        do {
            _ = try FilterConfig.decode(bytes)
            Issue.record("expected the config to be rejected")
        } catch let error as FilterConfig.ValidationError {
            if let expected { #expect(error == expected) }
        }
    }

    private func setRoutes(_ object: inout [String: Any], _ key: String, _ value: Any) {
        var routes = object["routes"] as! [String: Any]
        routes[key] = value
        object["routes"] = routes
    }

    private func setRule(_ object: inout [String: Any], _ index: Int, _ key: String, _ value: Any) {
        var rules = object["rules"] as! [[String: Any]]
        rules[index][key] = value
        object["rules"] = rules
    }

    // MARK: the bundled file

    @Test func bundledDefaultIsValid() throws {
        let config = FilterConfig.bundledDefault()
        #expect(config.schema == 1)
        #expect(config.minEngine <= FilterConfig.engineVersion)
        #expect(config.rules.map(\.id) == ["nav.home", "nav.explore", "nav.reels"])
        #expect(config.rules.allSatisfy { !($0.expectOn ?? []).isEmpty })
        #expect(config.routes.blocked == ["homeFeed", "reelsFeed", "explore"])
        #expect(config.i18n["en"]?["suggested"] != nil && config.i18n["fr"]?["suggested"] != nil)
        try config.validate()
    }

    @Test func bundledPatternsMatchTheBuiltInDefaults() {
        // The file is the source of truth, the built-ins its fallback: they must not drift apart.
        #expect(FilterConfig.bundledDefault().routes.patterns == RouteClassifier.defaultPatterns)
    }

    @Test func bundledFileIsWellUnderTheSizeLimit() throws {
        let url = try #require(Bundle.main.url(forResource: "filters.default", withExtension: "json"))
        #expect(try Data(contentsOf: url).count < FilterConfig.maxBytes / 4)
    }

    // MARK: rejected configs

    @Test func rejectsOversizedConfigs() throws {
        let big = try data { $0["revision"] = String(repeating: "x", count: 70_000) }
        #expect(throws: FilterConfig.ValidationError.tooLarge) { try FilterConfig.decode(big) }
    }

    @Test func rejectsMalformedJSONAndWrongShapes() {
        for text in ["", "not json", "[]", "{}", #"{"schema":"1"}"#] {
            #expect(throws: FilterConfig.ValidationError.malformed) { try FilterConfig.decode(Data(text.utf8)) }
        }
    }

    @Test func rejectsUnknownKeysAtEveryLevel() throws {
        try expectFailure({ $0["script"] = "alert(1)" }, .unknownKey("script"))
        try expectFailure({ setRoutes(&$0, "eval", "x") }, .unknownKey("routes.eval"))
        try expectFailure({ setRule(&$0, 0, "css", "body { }") }, .unknownKey("rules[0].css"))
    }

    @Test func rejectsIncompatibleVersions() throws {
        try expectFailure({ $0["schema"] = 2 }, .unsupportedSchema(2))
        try expectFailure({ $0["minEngine"] = FilterConfig.engineVersion + 1 }, .engineTooOld(required: FilterConfig.engineVersion + 1))
    }

    @Test func rejectsRegexesThatDoNotCompile() throws {
        try expectFailure { self.setRule(&$0, 0, "expectOn", ["("]) }
        try expectFailure { self.setRoutes(&$0, "patterns", ["explore": ["["]]) }
    }

    @Test func rejectsUnknownPatternKindsAndBlockedNames() throws {
        try expectFailure { self.setRoutes(&$0, "patterns", ["profile": ["^/x"]]) }
        try expectFailure { self.setRoutes(&$0, "blocked", ["everything"]) }
    }

    @Test func reelAndStoryPatternsNeedACaptureGroup() throws {
        try expectFailure { self.setRoutes(&$0, "patterns", ["reel": ["^/clip/[^/]+"]]) }
        try expectFailure { self.setRoutes(&$0, "patterns", ["story": ["^/s/[^/]+"]]) }
    }

    @Test func rejectsDuplicateAndMalformedRuleIds() throws {
        try expectFailure { self.setRule(&$0, 1, "id", "nav.home") }
        try expectFailure { self.setRule(&$0, 0, "id", "has space") }
        try expectFailure { self.setRule(&$0, 0, "id", "") }
    }

    @Test func rejectsSelectorsThatCouldCarryMoreThanASelector() throws {
        for hide in ["", "a } body { display: none", "a; color: red", "@import url(x)", "a\nb"] {
            try expectFailure { self.setRule(&$0, 0, "hide", hide) }
        }
    }

    @Test func rejectsUnknownRouteScopes() throws {
        try expectFailure { self.setRule(&$0, 0, "routeScope", ["nowhere"]) }
    }

    @Test func rejectsUnsafeRedirectTargets() throws {
        for target in ["direct/inbox/", "//evil.example/x", "/has space", ""] {
            try expectFailure { self.setRoutes(&$0, "redirectHomeTo", target) }
        }
    }

    @Test func rejectsBadLocales() throws {
        try expectFailure { $0["i18n"] = ["french": ["suggested": "x"]] }
        try expectFailure { $0["i18n"] = ["fr": ["suggested": String(repeating: "x", count: 500)]] }
    }

    @Test func acceptsARuleScopedToKnownRoutes() throws {
        let bytes = try data { self.setRule(&$0, 0, "routeScope", ["reel", "story"]) }
        #expect(try FilterConfig.decode(bytes).rules[0].routeScope == ["reel", "story"])
    }

    // MARK: what the page receives

    @Test func pageJSONFillsInBuiltInPatternsAndIsCanonical() throws {
        var config = FilterConfig.bundledDefault()
        config.routes.patterns = ["explore": ["^/discover/"]]
        let json = try config.pageJSON()
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let patterns = try #require((object["routes"] as? [String: Any])?["patterns"] as? [String: [String]])
        #expect(patterns["explore"] == ["^/discover/"])  // the override wins
        #expect(patterns["homeFeed"] == RouteClassifier.defaultPatterns["homeFeed"])  // the rest is filled in
        #expect(try config.pageJSON() == json)  // stable output
        #expect(!json.contains("\\/"))
    }

    @Test func pageJSONIsReEncodedFromTheValidatedValueNotTheRawBytes() throws {
        // The same config with different whitespace and key order encodes to the same page JSON.
        let url = try #require(Bundle.main.url(forResource: "filters.default", withExtension: "json"))
        let raw = try Data(contentsOf: url)
        let padded = Data((String(decoding: raw, as: UTF8.self) + "\n\n   \n").utf8)
        let compact = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: raw))
        let json = try FilterConfig.decode(raw).pageJSON()
        #expect(try FilterConfig.decode(padded).pageJSON() == json)
        #expect(try FilterConfig.decode(compact).pageJSON() == json)
        #expect(json != String(decoding: raw, as: UTF8.self))
    }

    @Test func engineScriptIsEngineSourcePlusOneApplyCall() throws {
        let config = FilterConfig.bundledDefault()
        let script = try InjectionScripts.focusEngine(config: config)
        #expect(script.hasPrefix(BrowserConfiguration.scriptSource(named: "focus-engine")))
        #expect(script.hasSuffix("\n__focus.apply(" + (try config.pageJSON()) + ");\n"))
    }
}
