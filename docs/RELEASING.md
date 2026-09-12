# Releasing Openlist

Official releases target Apple Silicon (`arm64`) and macOS 26.5 or later.
GitHub's `macos-26` runner uses Xcode 26.6, explicitly selected by both workflows.
The app and widget retain their production bundle IDs and shared App Group.
The app's CloudKit and push entitlements require an Apple-issued Developer ID
provisioning profile; an unsigned build followed by unprofiled `codesign` is not
a valid iCloud release. The widget reads shared snapshots only and keeps its
existing signing entitlements, without CloudKit or push capabilities.

## One-time Apple Developer setup

An authorized maintainer must complete these steps in Certificates, Identifiers
& Profiles for team `Y5UE64R7TQ`:

1. Use the explicit macOS App ID for bundle ID `solimanali.openlist`, not a
   wildcard. Retain its actual App ID prefix; older prefixes can differ from
   the Team ID.
2. Register `iCloud.solimanali.openlist`, associate it with that App ID, and
   enable iCloud/CloudKit and Push Notifications. Keep the existing
   `Y5UE64R7TQ.solimanali.openlist` macOS App Group on the app and widget.
3. Generate a **Developer ID** distribution provisioning profile for that App ID,
   selecting the **Developer ID Application** certificate used for releases.
   Do not use a development, ad hoc, or Mac App Store profile. Download the
   original `.provisionprofile`, not a decoded plist.
4. Confirm the profile authorizes the intended container, `CloudKit`,
   `Production` iCloud, and native macOS
   `com.apple.developer.aps-environment=production`. Store it as the CI secret
   below and keep any local copy private and outside source control.

Regenerate the profile after changing capabilities, container associations, or
the signing certificate, and replace it before it expires. The helper checks
the profile's authorized App ID/prefix, team, expiry, macOS all-devices
distribution properties, capabilities, and the signed app's public leaf
certificate against `DeveloperCertificates`. It never reads or exports private
keys. It claims only reviewed app entitlements, not every grant in the profile.
App Sandbox and the existing team-prefixed macOS App Group are retained; those
are unrestricted macOS entitlements, not additional CloudKit grants.

See Apple's [supported macOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-macos),
[Developer ID overview](https://developer.apple.com/developer-id/), and
[TN3125: Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles).
Profile parsing is a release preflight, not a replacement for Apple's signature,
profile trust, notarization, or runtime checks; Apple can change profile formats.

## One-time repository setup

In repository Settings → Secrets and variables → Actions, configure:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded export of the Developer ID Application certificate and its private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting that P12 |
| `MACOS_APP_PROVISION_PROFILE_BASE64` | Base64 encoding of the original Developer ID app `.provisionprofile` authorizing CloudKit and production push |
| `NOTARY_API_KEY_BASE64` | Base64-encoded App Store Connect team API private key (`.p8`) |
| `NOTARY_KEY_ID` | API key ID |
| `NOTARY_ISSUER_ID` | API issuer ID |

Use a dedicated API key with the Developer role. Never commit signing material.
The release job imports the certificate into a temporary Keychain, writes the
profile under `RUNNER_TEMP` with a restrictive `umask`, and removes its named
credential/profile files at the end of the job. Do not print profile contents or
upload decoded profiles, certificates, or signing scratch files as CI artifacts.
Pull-request CI does not access secrets.
The signing identity is `Developer ID Application: Ali Soliman (Y5UE64R7TQ)`;
forks must change it and configure their own app identifiers, entitlements, and
the identity-policy constants in `Tools/prepare-release-signing.py`.

## Maintainer credentials on this Mac

The local backup lives outside the repository at
`~/.config/openlist/release/AuthKey_<KEY_ID>.p8`. The directory is readable only
by its owner, and the key file has mode `600`. A neighboring `config.json` records
the key ID, issuer ID, key path, repository and Keychain profile name; it contains
no private-key contents. Keep this directory out of source control.

The validated macOS Keychain profile is `openlist-notary`. Use it for local
notarization with `NOTARY_PROFILE=openlist-notary`. GitHub-hosted runners use the
encrypted Actions secrets above and do not depend on this Mac being online.
When rotating the API key, update both the local Keychain profile and GitHub's
`NOTARY_API_KEY_BASE64` / `NOTARY_KEY_ID` secrets.

## Required manual gate: production CloudKit schema

**Before the first iCloud release, and after every model/schema change, an
authorized maintainer must initialize and deploy the CloudKit schema.** Adding
entitlements, generating a provisioning profile, or notarizing the app does not
perform this step.

1. Build and provision a development-signed app with the current model and the
   container's **Development** environment. Connect the Mac to AC power so
   battery can recover from a low level; discretionary transfers may remain
   deferred while charging. Use the
   existing development-only helper rather than writing a separate initializer:

   ```sh
   DEVELOPMENT_SIGNED_APP='/path/to/development-signed/openlist.app'
   ./Tools/run-cloud-sync-checks.sh "$DEVELOPMENT_SIGNED_APP" --account-only &&
     ./Tools/run-cloud-sync-checks.sh "$DEVELOPMENT_SIGNED_APP" --connection &&
     ./Tools/run-cloud-sync-checks.sh "$DEVELOPMENT_SIGNED_APP" --initialize-schema &&
     ./Tools/run-cloud-sync-checks.sh "$DEVELOPMENT_SIGNED_APP" --run
   ```

   The helper reuses the app's matching development identity and provisioning
   profile and refuses Production. `--account-only` checks account access;
   `--connection` performs an authenticated, read-only CloudKit service request;
   `--initialize-schema` follows [SwiftData's schema setup instructions](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
   using `NSManagedObjectModel.makeManagedObjectModel` and
   `NSPersistentCloudKitContainer`'s schema initializer, unloading the stack
   before another stack opens. `--run` performs the live synthetic-data checks.
   The helper uses temporary local stores and synthetic UUID records and confirms
   cleanup; it does not use a maintainer's personal database.
   These are opt-in live iCloud operations, not offline signing tests.

   Stop on any error or missing cleanup confirmation. Ensure every model,
   relationship, asset field, and required index is represented before deploying.
   Account access alone, or saving one kind of record, does not establish that
   the schema is ready. Do not put schema initialization in a production build.
   If a failed run retains a diagnostic directory, use
   `--resume /path/to/OpenlistCloudCheck-UUID` to continue its recorded phases,
   or `--cleanup /path/to/OpenlistCloudCheck-UUID` to abandon the check safely.
   Cleanup reads only record identifiers and removes only that run's fixture.
2. In CloudKit Console, review `iCloud.solimanali.openlist` and
   [deploy its development schema to Production](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
   Verify the expected record types, fields, and indexes in Production.
   Schema deployment does not copy development records into production.
3. Before publishing a tag, test a correctly profiled Release build against
   Production on two Macs signed into the same iCloud account. Check create,
   edit, delete, media transfer, offline/reconnect behavior, and widget snapshot
   updates. Use disposable records, not a maintainer's personal database.
   Follow [TN3164's CloudKit synchronization diagnostics](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer)
   if import/export events fail.

Record completion in the release checklist. CI cannot establish that the live
production schema is ready or that cross-device synchronization works; it does
not register Apple resources, deploy schemas, or run cloud-account tests.
Offline signing tests alone do **not** verify distribution or live sync.

Current validation status (2026-09-12): development signing/provisioning with
`xcodebuild -allowProvisioningUpdates`, the unsigned Release build, and offline
checks succeeded. The helper's `--account-only` check and authenticated CloudKit
zone reads and complete development schema initialization also succeeded.
The native development-container round-trip passed using independent persistent
stores in separate app processes: existing offline records uploaded, the second
store downloaded both exact 2 MiB assets, its edit and completion reached iCloud
and the original store, and native deletion propagated back to the second store.
Cloud fixture deletion was verified and isolated local stores were removed.

Initial checks exposed macOS battery scheduling rather than a migration failure:
`nsurlsessiond` treated Core Data requests as discretionary and `dasd` assigned a
zero Battery Level Policy score at 14-16%, including while charging. The checks
completed after battery recovery on AC power. The diagnostic now checkpoints
phases and allows ten minutes per transfer for native retries.

This verifies development-container data replication, not production deployment
or real-time push delivery between two physical Macs. The Production schema,
Developer ID distribution profile, and two-Mac Release checks above remain
release gates; development-account success does not satisfy them.

## Publish

1. Merge and verify CI on `main`; complete the production CloudKit gate above.
2. Add `docs/releases/X.Y.Z.md` describing changes and requirements. Merge it first.
3. From the verified main commit, create and push a version tag:

   ```sh
   git tag -a vX.Y.Z -m 'Openlist X.Y.Z'
   git push origin vX.Y.Z
   ```

The release workflow only accepts `vX.Y.Z` tags whose commit is on `main`.
It runs every regression suite, builds Release for arm64, verifies both bundles'
versions, architectures and minimum OS, validates the required Developer ID app
profile, and embeds the **original** profile at
`openlist.app/Contents/embedded.provisionprofile` before signing. The helper
resolves the two source build placeholders to `Production`/`production` and adds
the profile-authorized native macOS App ID and team to a separate release
entitlements file. Raw `codesign` does not expand Xcode build variables.

The workflow signs the extension with its unchanged entitlements, then the app
with the prepared entitlements and hardened runtime. Before contacting the
notary service, it checks the extracted signed entitlements and confirms the
public signing certificate is allowed by the embedded profile. Missing, expired,
wrong-team/app/container, development-only, unsafe, or unresolved configuration
fails closed; there is no local-only release fallback.

It waits for Apple notarization, staples the app ticket, verifies
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
./Tools/run-signing-checks.sh  # focused, Python-stdlib-only offline fixtures
./Tools/build-release.sh 0.1.0 1
SIGNING_IDENTITY='Developer ID Application: Ali Soliman (Y5UE64R7TQ)' \
APP_PROVISION_PROFILE='/path/to/private/Openlist-DeveloperID.provisionprofile' \
NOTARY_PROFILE='your-notarytool-profile' \
  ./Tools/package-release.sh 0.1.0 1
```

Alternatively set `NOTARY_KEY_PATH`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID`.
Downloads appear in `dist/`; intermediates and logs are under `build/release/`.
Resolved entitlements and extracted public certificates are under
`build/release/signing/` and must not be committed or uploaded as CI logs.
The offline signing suite generates fresh synthetic profiles and certificate
bytes, mocks CMS decoding, and never accesses a Keychain or real signing
material. It is a preflight regression check, not cryptographic validation.
Check a fresh extraction with `codesign --verify --deep --strict`,
`xcrun stapler validate`, and `spctl --assess --type execute` before launch.
Test opening the app and widget on a Mac; compilation and notarization alone do
not establish that every native user journey works.
