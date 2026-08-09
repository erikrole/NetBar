# Releasing NetBar

NetBar is distributed directly as a signed and notarized Apple Silicon ZIP
attached to a GitHub Release. Homebrew is deferred until the release cadence is
stable.

## Prerequisites

- Apple Developer Program membership.
- A **Developer ID Application** certificate and private key in the local
  keychain or in the release workflow's imported keychain.
- An App Store Connect API key authorized to submit notarization requests, or a
  local `notarytool` keychain profile.
- Xcode and XcodeGen.

## Local release

```sh
TEAM_ID="YOUR_TEAM_ID" \
NOTARY_KEY_ID="YOUR_KEY_ID" \
NOTARY_ISSUER_ID="YOUR_ISSUER_ID" \
NOTARY_PRIVATE_KEY_PATH="/path/to/AuthKey_KEYID.p8" \
./scripts/release-macos.sh
```

The script generates a Release archive, exports Developer ID-signed
`NetBar.app`, submits a ZIP to Apple's notary service, staples the ticket, and
writes `.release/NetBar-0.1.0-arm64.zip` plus a portable SHA-256 checksum.

## GitHub release

The release workflow runs when a `v*` tag is pushed. It expects these GitHub
Actions secrets:

- `APPLE_TEAM_ID`
- `DEVELOPER_ID_CERTIFICATE_P12` (base64-encoded certificate and private key)
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `NOTARY_KEY_ID`
- `NOTARY_ISSUER_ID`
- `NOTARY_PRIVATE_KEY` (base64-encoded `.p8` key)

After the secrets are configured:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Do not commit certificates, private keys, provisioning assets, or notarization
credentials.
