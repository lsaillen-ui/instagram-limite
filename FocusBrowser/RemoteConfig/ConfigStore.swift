import Foundation

/// The on-disk copy of the last valid remote config: three plain files in Application Support
/// (not SwiftData). The signature is checked again on every load, so a file edited on disk is ignored.
struct ConfigStore: Sendable {
    struct Loaded: Sendable {
        let config: FilterConfig
        /// ETag of the cached `config.json`, sent as `If-None-Match`.
        let etag: String?
    }

    let directory: URL
    let publicKey: Data

    private var configURL: URL { directory.appendingPathComponent("config.json") }
    private var signatureURL: URL { directory.appendingPathComponent("config.json.sig") }
    private var etagURL: URL { directory.appendingPathComponent("etag.txt") }

    static var standardDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("FocusBrowser/RemoteConfig", isDirectory: true)
    }

    static func standard() -> ConfigStore {
        ConfigStore(directory: standardDirectory, publicKey: RemoteConfigEndpoint.publicKey)
    }

    /// The cached config if it is complete, correctly signed and valid for this app version.
    func loadCached() -> Loaded? {
        guard
            let data = try? Data(contentsOf: configURL),
            let signature = try? Data(contentsOf: signatureURL),
            let config = try? SignedConfig.open(config: data, signature: signature, publicKey: publicKey, newerThan: nil)
        else { return nil }
        let etag = (try? String(contentsOf: etagURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Loaded(config: config, etag: (etag?.isEmpty ?? true) ? nil : etag)
    }

    /// What the app starts with: the cache, unless the bundled config is newer (an app update).
    /// Never touches the network.
    func startupConfig(bundled: FilterConfig) -> Loaded {
        if let cached = loadCached(), !bundled.revision.isNewer(than: cached.config.revision) { return cached }
        return Loaded(config: bundled, etag: nil)
    }

    /// Call only with bytes that already passed `SignedConfig.open`.
    func save(config: Data, signature: Data, etag: String?) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try config.write(to: configURL, options: .atomic)
        try signature.write(to: signatureURL, options: .atomic)
        if let etag {
            try Data(etag.utf8).write(to: etagURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: etagURL)
        }
    }
}
