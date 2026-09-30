import Foundation

/// Replaces identifying path segments (usernames, thread, reel and post ids) with a short token, so
/// logs can be pasted in chats. Tokens are a pure function of `salt` and the segment: the same
/// segment gets the same token all session long (reel A → reel B stays visible), and the JS
/// reimplementation in `recon.js` produces the same tokens for the same salt.
///
///     /reel/8f3kd/      → /reel/#3fa1/
///     /direct/t/1234/   → /direct/t/#91c0/
///     /stories/bob/99/  → /stories/#u7d2/#e02c/
///     /bob/reels/       → /@#4e2a/reels/
struct PathRedactor: Sendable {
    let salt: String

    init(salt: String = String(UInt32.random(in: .min ... .max))) {
        self.salt = salt
    }

    func redact(_ path: String) -> String {
        // Only a pathname is expected; anything after `?` or `#` could carry tokens.
        let pathOnly = path.prefix { $0 != "?" && $0 != "#" }
        let segments = pathOnly.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        var out: [String] = [""]
        for (index, segment) in segments.enumerated() {
            let text = String(segment)
            if text.isEmpty {
                out.append("")
            } else if index == 0 {
                out.append(ReservedSegments.firstSegments.contains(text.lowercased()) ? text : "@" + token(for: text))
            } else {
                out.append(ReservedSegments.knownSubsegments.contains(text.lowercased()) ? text : token(for: text))
            }
        }
        return out.joined(separator: "/")
    }

    /// `#` + 4 hex digits: FNV-1a (32 bit) over `salt`, a zero byte and the segment, folded to 16 bits.
    func token(for segment: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in salt.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        hash = (hash ^ 0) &* 16_777_619
        for byte in segment.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return String(format: "#%04x", (hash ^ (hash >> 16)) & 0xFFFF)
    }
}
