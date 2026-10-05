# Contributing to Openlist

Bug reports and focused pull requests are welcome. For substantial changes,
open an issue first to discuss the user journey and scope.

## Build and check

Use macOS 27 or later and Xcode 27. CI and release builds run on GitHub's
`xcode-27` Apple Silicon image and select its latest Xcode, verifying that it is version 27. This image
currently provides a preview toolchain; each run logs the actual Xcode, Swift,
and host architecture. The app's minimum macOS target is 27.0.
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
The separate global voice shortcut is opt-in in every build, initially
Control-Shift-Option-Space, and can be changed in Settings. Review fixtures never
register either real global shortcut, even if their saved settings enable it.
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
widget; it reads the snapshot and only appends to the App Group command queue.

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
logic, persistence, exports or editing behaviour. For voice capture, also run
`./Tools/run-voice-audio-checks.sh`, which plays recordings through the real
speech model and Apple Intelligence (see [voice capture](docs/VOICE_CAPTURE.md)). For UI changes, exercise the
actual native app and explain what you verified. See `Tools/screenshot.sh` for
window-scoped capture. Keep fixtures separate from your personal lists.

Describe the problem, resulting behaviour and validation in each PR. Keep changes
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

### iPhone companion

The iOS 27 app `OpenlistiOS`, its widget extension `OpenlistiOSWidget` and
their test bundles (`OpenlistiOSTests`, Swift Testing, hosted by the app;
`OpenlistiOSUITests`, XCUITest) share the Mac project. The app is iPhone-only
and portrait, and syncs with the Mac through the same CloudKit container.

```sh
./Tools/run-ios-core-checks.sh   # part of check.sh: type-checks both iOS targets, no simulator
./Tools/run-ios-checks.sh        # unsigned build, unit and UI tests on a throwaway simulator
```

`run-ios-checks.sh` needs the iOS 27 simulator runtime
(`xcodebuild -downloadPlatform iOS`). It creates an iPhone 18 Pro simulator
(`OPENLIST_IOS_DEVICE_TYPE` picks another), deletes it afterwards, verifies the
built bundles and leaves its logs and `Tests.xcresult` in `build/ios`. CI runs it
as the separate `ios` job. It builds with `CODE_SIGNING_ALLOWED=NO` and an empty
`ICLOUD_CONTAINER_ENVIRONMENT`, so the app runs local-only.

The iPhone companion compiles the same Model, Store and service sources as
the Mac, listed in `Tools/iOS/shared-sources.txt`; its own replacements for
Mac-only pieces live in `OpenlistiOS/Platform/`. To share another file, add a
line there and run `python3 Tools/add-ios-targets.py`, which writes the list
into the project's exception sets; don't tick target membership in Xcode's File
inspector. `run-ios-core-checks.sh` fails while the project and the list
disagree, when a Mac UI file from `openlist/Next`, `Views` or `Editor` joins
iOS, or when a `Model` file is missing (both apps must build the same CloudKit
schema), then type-checks what the project compiles in Debug, Dev and Release.
Keep platform differences in shared files behind `#if os(macOS)` in place, and
never add iOS-only files to `openlist/` or `Shared/`: code the iOS app and
widget share goes in `SharediOS/`, which also holds the privacy manifest both
bundles carry. Logic both apps' screens need (Today's set, the Inbox queue, the
task query language, capture, list page rows, the phone's compact wording)
lives in UI-free shared files the Mac views call, not in the views;
`./Tools/run-shared-logic-checks.sh` covers it. Both devices read and write
`Block.richData`: after changing `RichTextCodec` or either platform's
`NXEditor`, run `./Tools/make-rich-text-fixtures.sh` (it needs the iOS 27
simulator runtime) and commit the regenerated
`Tools/RichTextParityChecks/Fixtures`, which
`./Tools/run-rich-text-parity-checks.sh` decodes on the Mac.

The **OpenlistiOS** scheme runs, tests and analyzes `Debug` and profiles and
archives `Release`. Its test action launches the host app in the review session
`HostedTests`, and every UI test starts the app with its own
`OpenlistReviewSession` launch variable (Debug builds only), so tests get an
isolated store, media and defaults, with iCloud and system notifications off.
**Openlist iOS Dev** uses `Dev` throughout: `solimanali.openlist.ios.dev`
("Openlist Dev"), the `group.solimanali.openlist.dev` App Group, the
`openlist-dev` URL scheme and no iCloud.

| | App | Widget |
|---|---|---|
| Debug, Release | `solimanali.openlist.ios` | `solimanali.openlist.ios.widget` |
| Dev | `solimanali.openlist.ios.dev` | `solimanali.openlist.ios.dev.widget` |

A review session's first launch seeds the library the iPhone mockups show
(`OpenlistiOS/Fixtures/PhoneFixture.swift`), never outside one. Debug builds
also read these launch variables in a review session, for UI tests and
screenshots (`xcrun simctl launch` passes them as `SIMCTL_CHILD_<name>`):

| Variable | Effect |
|---|---|
| `OpenlistFixtureNow` | Pins the app's clock (`AppClock`) to an ISO 8601 moment; `2026-09-23T10:40:00` is the mockups' |
| `OpenlistOpenRoute` | Opens a screen at launch: `today`, `timeline`, `inbox`, `lists`, `work`, `settings`, `trash`, `capture`, `voice` (Capture, listening), `working`, `triage`, `activity`, `find:#travel`, `list:<title>`, `task:<title>` |
| `OpenlistShowTray` | Shows its text in the tray, with Undo |
| `OpenlistCaptureText` | Types its text into the Capture sheet |
| `OpenlistVoiceRecording` | A recording's path, which voice capture listens to in place of the microphone (the Mac's Dev and Debug builds too) |
| `OpenlistVoiceFixture` | Offline voice UX fixture: shows Listening until Done/Return, then reads each newline-separated task without a microphone, permission prompt or model (Debug/Dev review sessions only) |
| `OpenlistComponentGallery=1` | Opens the design components' gallery (`OpenlistGalleryPage` 0–4 shows one part); Settings links to it too |

The app's code is in `OpenlistiOS/`: `App/` (entry, `PhoneEnvironment`,
navigation, the actions coordinator and tray), `Design/` (the `OL` components;
the colour tokens are in `SharediOS/OLTokens.swift` for the widget too),
`Features/<Feature>/`, `Platform/` and `Fixtures/`. Screens act on tasks through
`PhoneActions`, which keeps the Mac's completion dwell and Undo, and read the
time from `env.clock`, never `.now`.

Screens read the library from `\.phoneLibrary`, the Mac's `NextLibrary` built
once a render from the root's queries (`App/PhoneLibrary.swift`), and word rows
through `PhoneTaskRow`. What's worked on now (Today's Now card, Working, the
timeline's working block and the Live Activity) is `PhoneWork`, read from the
calendar coordinator. The widget extension draws Today, Inbox and Up next from
the published snapshot with the Mac widgets' model, and the work Live Activity
from `SharediOS/WorkActivity.swift`, which the app starts, updates and ends
(`App/PhoneLiveActivity.swift`); its buttons are the widgets' intents, run in
the app. A review session's calendar is a fixture holding the mockups' Design
sync meeting, and its Live Activity counts on the system clock. Review sessions
keep the widget snapshot out of the App Group, so placed widgets there show
their placeholder and the gallery its sample.

iOS App Groups carry the `group.` prefix, so the iPhone uses
`group.solimanali.openlist` where the Mac keeps its team-prefixed group; the two
never share files, only the CloudKit container `iCloud.solimanali.openlist`.
iOS Debug syncs with Mac Debug in the CloudKit Development environment, iOS
Release (TestFlight) with the notarized Mac Release in Production, and neither
Dev build syncs. Model changes therefore pass the
[production schema gate](#required-production-schema-gate) before either
platform ships. `ICLOUD_CONTAINER_ENVIRONMENT` fills both the iCloud
environment entitlement and the Info.plist key `OpenlistICloudEnvironment`,
which the app reads before it opens CloudKit, because iOS offers no API to read
the process's entitlements and an unentitled `CKContainer` crashes. Keep the
two driven by that one variable.

Signing is automatic with team `Y5UE64R7TQ`. Simulator builds sign to run
locally and need no provisioning profile. Device builds need explicit App IDs
for the app (iCloud with the CloudKit container, Push Notifications and App
Groups) and the widget (App Groups), and the `group.solimanali.openlist` group
registered on the team; Xcode, or `xcodebuild -allowProvisioningUpdates`, sets
these up for a developer allowed to change the team's identifiers. iOS uses the
`aps-environment` entitlement and `UIBackgroundModes: remote-notification`.
Give the widget the App Group only, never CloudKit or push. The iOS entitlements
(`Config/OpenlistiOS*.entitlements`) never go through
`Tools/prepare-release-signing.py`, which signs only the Mac app; iOS
distribution is not automated yet.

### App icon

The default app icon is `openlist/Openlist.icon`, an editable Icon Composer
document containing the checkmark and list SVG layers. Open it in Icon Composer
to adjust the artwork, background, and glass effects. Both Debug and Release
select `Openlist` as their app icon; Xcode compiles its default, dark, and mono
appearances. Local `Dev` selects `openlist/OpenlistDev.icon`, which reuses those
vector layers with a separate outlined **DEV** badge layer.

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
widget receives CloudKit or push entitlements.

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
   behaviour, and widget updates using disposable records. Follow
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
backup format 4 added cover assets and presentation; current exports use format 5
(see docs/LIBRARY_BACKUP.md) and formats 1–4 remain readable. Compilation and local
fixtures do not verify cloud delivery or the Production schema.

### Nested document persistence

Run `Tools/run-nested-list-checks.sh` for child document ownership, moves, inherited
archive, subtree copy/export, Trash restoration, late-sync retention, and the
exact pre-nesting nine-model private migration and cold Return matrix.
`TaskList.parentListID` is an additive CloudKit schema change covered by the
production schema gate above.
