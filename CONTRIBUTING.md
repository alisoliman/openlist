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

Run `./Tools/check.sh` before submitting. Add regression checks when changing
logic, persistence, exports or editing behavior. For UI changes, exercise the
actual native app and explain what you verified. See `Tools/screenshot.sh` for
window-scoped capture. Keep fixtures separate from your personal lists.

Describe the problem, resulting behavior and validation in each PR. Keep changes
focused and avoid unrelated formatting. Contributions are licensed under the
repository's MIT license. Be respectful and constructive in discussions.
