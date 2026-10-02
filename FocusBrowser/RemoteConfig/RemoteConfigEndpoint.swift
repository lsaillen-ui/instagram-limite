import Foundation

/// Where the public filter config lives and which key signs it.
enum RemoteConfigEndpoint {
    /// Root of the GitHub Pages site: serves `config.json` and `config.json.sig`, published from
    /// `remote-config/` by `.github/workflows/pages.yml`.
    static let baseURL = URL(string: "https://lsaillen-ui.github.io/instagram-limite/")!

    /// Ed25519 public key (base64, 32 bytes) matching `~/.focusbrowser/signing.key`
    /// (`swift remote-config/sign.swift public`). The private key never goes in the repo.
    static let publicKey = Data(base64Encoded: "0a452oDoWQG8/KHPHA1ijVgYihzReI6olpfwDhLifE4=")!
}
