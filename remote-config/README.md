# remote-config

The public filter config, served by GitHub Pages. Data only: selectors, route patterns, locale strings.

- `config.json`: the config (same schema as `FocusBrowser/Resources/filters.default.json`).
- `config.json.sig`: base64 Ed25519 signature over the exact bytes of `config.json`.
- `sign.swift`: key generation and signing. The private key lives in `~/.focusbrowser/signing.key` and never goes in the repo.

## Publish a change

1. Edit `config.json`. Bump `revision` (`YYYY-MM-DD.N`); the app ignores a revision that is not strictly newer.
2. `swift remote-config/sign.swift sign`
3. Run the tests (`SignedConfigTests` checks the file against the key bundled in the app).
4. Commit `config.json` and `config.json.sig` together and push. Pages serves them within a few minutes.

Re-signing after any edit is mandatory, even a whitespace change: the signature covers the exact bytes.

## Rotate the key

The public key is compiled into the app (`RemoteConfigEndpoint.publicKey`), so a new key needs an app release. Keep the old key until the release is out.
