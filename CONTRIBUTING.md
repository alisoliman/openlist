# Contributing to Openlist

Bug reports and focused pull requests are welcome. For substantial changes,
open an issue first to discuss the user journey and scope.

## Build and check

Use macOS 26.5 or later and Xcode 26.5 or later (CI uses Xcode 26.6).
Clone the repository, then run:

```sh
./Tools/check.sh
./Tools/build-release.sh 0.1.0 1
```

This produces an unsigned Apple Silicon app in `build/release/DerivedData/Build/Products/Release/openlist.app`
without an Apple account. It verifies compilation and bundle metadata; use a
signed build to run the sandboxed app and widget reliably.

For development, open `openlist.xcodeproj`, select the `openlist` scheme and
choose your signing team for both targets. Forks should use their own bundle
IDs and matching App Group in `Shared/AppGroup.swift` and both entitlements.
The committed team and identifiers are public app identities, not credentials.

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
profile described in [release maintenance](docs/RELEASING.md). Compiling or
notarizing an app does not establish that its container or schema is usable.

Run `./Tools/check.sh` before submitting. Add regression checks when changing
logic, persistence, exports or editing behavior. For UI changes, exercise the
actual native app and explain what you verified. See `Tools/screenshot.sh` for
window-scoped capture. Keep fixtures separate from your personal lists.

Describe the problem, resulting behavior and validation in each PR. Keep changes
focused and avoid unrelated formatting. Contributions are licensed under the
repository's MIT license. Be respectful and constructive in discussions.
