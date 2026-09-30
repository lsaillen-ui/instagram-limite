import Foundation

/// The filter config: data only (selectors, route patterns, locale strings). Never code.
/// Bundled as `filters.default.json`; Step 3 adds the remote copy, which goes through the same
/// `decode(_:)`.
struct FilterConfig: Codable, Equatable, Sendable {
    /// Highest engine version this app implements: a config's `minEngine` may not exceed it.
    static let engineVersion = 1
    static let supportedSchema = 1
    static let maxBytes = 64 * 1024

    struct Routes: Codable, Equatable, Sendable {
        /// Where blocked routes and cold content land.
        var redirectHomeTo: String
        /// Kind names (`RouteKind.name`) that are redirected.
        var blocked: [String]
        /// Optional per-kind regex overrides; a missing kind uses `RouteClassifier.defaultPatterns`.
        var patterns: [String: [String]]
    }

    struct Rule: Codable, Equatable, Sendable {
        var id: String
        /// A CSS selector list. The engine hides what it matches (`display: none !important`);
        /// a rule cannot carry declarations.
        var hide: String
        /// Route kind names the rule is limited to; absent means everywhere.
        var routeScope: [String]?
        /// Path regexes where the rule must match something, or the engine reports it unhealthy.
        var expectOn: [String]?
    }

    var schema: Int
    var minEngine: Int
    var revision: String
    var routes: Routes
    var rules: [Rule]
    /// locale → key → text (for the text-based rules).
    var i18n: [String: [String: String]]

    enum ValidationError: Error, Equatable {
        case tooLarge
        case malformed
        case unknownKey(String)
        case unsupportedSchema(Int)
        case engineTooOld(required: Int)
        case invalid(String)
    }

    // MARK: Decoding and validation

    /// Strict decoding: size, exact key sets, types, then `validate()`.
    static func decode(_ data: Data) throws -> FilterConfig {
        guard data.count <= maxBytes else { throw ValidationError.tooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ValidationError.malformed
        }
        try checkKeys(object)
        guard let config = try? JSONDecoder().decode(FilterConfig.self, from: data) else {
            throw ValidationError.malformed
        }
        try config.validate()
        return config
    }

    private static func checkKeys(_ root: [String: Any]) throws {
        func check(_ object: [String: Any], allowed: Set<String>, at path: String) throws {
            if let extra = Set(object.keys).subtracting(allowed).sorted().first {
                throw ValidationError.unknownKey(path.isEmpty ? extra : "\(path).\(extra)")
            }
        }
        try check(root, allowed: ["schema", "minEngine", "revision", "routes", "rules", "i18n"], at: "")
        if let routes = root["routes"] as? [String: Any] {
            try check(routes, allowed: ["redirectHomeTo", "blocked", "patterns"], at: "routes")
        }
        for (index, rule) in ((root["rules"] as? [Any]) ?? []).enumerated() {
            if let rule = rule as? [String: Any] {
                try check(rule, allowed: ["id", "hide", "routeScope", "expectOn"], at: "rules[\(index)]")
            }
        }
    }

    func validate() throws {
        guard schema == Self.supportedSchema else { throw ValidationError.unsupportedSchema(schema) }
        guard minEngine <= Self.engineVersion else { throw ValidationError.engineTooOld(required: minEngine) }
        guard !revision.isEmpty, revision.count <= 40 else { throw ValidationError.invalid("revision") }

        let target = routes.redirectHomeTo
        guard target.hasPrefix("/"), !target.hasPrefix("//"), target.count <= 200,
              !target.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw ValidationError.invalid("routes.redirectHomeTo")
        }
        for name in routes.blocked where !RouteKind.allNames.contains(name) {
            throw ValidationError.invalid("routes.blocked: \(name)")
        }
        for (kind, patterns) in routes.patterns {
            guard RouteClassifier.configurableKinds.contains(kind) else {
                throw ValidationError.invalid("routes.patterns: \(kind)")
            }
            for pattern in patterns {
                let regex = try Self.compile(pattern, field: "routes.patterns.\(kind)")
                if kind == "reel" || kind == "story", regex.numberOfCaptureGroups < 1 {
                    throw ValidationError.invalid("routes.patterns.\(kind): needs a capture group")
                }
            }
        }

        guard rules.count <= 100 else { throw ValidationError.invalid("rules: too many") }
        var seen = Set<String>()
        for rule in rules {
            guard rule.id.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil else {
                throw ValidationError.invalid("rule id: \(rule.id)")
            }
            guard seen.insert(rule.id).inserted else { throw ValidationError.invalid("duplicate rule id: \(rule.id)") }
            // The engine wraps the selector in one rule; these characters could end it early or add more.
            guard !rule.hide.isEmpty, rule.hide.count <= 500,
                  rule.hide.rangeOfCharacter(from: CharacterSet(charactersIn: "{};@\n\r")) == nil else {
                throw ValidationError.invalid("rule \(rule.id): hide")
            }
            for scope in rule.routeScope ?? [] where !RouteKind.allNames.contains(scope) {
                throw ValidationError.invalid("rule \(rule.id): routeScope \(scope)")
            }
            for pattern in rule.expectOn ?? [] { _ = try Self.compile(pattern, field: "rule \(rule.id): expectOn") }
        }

        for (locale, table) in i18n {
            guard locale.range(of: "^[a-z]{2}(-[A-Z]{2})?$", options: .regularExpression) != nil,
                  table.count <= 20, table.allSatisfy({ $0.key.count <= 40 && $0.value.count <= 100 }) else {
                throw ValidationError.invalid("i18n: \(locale)")
            }
        }
    }

    private static func compile(_ pattern: String, field: String) throws -> NSRegularExpression {
        guard !pattern.isEmpty, pattern.count <= 200, let regex = try? NSRegularExpression(pattern: pattern) else {
            throw ValidationError.invalid("\(field): regex")
        }
        return regex
    }

    // MARK: Using it

    var classifier: RouteClassifier { RouteClassifier(patterns: routes.patterns) }

    var policy: RoutePolicy {
        RoutePolicy(classifier: classifier, redirectTo: routes.redirectHomeTo, blocked: Set(routes.blocked))
    }

    /// The JSON the page engine receives: re-encoded from this validated value (never the raw file
    /// bytes, so a config can only ever carry data), with the built-in route patterns filled in so
    /// the page needs no defaults of its own.
    func pageJSON() throws -> String {
        var resolved = self
        for (kind, patterns) in RouteClassifier.defaultPatterns where resolved.routes.patterns[kind] == nil {
            resolved.routes.patterns[kind] = patterns
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(resolved), as: UTF8.self)
    }

    /// The config shipped in the app. A broken bundled file is a build error, not a runtime condition.
    static func bundledDefault() -> FilterConfig {
        guard
            let url = Bundle.main.url(forResource: "filters.default", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let config = try? decode(data)
        else { preconditionFailure("Missing or invalid bundled filters.default.json") }
        return config
    }
}
