import Foundation

/// The Swift side of the injected scripts: assembles their sources.
enum InjectionScripts {
    /// The engine source followed by the one call that hands it its config. The config is
    /// re-encoded from the validated `FilterConfig` value, so it is always a JSON data literal.
    @MainActor
    static func focusEngine(config: FilterConfig) throws -> String {
        let json = try config.pageJSON()
        return BrowserConfiguration.scriptSource(named: "focus-engine") + "\n__focus.apply(" + json + ");\n"
    }
}
