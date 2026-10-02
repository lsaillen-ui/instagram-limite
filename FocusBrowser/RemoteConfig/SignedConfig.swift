import CryptoKit
import Foundation

/// Turns the bytes of a remote `config.json` plus its `config.json.sig` into a trusted `FilterConfig`.
/// Pure: no network, no disk, no WebKit.
enum SignedConfig {
    enum Failure: Error, Equatable {
        case badSignature
        case invalid(FilterConfig.ValidationError)
        /// Well formed and signed, but not newer than what the app already has (also blocks replays
        /// of an older signed config).
        case notNewer
    }

    /// `signature` is the base64 text of the 64-byte Ed25519 signature over the exact `config` bytes.
    /// `publicKey` is the raw 32-byte key. `current` is the revision already in use, if any.
    static func open(config: Data, signature: Data, publicKey: Data, newerThan current: String?) throws -> FilterConfig {
        guard config.count <= FilterConfig.maxBytes else { throw Failure.invalid(.tooLarge) }
        guard verifies(config, signature: signature, publicKey: publicKey) else { throw Failure.badSignature }

        let decoded: FilterConfig
        do {
            decoded = try FilterConfig.decode(config)
        } catch let error as FilterConfig.ValidationError {
            throw Failure.invalid(error)
        } catch {
            throw Failure.invalid(.malformed)
        }
        if let current, !decoded.revision.isNewer(than: current) { throw Failure.notNewer }
        return decoded
    }

    static func verifies(_ data: Data, signature encoded: Data, publicKey: Data) -> Bool {
        guard
            encoded.count <= 256,
            let text = String(data: encoded, encoding: .utf8),
            let signature = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        else { return false }
        return key.isValidSignature(signature, for: data)
    }
}

extension String {
    /// Revision order: digit runs compare as numbers, so `2026-09-29.10` is newer than `2026-09-29.9`.
    func isNewer(than other: String) -> Bool {
        compare(other, options: .numeric) == .orderedDescending
    }
}
