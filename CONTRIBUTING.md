# Contributing to Openlist

Bug reports and focused pull requests are welcome. For substantial changes,
open an issue first to discuss the user journey and scope.

## Build and check

Use macOS 26.5 or later and Xcode 27. CI and release builds run on GitHub's
`xcode-27` Apple Silicon image and select its latest Xcode, verifying that it is version 27. This image
currently provides a preview toolchain; each run logs the actual Xcode, Swift,
and host architecture. The app's minimum macOS target remains 26.5.
Clone the repository, then run:

```sh
./Tools/check.sh
./Tools/build-release.sh 0.1.0 1
```

This produces an unsigned Apple Silicon app in `build/release/DerivedData/Build/Products/Release/openlist.app`
without an Apple account. It verifies compilation and bundle metadata; use a
signed build to run the sandboxed app and widget reliably.

For local development, run:

```sh
./Tools/build-dev.sh --open
```

This builds **Openlist Dev.app**, with an orange **DEV** badge, bundle identifier
`solimanali.openlist.dev`, and a separate `openlist-dev` executable. Production
Openlist can stay installed and running. The script builds and ad-hoc signs
without Apple credentials, then verifies the app, widget, helper, icon,
entitlements, and storage isolation. The app is at
`build/dev/DerivedData/Build/Products/Dev/Openlist Dev.app`; later launches can use
`open "build/dev/DerivedData/Build/Products/Dev/Openlist Dev.app"`.

Xcode's **Openlist Dev** scheme uses the same `Dev` configuration. The existing
`openlist` scheme also uses `Dev` for Run, Test, and Analyze; its Profile and
Archive actions retain `Release`. Both development routes use separate
preferences and local data, and disable iCloud. They do not seed disposable
review fixtures or import production tasks. Ad-hoc Dev data lives in its private
sandbox under `Library/Application Support/Openlist Dev`, with `Store` and
`Openlist/Media` subdirectories. Its preferences suite is
`solimanali.openlist.dev`; its MCP Keychain identity is also separate. MCP stays
off initially; enabling it uses port **45874** and the client configuration key
`openlist-dev`, leaving production's **45873** / `openlist` entry separate.
Development's global quick-capture shortcut is off initially so opening Dev
does not take production's shortcut. You can enable it in Dev settings.
`OPENLIST_DEV_CHECKS=1 ./Tools/run-mcp-checks.sh` verifies the development MCP
defaults and exported client names through the actual local listener and helper.

To exercise the development widget with shared data, choose your signing team
in Xcode or use `./Tools/build-dev.sh --signed --open`. These signed builds use
the distinct `Y5UE64R7TQ.solimanali.openlist.dev` App Group. Credential-free
ad-hoc builds omit App Group entitlements and keep widget data private to its
own process; they cannot share the app's task snapshot. Neither route touches
the production App Group. The signed group and private sandbox are separate
development stores; changing signing modes does not migrate data between them.

The explicit `Debug` configuration remains available for provisioned iCloud
integration work described below. It retains the production identity, so use
isolated review fixtures for that work. Forks should use their own bundle IDs,
signing team, and matching App Groups in `Shared/AppGroup.swift` and the
production/development entitlements. Committed identifiers are public app
identities, not credentials.

### Developing iCloud sync

The main app needs the iCloud/CloudKit and Push Notifications capabilities, an
associated `iCloud.solimanali.openlist` container, and an authorized development
provisioning profile. Xcode can update development provisioning when the signed-in
developer has permission (`xcodebuild -allowProvisioningUpdates`). Forks must
also change the container identifier in `Config/openlist.entitlements` and
`openlist/Services/ICloudConfiguration.swift`. Do not add CloudKit to the
snapshot-only widget.

Debug signatures select CloudKit `Development` and APNs `development`; Release
signatures select `Production` and `production`. Native macOS uses the
`com.apple.developer.aps-environment` entitlement, not iOS's `aps-environment`
or `UIBackgroundModes`. Unsigned builds and `OpenlistReviewSession` fixtures
always disable CloudKit, even on a Mac signed in to iCloud.

Run `./Tools/run-sync-checks.sh` for offline migration and synchronization
regressions. For real service verification, use
`Tools/run-cloud-sync-checks.sh /path/to/Debug/openlist.app --account-only`,
then `--connection`, `--initialize-schema` and `--run`. These commands require a matching
development signing identity in the Keychain, use only synthetic data and
temporary stores, and refuse Production. If a live check cannot confirm cloud
cleanup, it reports the synthetic IDs and retains its isolated databases for
diagnosis. Once connectivity returns, `--cleanup /path/to/OpenlistCloudCheck-UUID`
removes only that fixture and verifies its cloud deletion; do not reset the
user's cloud database.

Before publishing, initialize the complete development schema, deploy it to
Production in CloudKit Console, and configure the Developer ID provisioning
profile described in [release maintenance](#releases). Compiling or
notarizing an app does not establish that its container or schema is usable.

Run `./Tools/check.sh` before submitting. Add regression checks when changing
logic, persistence, exports or editing behavior. For UI changes, exercise the
actual native app and explain what you verified. See `Tools/screenshot.sh` for
window-scoped capture. Keep fixtures separate from your personal lists.

Describe the problem, resulting behavior and validation in each PR. Keep changes
focused and avoid unrelated formatting. Contributions are licensed under the
repository's MIT license. Be respectful and constructive in discussions.

The app links the local `OpenlistMCP` Swift package; Xcode and the check scripts
resolve its pinned dependencies automatically. Keep `Package.resolved` and the
Xcode workspace's package resolution consistent. For MCP changes, run
`./Tools/run-mcp-checks.sh` and `./Tools/run-mcp-helper-checks.sh`.
After dependency updates, refresh bundled license notices using
`./Tools/update-mcp-notices.sh .build/checkouts`. See the
[README](README.md#ai-clients-through-mcp) for MCP setup and privacy details.
`OPENLIST_SWIFT_BUILD_SYSTEM=native ./Tools/run-mcp-checks.sh` also exercises
the classic SwiftPM backend used by older supported toolchains. To check the
actual release launcher, set `OPENLIST_MCP_HELPER` to its absolute bundle path
when running that script.

Release-verifier regressions run through the script's own shebang, macOS's
`/bin/bash`, and any distinct Bash installed on `PATH`. Keep release gates
explicitly fail-closed: do not rely on `set -e` to reject metadata mismatches,
especially when a `[[ ... ]]` condition contains command substitution.

### App icon

The default app icon is `openlist/Openlist.icon`, an editable Icon Composer
document containing the checkmark and list SVG layers. Open it in Icon Composer
to adjust the artwork, background, and glass effects. Both Debug and Release
select `Openlist` as their app icon; Xcode compiles its default, dark, and mono
appearances. Local `Dev` selects `openlist/OpenlistDev.icon`, which reuses those
vector layers with a separate outlined **DEV** badge layer. The older
`AppIcon.appiconset` and `Tools/generate-app-icon.swift`
are legacy artwork and do not control the default icon.

## Releases

Release binaries and notes belong on
[GitHub Releases](https://github.com/alisoliman/openlist/releases), not in the
repository. The release workflow publishes `vX.Y.Z` tags whose commits are on
`main`, after checks, signing and notarization. Notes are generated by GitHub
and can be edited on the release page.

Required signing and notarization secrets are named in
`.github/workflows/release.yml`. Keep their values and local signing material
outside source control.

### iCloud distribution provisioning

The app's CloudKit and push capabilities require an original Apple-issued
**Developer ID** provisioning profile for team `Y5UE64R7TQ` and the explicit
macOS App ID `solimanali.openlist`. Use its actual App ID prefix, which may
differ from the Team ID. Associate `iCloud.solimanali.openlist` with that App ID,
enable CloudKit and Push Notifications, and select the Developer ID Application
certificate used for release signing when generating the profile.

The profile must authorize that container, `CloudKit`, the `Production` iCloud
environment, and native macOS
`com.apple.developer.aps-environment=production`. Development, ad hoc, Mac App
Store, and wildcard profiles are not valid substitutes. Regenerate the profile
after changing capabilities, container associations, or signing certificates,
and replace it before expiry.

Store the original `.provisionprofile` as the base64-encoded
`MACOS_APP_PROVISION_PROFILE_BASE64` Actions secret. Local packaging uses its
private path in `APP_PROVISION_PROFILE`. Never commit the original or decoded
profile, signing keys, resolved signing artifacts, or access tokens.

`Tools/prepare-release-signing.py` validates the profile's App ID/prefix, team,
validity, macOS all-devices distribution properties, and capabilities. It embeds
the original profile and resolves the source environment placeholders into a
separate production entitlements file. After signing, it verifies the app's
extracted entitlements and public signing certificate against the profile.
This is a preflight, not a replacement for Apple's profile trust, signature,
notarization, or runtime checks.

The existing App Group and sandbox permissions are retained, including the
network server permission needed by opt-in localhost MCP access. The native MCP
launcher is signed before the widget and app. Neither the launcher nor the
snapshot-only widget receives CloudKit or push entitlements.

See Apple's [supported macOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-macos)
and [TN3125: Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles).

### Required production schema gate

Before the first iCloud release and after each model/schema change:

1. Build and provision a development-signed app with the current model. Run the
   opt-in `--account-only`, `--connection`, `--initialize-schema`, and `--run`
   modes of `Tools/run-cloud-sync-checks.sh` described above. The initializer
   uses the complete SwiftData model; account access or a single record type
   is not evidence of schema readiness. Stop on errors or missing fixture
   cleanup confirmation. Use `--resume` or `--cleanup` with the reported
   diagnostic directory when needed. Low battery can postpone native transfers
   even while charging, so allow battery recovery on AC power.
2. Review all record types, fields, and required indexes in CloudKit Console
   and [deploy the development schema to Production](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).
   Schema deployment does not copy development records into Production.
3. Test a correctly profiled Release build on two physical Macs signed into the
   same Apple Account. Verify creation, edits, deletion, media, offline/reconnect
   behavior, and widget updates using disposable records. Follow
   [TN3164's synchronization diagnostics](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer)
   for native import/export failures.

Record completion in the release checklist. CI does not register Apple
resources, deploy schemas, or access cloud accounts. Offline tests and a
development-container round trip do not verify Production readiness or
cross-device push delivery. Never initialize the schema in a production build.

### Local release packaging

```sh
./Tools/check.sh
./Tools/build-release.sh 0.1.0 1
SIGNING_IDENTITY='Developer ID Application: Ali Soliman (Y5UE64R7TQ)' \
APP_PROVISION_PROFILE='/path/to/private/Openlist-DeveloperID.provisionprofile' \
NOTARY_PROFILE='your-notarytool-profile' \
  ./Tools/package-release.sh 0.1.0 1
```

Alternatively, provide `NOTARY_KEY_PATH`, `NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID`.
Packaging validates the app, widget, native helper, and notices; signs the
components; notarizes and staples the app and DMG; and verifies Gatekeeper
acceptance before generating downloadable packages and checksums.
Downloads are written to `dist/`, with intermediate files under `build/release/`.
Forks must update the identity-policy constants in
`Tools/prepare-release-signing.py` as well as their app identifiers and entitlements.

Run `./Tools/run-signing-checks.sh` for the focused offline signing fixtures.
They use synthetic profiles and certificate bytes with mocked CMS decoding,
never a Keychain or real signing material. Check a fresh extraction with
`codesign --verify --deep --strict`, `xcrun stapler validate`, and
`spctl --assess --type execute` before launch.

### Trash persistence

Run `Tools/run-trash-checks.sh` for deletion/restart/restore, independent subtree
ownership, Undo, shared media erasure, and injected and actual read-only save
failures. Its migration matrix uses the persisted pre-Trash Block/TaskList
schema and verifies private-copy restore plus cold Return without changing the
retained original. `Tools/run-inbox-checks.sh` retains the pre-membership matrix.
Trash adds optional `trashID` and `trashMetadataData` to Block and TaskList;
these are CloudKit schema changes subject to the production schema gate above.
Local tests and ad-hoc Dev builds do not verify cloud delivery or Production.

### List covers

`Tools/run-list-cover-checks.sh` exercises bounded local image import, independent
list/template copy ownership, Markdown assets, Trash recovery, cold relaunch, and
injected plus actual read-only save failures. It also runs the persisted pre-cover
nine-model migration matrix: restore reads a private copy and a later Return
preserves the retained original database, WAL, and external payload bytes.

List covers add optional `coverFilename`, externally stored `coverData`,
`coverMetadataData`, and `coverPresentationRaw` fields to TaskList. These are
CloudKit schema changes subject to the production schema gate above. Logical
backup format 4 includes cover assets and presentation; formats 1, 2, and 3 remain
readable. Compilation and local fixtures do not verify cloud delivery or the
Production schema.
