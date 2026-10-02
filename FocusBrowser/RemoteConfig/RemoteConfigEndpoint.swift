import Foundation

/// Where the public filter config lives and which key signs it.
enum RemoteConfigEndpoint {
    /// Folder served by GitHub Pages (`remote-config/` of the config repo): holds `config.json` and
    /// `config.json.sig`. The `.invalid` host never resolves: replace it with the real Pages URL.
    static let baseURL = URL(string: "https://REPLACE-ME.invalid/")!

    /// Ed25519 public key (base64, 32 bytes) matching `~/.focusbrowser/signing.key`
    /// (`swift remote-config/sign.swift public`). The private key never goes in the repo.
    static let publicKey = Data(base64Encoded: "0a452oDoWQG8/KHPHA1ijVgYihzReI6olpfwDhLifE4=")!
}
