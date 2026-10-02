// Signs remote-config/config.json with the Ed25519 private key kept OUTSIDE the repo.
//
//   swift remote-config/sign.swift keygen   create ~/.focusbrowser/signing.key (refuses to overwrite)
//   swift remote-config/sign.swift public   print the public key (base64) to paste in RemoteConfigEndpoint.swift
//   swift remote-config/sign.swift sign     write config.json.sig for the current config.json
//
// The key file holds the base64 of the 32-byte private key. Never commit it, never print it.
import CryptoKit
import Foundation

let keyURL = URL(fileURLWithPath: ("~/.focusbrowser/signing.key" as NSString).expandingTildeInPath)
let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let configURL = directory.appendingPathComponent("config.json")
let signatureURL = directory.appendingPathComponent("config.json.sig")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadKey() -> Curve25519.Signing.PrivateKey {
    guard
        let text = try? String(contentsOf: keyURL, encoding: .utf8),
        let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
        let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("Cannot read a valid key at \(keyURL.path). Run `keygen` first.") }
    return key
}

switch CommandLine.arguments.dropFirst().first {
case "keygen":
    if FileManager.default.fileExists(atPath: keyURL.path) { fail("\(keyURL.path) already exists, not overwriting.") }
    let key = Curve25519.Signing.PrivateKey()
    do {
        try FileManager.default.createDirectory(
            at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data((key.rawRepresentation.base64EncodedString() + "\n").utf8).write(to: keyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
    } catch {
        fail("Could not write the key: \(error)")
    }
    print("Key created at \(keyURL.path)")
    print("Public key: \(key.publicKey.rawRepresentation.base64EncodedString())")

case "public":
    print(loadKey().publicKey.rawRepresentation.base64EncodedString())

case "sign":
    guard let config = try? Data(contentsOf: configURL) else { fail("Cannot read \(configURL.path)") }
    let key = loadKey()
    guard let signature = try? key.signature(for: config) else { fail("Signing failed") }
    guard key.publicKey.isValidSignature(signature, for: config) else { fail("Self-check failed") }
    do {
        try Data((signature.base64EncodedString() + "\n").utf8).write(to: signatureURL, options: .atomic)
    } catch {
        fail("Could not write \(signatureURL.path): \(error)")
    }
    print("Signed \(configURL.lastPathComponent) -> \(signatureURL.lastPathComponent)")

default:
    fail("Usage: swift remote-config/sign.swift keygen | public | sign")
}
