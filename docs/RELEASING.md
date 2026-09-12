# Releasing Openlist

Official releases target Apple Silicon (`arm64`) and macOS 26.5 or later.
GitHub's `macos-26` runner uses Xcode 26.6, explicitly selected by both workflows.
The app and widget retain their production bundle IDs and shared App Group.

## One-time repository setup

In repository Settings → Secrets and variables → Actions, configure:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded export of the Developer ID Application certificate and its private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting that P12 |
| `NOTARY_API_KEY_BASE64` | Base64-encoded App Store Connect team API private key (`.p8`) |
| `NOTARY_KEY_ID` | API key ID |
| `NOTARY_ISSUER_ID` | API issuer ID |

Use a dedicated API key with the Developer role. Never commit signing material.
The release job imports the certificate into a temporary Keychain and removes
credentials at the end of the job. Pull-request CI does not access secrets.
The signing identity is `Developer ID Application: Ali Soliman (Y5UE64R7TQ)`;
forks must change it and configure their own app identifiers and entitlements.

## Publish

1. Merge and verify CI on `main`.
2. Add `docs/releases/X.Y.Z.md` describing changes and requirements. Merge it first.
3. From the verified main commit, create and push a version tag:

   ```sh
   git tag -a vX.Y.Z -m 'Openlist X.Y.Z'
   git push origin vX.Y.Z
   ```

The release workflow only accepts `vX.Y.Z` tags whose commit is on `main`.
It runs every regression suite, builds Release for arm64, verifies both bundles'
versions, architectures and minimum OS, signs the extension then app with hardened
runtime, and waits for Apple notarization. It staples the app ticket, verifies
Gatekeeper acceptance, packages ZIP and DMG downloads, notarizes/staples the DMG,
and generates SHA-256 checksums. Only then does it create and publish a release.

Version comes from the tag and build number from the Actions run number.
Any build, check, signing, notarization or packaging failure prevents publication.
Build and notarization logs are retained as Actions artifacts.

If a job fails before creating the draft, fix the cause and rerun it. If a draft
was already created, inspect its assets before publishing or delete only that
unpublished draft before rerunning. Never move a published version tag or replace
published assets; issue a new patch release instead.

## Local verification

```sh
./Tools/check.sh
./Tools/build-release.sh 0.1.0 1
SIGNING_IDENTITY='Developer ID Application: Ali Soliman (Y5UE64R7TQ)' \
NOTARY_PROFILE='your-notarytool-profile' \
  ./Tools/package-release.sh 0.1.0 1
```

Alternatively set `NOTARY_KEY_PATH`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID`.
Downloads appear in `dist/`; intermediates and logs are under `build/release/`.
Check a fresh extraction with `codesign --verify --deep --strict`,
`xcrun stapler validate`, and `spctl --assess --type execute` before launch.
Test opening the app and widget on a Mac; compilation and notarization alone do
not establish that every native user journey works.
