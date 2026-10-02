import Foundation

enum ConfigFetchResult: Equatable, Sendable {
    case notModified
    case updated(config: Data, signature: Data, etag: String?)
}

enum ConfigFetchError: Error, Equatable {
    case badStatus(Int)
    case tooLarge
    case notHTTPS
}

protocol ConfigFetching: Sendable {
    func fetch(etag: String?) async throws -> ConfigFetchResult
}

/// Fetches `config.json` (conditionally) and, when it changed, `config.json.sig`.
/// Anonymous: ephemeral session, no cookies, no cache, no headers beyond `If-None-Match`.
struct URLSessionConfigFetcher: ConfigFetching {
    static let timeout: TimeInterval = 5
    static let maxSignatureBytes = 256

    let baseURL: URL

    func fetch(etag: String?) async throws -> ConfigFetchResult {
        guard baseURL.scheme == "https" else { throw ConfigFetchError.notHTTPS }

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = Self.timeout
        sessionConfiguration.timeoutIntervalForResource = Self.timeout * 2
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.urlCache = nil
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.finishTasksAndInvalidate() }

        let config = try await get("config.json", etag: etag, maxBytes: FilterConfig.maxBytes, using: session)
        if config.status == 304 { return .notModified }
        let signature = try await get("config.json.sig", etag: nil, maxBytes: Self.maxSignatureBytes, using: session)
        return .updated(config: config.body, signature: signature.body, etag: config.etag)
    }

    private func get(
        _ name: String, etag: String?, maxBytes: Int, using session: URLSession
    ) async throws -> (status: Int, body: Data, etag: String?) {
        var request = URLRequest(
            url: baseURL.appendingPathComponent(name),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: Self.timeout
        )
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ConfigFetchError.badStatus(0) }
        if http.statusCode == 304 { return (304, Data(), nil) }
        guard http.statusCode == 200 else { throw ConfigFetchError.badStatus(http.statusCode) }

        var body = Data()
        for try await byte in bytes {
            body.append(byte)
            if body.count > maxBytes { throw ConfigFetchError.tooLarge }
        }
        return (200, body, http.value(forHTTPHeaderField: "ETag"))
    }
}
