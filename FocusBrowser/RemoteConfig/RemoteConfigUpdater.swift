import Foundation

/// Fetches the public filter config in the background and hands a validated one to `apply`.
/// Never blocks startup; any failure keeps the config in use.
@MainActor
final class RemoteConfigUpdater {
    enum Outcome: Equatable {
        case updated(revision: String)
        case unchanged
        case rejected(String)
        case failed
        case skipped
    }

    static let staleAfter: TimeInterval = 6 * 3600
    /// A rule reporting itself unhealthy forces a refresh, at most this often.
    static let healthRefreshInterval: TimeInterval = 15 * 60

    private let store: ConfigStore
    private let fetcher: any ConfigFetching
    private let now: @Sendable () -> Date
    private let apply: @MainActor (FilterConfig) async -> Void

    private(set) var currentRevision: String
    private var etag: String?
    private var lastAttempt: Date?
    private var inFlight = false

    init(
        store: ConfigStore,
        fetcher: any ConfigFetching,
        current: ConfigStore.Loaded,
        now: @escaping @Sendable () -> Date = { Date() },
        apply: @escaping @MainActor (FilterConfig) async -> Void
    ) {
        self.store = store
        self.fetcher = fetcher
        self.currentRevision = current.config.revision
        self.etag = current.etag
        self.now = now
        self.apply = apply
    }

    // MARK: Triggers (fire and forget)

    func refreshAtLaunch() {
        start()
    }

    /// For `scenePhase == .active`.
    func refreshIfStale() {
        if let lastAttempt, now().timeIntervalSince(lastAttempt) < Self.staleAfter { return }
        start()
    }

    func refreshAfterHealthFailure() {
        if let lastAttempt, now().timeIntervalSince(lastAttempt) < Self.healthRefreshInterval { return }
        start()
    }

    private func start() {
        Task { _ = await refresh() }
    }

    // MARK: Refresh

    @discardableResult
    func refresh() async -> Outcome {
        guard !inFlight else { return .skipped }
        inFlight = true
        lastAttempt = now()
        defer { inFlight = false }

        let outcome = await run()
        #if DEBUG
        print("[FocusBrowser] config refresh: \(outcome) (revision \(currentRevision))")
        #endif
        return outcome
    }

    private func run() async -> Outcome {
        let result: ConfigFetchResult
        do {
            result = try await fetcher.fetch(etag: etag)
        } catch {
            return .failed
        }
        guard case .updated(let data, let signature, let newETag) = result else { return .unchanged }

        let config: FilterConfig
        do {
            config = try SignedConfig.open(
                config: data, signature: signature, publicKey: store.publicKey, newerThan: currentRevision
            )
        } catch SignedConfig.Failure.notNewer {
            return .unchanged
        } catch {
            return .rejected("\(error)")
        }

        do {
            try store.save(config: data, signature: signature, etag: newETag)
        } catch {
            return .failed
        }
        currentRevision = config.revision
        etag = newETag
        await apply(config)
        return .updated(revision: config.revision)
    }
}
