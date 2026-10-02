import CryptoKit
import Foundation
import Testing
@testable import FocusBrowser

/// Test doubles and helpers shared by the remote config tests.
private enum Fixtures {
    static let key = Curve25519.Signing.PrivateKey()
    static var publicKey: Data { key.publicKey.rawRepresentation }

    /// The bundled config with edits applied, as raw JSON bytes.
    static func configData(revision: String, edit: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        let url = try #require(Bundle.main.url(forResource: "filters.default", withExtension: "json"))
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["revision"] = revision
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func sign(_ data: Data, with key: Curve25519.Signing.PrivateKey = Fixtures.key) throws -> Data {
        Data((try key.signature(for: data).base64EncodedString() + "\n").utf8)
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("focus-config-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor FakeFetcher: ConfigFetching {
    private var results: [Result<ConfigFetchResult, Error>]
    private(set) var etags: [String?] = []

    init(_ results: [Result<ConfigFetchResult, Error>]) { self.results = results }

    func fetch(etag: String?) async throws -> ConfigFetchResult {
        etags.append(etag)
        guard !results.isEmpty else { return .notModified }
        return try results.removeFirst().get()
    }
}

private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}

private struct Boom: Error {}

struct SignedConfigTests {
    @Test func aCorrectlySignedNewerConfigIsAccepted() throws {
        let data = try Fixtures.configData(revision: "2026-10-02.1")
        let config = try SignedConfig.open(
            config: data, signature: Fixtures.sign(data), publicKey: Fixtures.publicKey, newerThan: "2026-09-30.1"
        )
        #expect(config.revision == "2026-10-02.1")
    }

    @Test func aTamperedConfigIsRejected() throws {
        let data = try Fixtures.configData(revision: "2026-10-02.1")
        let signature = try Fixtures.sign(data)
        let tampered = try Fixtures.configData(revision: "2026-10-02.1") { $0["rules"] = [] }
        #expect(throws: SignedConfig.Failure.badSignature) {
            try SignedConfig.open(config: tampered, signature: signature, publicKey: Fixtures.publicKey, newerThan: nil)
        }
    }

    @Test func aSignatureFromAnotherKeyIsRejected() throws {
        let data = try Fixtures.configData(revision: "2026-10-02.1")
        let stranger = Curve25519.Signing.PrivateKey()
        #expect(throws: SignedConfig.Failure.badSignature) {
            try SignedConfig.open(
                config: data, signature: Fixtures.sign(data, with: stranger), publicKey: Fixtures.publicKey, newerThan: nil
            )
        }
    }

    @Test func garbageSignaturesAreRejected() throws {
        let data = try Fixtures.configData(revision: "2026-10-02.1")
        for garbage in ["", "not base64!!", String(repeating: "A", count: 1000)] {
            #expect(!SignedConfig.verifies(data, signature: Data(garbage.utf8), publicKey: Fixtures.publicKey))
        }
        #expect(!SignedConfig.verifies(data, signature: try Fixtures.sign(data), publicKey: Data([1, 2, 3])))
    }

    @Test func aSignedButInvalidConfigIsRejected() throws {
        let data = try Fixtures.configData(revision: "2026-10-02.1") { $0["surprise"] = true }
        #expect(throws: SignedConfig.Failure.invalid(.unknownKey("surprise"))) {
            try SignedConfig.open(config: data, signature: Fixtures.sign(data), publicKey: Fixtures.publicKey, newerThan: nil)
        }
    }

    @Test func aConfigNeedingANewerEngineIsRejected() throws {
        let data = try Fixtures.configData(revision: "2026-10-02.1") { $0["minEngine"] = FilterConfig.engineVersion + 1 }
        #expect(throws: SignedConfig.Failure.invalid(.engineTooOld(required: FilterConfig.engineVersion + 1))) {
            try SignedConfig.open(config: data, signature: Fixtures.sign(data), publicKey: Fixtures.publicKey, newerThan: nil)
        }
    }

    @Test func anOversizedConfigIsRejectedBeforeAnythingElse() throws {
        let data = Data(repeating: 0x20, count: FilterConfig.maxBytes + 1)
        #expect(throws: SignedConfig.Failure.invalid(.tooLarge)) {
            try SignedConfig.open(config: data, signature: Fixtures.sign(data), publicKey: Fixtures.publicKey, newerThan: nil)
        }
    }

    @Test func sameOrOlderRevisionsAreNotNewer() throws {
        let current = "2026-10-02.2"
        for revision in ["2026-10-02.2", "2026-10-02.1", "2026-09-30.9"] {
            let data = try Fixtures.configData(revision: revision)
            #expect(throws: SignedConfig.Failure.notNewer) {
                try SignedConfig.open(config: data, signature: Fixtures.sign(data), publicKey: Fixtures.publicKey, newerThan: current)
            }
        }
    }

    @Test func revisionsCompareNumerically() {
        #expect("2026-09-29.10".isNewer(than: "2026-09-29.9"))
        #expect("2026-10-01.1".isNewer(than: "2026-09-30.7"))
        #expect(!"2026-09-30.1".isNewer(than: "2026-09-30.1"))
    }

    @Test func theConfigPublishedInTheRepoIsValidAndSignedWithTheBundledKey() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("remote-config")
        let data = try Data(contentsOf: folder.appendingPathComponent("config.json"))
        let signature = try Data(contentsOf: folder.appendingPathComponent("config.json.sig"))
        let config = try SignedConfig.open(
            config: data, signature: signature, publicKey: RemoteConfigEndpoint.publicKey, newerThan: nil
        )
        #expect(config.revision.isNewer(than: FilterConfig.bundledDefault().revision) || config.revision == FilterConfig.bundledDefault().revision)
    }
}

struct ConfigStoreTests {
    private func store() -> ConfigStore {
        ConfigStore(directory: Fixtures.temporaryDirectory(), publicKey: Fixtures.publicKey)
    }

    private func saved(_ store: ConfigStore, revision: String, etag: String? = "\"abc\"") throws {
        let data = try Fixtures.configData(revision: revision)
        try store.save(config: data, signature: Fixtures.sign(data), etag: etag)
    }

    @Test @MainActor func aSavedConfigLoadsBackWithItsETag() throws {
        let store = store()
        #expect(store.loadCached() == nil)
        try saved(store, revision: "2026-10-02.1")
        let loaded = try #require(store.loadCached())
        #expect(loaded.config.revision == "2026-10-02.1")
        #expect(loaded.etag == "\"abc\"")
    }

    @Test @MainActor func aCacheEditedOnDiskIsIgnored() throws {
        let store = store()
        try saved(store, revision: "2026-10-02.1")
        let file = store.directory.appendingPathComponent("config.json")
        var bytes = try Data(contentsOf: file)
        bytes.append(0x20)
        try bytes.write(to: file)
        #expect(store.loadCached() == nil)
    }

    @Test @MainActor func aCacheSignedByAnotherKeyIsIgnored() throws {
        let store = store()
        let data = try Fixtures.configData(revision: "2026-10-02.1")
        try store.save(config: data, signature: Fixtures.sign(data, with: Curve25519.Signing.PrivateKey()), etag: nil)
        #expect(store.loadCached() == nil)
    }

    @Test @MainActor func startupUsesTheCacheWhenItIsNotOlderThanTheBundledConfig() throws {
        let store = store()
        let bundled = FilterConfig.bundledDefault()
        try saved(store, revision: "2999-01-01.1")
        #expect(store.startupConfig(bundled: bundled).config.revision == "2999-01-01.1")
    }

    @Test @MainActor func startupUsesTheBundledConfigWhenTheCacheIsOlder() throws {
        let store = store()
        let bundled = FilterConfig.bundledDefault()
        try saved(store, revision: "2000-01-01.1")
        let startup = store.startupConfig(bundled: bundled)
        #expect(startup.config.revision == bundled.revision)
        #expect(startup.etag == nil)
    }

    @Test @MainActor func startupWithoutACacheUsesTheBundledConfig() {
        let bundled = FilterConfig.bundledDefault()
        #expect(store().startupConfig(bundled: bundled).config == bundled)
    }
}

@MainActor
struct RemoteConfigUpdaterTests {
    private final class Applied { var configs: [FilterConfig] = [] }

    private struct Setup {
        let updater: RemoteConfigUpdater
        let store: ConfigStore
        let fetcher: FakeFetcher
        let clock: FakeClock
        let applied: Applied
    }

    private func setup(_ results: [Result<ConfigFetchResult, Error>], startRevision: String = "2026-09-30.1") throws -> Setup {
        let store = ConfigStore(directory: Fixtures.temporaryDirectory(), publicKey: Fixtures.publicKey)
        var bundled = FilterConfig.bundledDefault()
        bundled.revision = startRevision
        let fetcher = FakeFetcher(results)
        let clock = FakeClock()
        let applied = Applied()
        let updater = RemoteConfigUpdater(
            store: store, fetcher: fetcher, current: .init(config: bundled, etag: nil),
            now: { clock.now }, apply: { applied.configs.append($0) }
        )
        return Setup(updater: updater, store: store, fetcher: fetcher, clock: clock, applied: applied)
    }

    private func update(_ revision: String, etag: String? = "\"v\"") throws -> Result<ConfigFetchResult, Error> {
        let data = try Fixtures.configData(revision: revision)
        return .success(.updated(config: data, signature: try Fixtures.sign(data), etag: etag))
    }

    @Test func aValidUpdateIsPersistedThenApplied() async throws {
        let s = try setup([update("2026-10-02.1")])
        #expect(await s.updater.refresh() == .updated(revision: "2026-10-02.1"))
        #expect(s.applied.configs.map(\.revision) == ["2026-10-02.1"])
        #expect(s.store.loadCached()?.config.revision == "2026-10-02.1")
        #expect(s.updater.currentRevision == "2026-10-02.1")
    }

    @Test func theNextRequestCarriesTheNewETag() async throws {
        let s = try setup([update("2026-10-02.1", etag: "\"v1\""), .success(.notModified)])
        _ = await s.updater.refresh()
        #expect(await s.updater.refresh() == .unchanged)
        #expect(await s.fetcher.etags == [nil, "\"v1\""])
        #expect(s.applied.configs.count == 1)
    }

    @Test func aBadSignatureKeepsTheCurrentConfig() async throws {
        let data = try Fixtures.configData(revision: "2026-10-02.1")
        let forged = try Fixtures.sign(data, with: Curve25519.Signing.PrivateKey())
        let s = try setup([.success(.updated(config: data, signature: forged, etag: "\"v\""))])
        let outcome = await s.updater.refresh()
        guard case .rejected = outcome else { Issue.record("expected a rejection"); return }
        #expect(s.applied.configs.isEmpty)
        #expect(s.store.loadCached() == nil)
        #expect(s.updater.currentRevision == "2026-09-30.1")
    }

    @Test func anInvalidSignedConfigKeepsTheCurrentConfig() async throws {
        let data = try Fixtures.configData(revision: "2026-10-02.1") { $0["rules"] = [["id": "x", "hide": "a { color: red }"]] }
        let s = try setup([.success(.updated(config: data, signature: try Fixtures.sign(data), etag: nil))])
        let outcome = await s.updater.refresh()
        guard case .rejected = outcome else { Issue.record("expected a rejection"); return }
        #expect(s.applied.configs.isEmpty)
    }

    @Test func anOlderSignedConfigIsNotApplied() async throws {
        let s = try setup([update("2026-09-01.1")])
        #expect(await s.updater.refresh() == .unchanged)
        #expect(s.applied.configs.isEmpty)
    }

    @Test func aNetworkFailureChangesNothing() async throws {
        let s = try setup([.failure(Boom())])
        #expect(await s.updater.refresh() == .failed)
        #expect(s.applied.configs.isEmpty)
        #expect(s.store.loadCached() == nil)
    }

    @Test func refreshesAreThrottled() async throws {
        let s = try setup([])
        s.updater.refreshAtLaunch()
        await settle(s.fetcher, calls: 1)

        s.clock.advance(RemoteConfigUpdater.healthRefreshInterval - 1)
        s.updater.refreshAfterHealthFailure()
        s.updater.refreshIfStale()
        await settle(s.fetcher, calls: 2, expectingMore: false)
        #expect(await s.fetcher.etags.count == 1)

        s.clock.advance(2)
        s.updater.refreshAfterHealthFailure()
        await settle(s.fetcher, calls: 2)
        #expect(await s.fetcher.etags.count == 2)

        s.clock.advance(RemoteConfigUpdater.staleAfter)
        s.updater.refreshIfStale()
        await settle(s.fetcher, calls: 3)
        #expect(await s.fetcher.etags.count == 3)
    }

    /// Waits for the fire-and-forget refresh to reach the fetcher.
    private func settle(_ fetcher: FakeFetcher, calls: Int, expectingMore: Bool = true) async {
        for _ in 0..<(expectingMore ? 100 : 10) {
            if await fetcher.etags.count >= calls, expectingMore { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
