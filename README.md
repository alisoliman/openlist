# Openlist

An open-source, local-first task and notes app for macOS, built with SwiftUI and
SwiftData. Combine tasks and rich notes in documents, capture ideas from any app,
and plan your day with a calendar and desktop widgets.

## Features

- **Tasks and notes together:** rich documents with headings, nested tasks,
  images, attachments, and child lists.
- **Task planning:** due dates, reminders, repeating tasks, labels, priorities,
  and reusable templates.
- **Quick capture:** a global shortcut, menu bar access, and natural-language
  dates such as “tomorrow at 6pm.”
- **Daily organization:** Inbox, Today, search, and a calendar with time blocking
  and work sessions.
- **Desktop widgets:** tasks, quick capture, agenda, progress, and activity.
- **Your data:** offline access, private iCloud sync in enabled builds, Markdown
  export, library backups, and restorable Trash.
- **AI integration:** an optional local MCP server for compatible clients.

An iPhone companion is included in the project and syncs through the same iCloud
container.

## Download

Get the **Apple Silicon (arm64)** DMG or ZIP from
[GitHub Releases](https://github.com/alisoliman/openlist/releases/latest).
Requires an **Apple Silicon Mac (M1 or newer) running macOS 27 or later**.

Drag `openlist.app` to Applications and launch it before adding widgets.
Official releases are Developer ID signed and notarized by Apple. Downloads
include `SHA256SUMS.txt` for checksum verification.

Openlist stores your data on your Mac and works offline. iCloud-enabled builds
sync through your Apple Account; no separate Openlist account is required.

## Build from source

Requires **macOS 27 or later and Xcode 27**.

```sh
git clone https://github.com/alisoliman/openlist.git
cd openlist
./Tools/build-dev.sh --open
```

This builds and opens **Openlist Dev**, using separate local data and preferences
with iCloud disabled. No Apple developer credentials are required. To work in
Xcode, open `openlist.xcodeproj` and select the **Openlist Dev** scheme.

Run the project checks:

```sh
./Tools/check.sh
```

For the iPhone companion, use the **OpenlistiOS** scheme or run
`./Tools/run-ios-checks.sh` to build and test on an iOS 27 simulator.

See [CONTRIBUTING.md](CONTRIBUTING.md) for signing, widget development, iCloud
setup, and release builds.

## AI clients through MCP

Enable **Settings → AI Agents**, copy the configuration for your client, and keep
Openlist running. The bundled server supports stdio and Streamable HTTP; no
additional runtime is required.

Access is off by default and read-only unless you allow changes. Connections use
a token on a localhost-only endpoint. Keep copied configurations private: they
contain that token. Connected AI clients may send content to their model providers.

## Documentation

- [Inbox](docs/INBOX.md) and [nested lists](docs/NESTED_LISTS.md)
- [Calendar, planning, and work sessions](docs/ADAPTIVE_CALENDAR.md)
- [Widgets](docs/WIDGETS.md)
- [Library backups](docs/LIBRARY_BACKUP.md)
- [Contributing](CONTRIBUTING.md) and [security reporting](SECURITY.md)

## License

[MIT](LICENSE). Openlist is an independent project inspired by personal task
managers including Superlist; it is not affiliated with or endorsed by Superlist.
