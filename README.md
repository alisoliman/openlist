# Openlist

An open-source, local-first task and notes app for macOS, built with SwiftUI and
SwiftData. Organize tasks in rich documents, capture ideas with a global shortcut,
and keep your day in view with desktop widgets.

Inspired by personal task managers including Superlist. Openlist is an independent
project and is not affiliated with or endorsed by Superlist.

## Download

Download the **Apple Silicon (arm64)** DMG or ZIP from
[GitHub Releases](https://github.com/alisoliman/openlist/releases/latest).
Requires an **Apple Silicon Mac (M1 or newer) running macOS 26.5 or later**.
Intel binaries are not currently published.

Open the DMG and drag `openlist.app` to Applications, or unzip the ZIP and move
the app there. Launch Openlist before adding its widgets. Official release
packages are Developer ID signed and notarized by Apple.

Downloads include `SHA256SUMS.txt`. To check both downloaded packages:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

Your lists and attachments are saved on your Mac. iCloud-enabled builds also sync
them privately through your Apple Account; there is no separate Openlist account.
You can keep working offline. Before installing an update, quit Openlist.
Existing local data is preserved.

## Build from source

Requires Xcode 26.5 or later and macOS 26.5 or later. CI and release builds use
`macos-latest` and the newest stable Xcode installed on that Apple Silicon image.

```sh
git clone https://github.com/alisoliman/openlist.git
cd openlist
./Tools/check.sh
./Tools/build-release.sh 0.1.0 1
open openlist.xcodeproj
```

The build script compiles an unsigned app without requiring an Apple account.
For running from Xcode, configure signing for the app and widget as described in
[CONTRIBUTING.md](CONTRIBUTING.md). They share the App Group
`Y5UE64R7TQ.solimanali.openlist`.

See [contributing and releases](CONTRIBUTING.md), [security reporting](SECURITY.md),
and the [MIT license](LICENSE).

---

## What's implemented

### Lists are documents, not checklists

A list holds an arbitrarily deep tree of blocks — tasks, paragraphs, three heading
levels, bullets, numbered items, quotes, code and dividers, plus inline images.
A task's detail page is the same editor rooted at that task, so subtasks nest as
deeply as you like.

Typing drives everything:

| Type | Get |
|---|---|
| `/` | block menu, filterable, arrow-key driven |
| `[]` · `-` · `1.` · `#` · `##` · `###` · `>` · `---` | the matching block |
| `**bold**` · `*italic*` · `~~strike~~` · `` `code` `` | inline styling |
| `#label` | attaches a label |
| paste of several lines | one block per line, nesting preserved |
| "tomorrow at 6pm", "every monday", "in 3 days" | due date and repeat rule |

⇥ / ⇧⇥ indent and outdent, ⌫ at the start of a line merges upwards, ⌥⌘↑/↓ move a
block with its subtree, and blocks drag to reorder or nest.

### Tasks

Due dates and times, reminders via `UserNotifications`, repeat rules (daily,
weekly-on-weekdays, monthly, yearly, every-N, anchored to either the schedule or
the completion date, ending never / on a date / after N times), labels, priority,
stars, and progress rollups from subtasks.
Completing a repeating task rolls it forward to the next occurrence rather than
marking it done.

### Views

**Inbox** (⌘1) · **Today** (⌘2) · **Updates** (⌘3) · **Tasks** (⌘4) · **Lists** (⌘5),
plus per-label views and a completed archive. Today buckets overdue / due today /
starred; Tasks filters and groups by date, list, label or priority; Updates is a
personal activity feed grouped by day.

### Capture and navigation

⌘K quick command (creates tasks, jumps to lists, runs commands), ⌘F search across
tasks, notes and lists, ⇧⌥Space global quick-add from any app, and a menu bar
popover. ⌘/ shows the full shortcut reference.

### Widgets

Three macOS widgets — **Today**, **Summary** and **Lists**. The app publishes a small
JSON snapshot into the shared App Group container and reloads timelines on save;
the widget never opens the SwiftData store, which keeps cross-process access out
of the picture entirely.

### iCloud

Provisioned builds automatically sync lists, nested tasks, notes, formatting,
labels, sections, activity, images and attachments with your private iCloud
database. Use the same Apple Account on your Macs and enable Openlist in iCloud
settings. **Settings > iCloud** shows account availability, transfer activity,
the last upload/download in this session, and actionable errors.

The existing SQLite store stays in place. The first sync uploads existing local
content, and an additive migration copies imported files into synced binary
attributes without removing the originals. Downloads can recreate local files
for opening, duplication and portable Markdown export. Imported attachments are
snapshots: reattach a file to sync changes made to it in another application.

Transfers run on Apple's schedule, not immediately. Offline edits are saved
locally and sync when iCloud becomes available. macOS can postpone discretionary
CloudKit transfers on low battery, even while charging; connect to power and
allow the battery to recover for the initial sync.
CloudKit resolves record conflicts; simultaneous edits to the same field can
replace one another. Open editors reflect incoming formatting, and untouched
title drafts follow remote changes without overwriting them on blur.
In-progress title edits are kept until committed.
System Inboxes and default sections created independently on different Macs converge,
keeping the oldest record and retaining aliases so later-arriving tasks still
find their destination. A fresh Mac's defaults do not replace existing custom
Inbox and section settings.
Ordinary user-created lists and sections are never merged by name. Incomplete
parent downloads and cycles from concurrent moves remain visible in a stable
outline without rewriting their stored parent links.

**Deletions sync too**, including clearing activity and resetting all data.
iCloud sync is not a backup; export important lists separately. App-wide
preferences remain per-Mac, and reminders and widget snapshots are refreshed
locally after imports. Widgets do not run their own sync engine.

New installs start without sample lists to avoid uploading a fresh set of demo
content from every Mac. Existing content is not removed. Unsigned builds and
isolated review fixtures explicitly use local-only storage. If a database cannot
be opened, the app reports the failure rather than opening a disposable empty
database.

### Also

Sidebar sections (create, rename, collapse, drag lists between them), list icons
and colours, per-list sort order, Markdown export, light/dark/system appearance,
Dock badge, and local-first storage with native SwiftData/CloudKit sync.

### AI clients through MCP

Openlist ships a native MCP server and stdio launcher. Enable it in
**Settings > AI Agents**, copy a client configuration, and keep Openlist running.
Agents can read lists, tasks and notes, or optionally create, edit, complete,
move and archive them. Access is off by default, read-only unless you allow
changes, and protected by a Keychain-backed token on a localhost-only endpoint.
No Node/Python runtime or cloud service is required.

Choose **Claude Desktop / stdio** or **VS Code / HTTP** in Settings, merge the
copied configuration into your client's MCP settings, and reconnect. Other local
clients can use the bundled stdio launcher or the Streamable HTTP endpoint with
its bearer token.

Keep copied configurations private: they contain your access token. Turning MCP
off disconnects clients; resetting the token revokes old configurations. Connected
AI clients may send the content they read to their own model providers.

Per-list *grouping* was cut rather than shipped half-working: grouping a rich
document that mixes headings, notes and tasks has no well-defined meaning, and
the Tasks screen already groups across every list by date, list, label or
priority.

---

## Deliberately excluded

Openlist focuses on personal, local-first workflows. These features are outside its current scope:

| Feature | Why |
|---|---|
| Voice AI ("Talk") | Outside the local task-management scope |
| AI Meeting Notes, AI Chat, Make AI, email/Slack summarisation | Requires online AI services |
| Integrations (Gmail, Slack, GitHub, Figma…) | Outside the local task-management scope |
| Sharing, real-time collaboration, assignees, comments, voice messages | Requires a collaborative backend |
| Unlimited-lists / storage caps | Lists here are uncapped |

---

## Layout

```
openlist/
  Model/       Block, TaskList, TaskLabel, SidebarSection, Attachment,
               ActivityEvent, Recurrence
  Services/    Store (+Blocks, +Tasks), BlockTree, DateParser,
               RecurrenceEngine, RichTextCodec, MediaStore, MarkdownExporter,
               NotificationService, QuickCaptureHotKey, WidgetSnapshotPublisher,
               ICloudConfiguration, ICloudSyncMonitor, ICloudSyncState
  Editor/      BlockTextView (AppKit-backed), DocumentView, BlockRowView,
               SlashMenuView, MarkdownInputRules, BlockDragAndDrop
  Views/       RootView, SidebarView, screens, pickers, palette, settings
  Design/      Theme
Shared/        ListAccent, WidgetSnapshot, AppGroup   (app + widget)
OpenlistWidget/  WidgetKit extension
MCPTransport/   Local Swift package: authenticated MCP/HTTP transport
OpenlistMCPHelper/  Bundled native stdio-to-localhost launcher
Config/          entitlements and the extension Info.plist
Tools/           regression suites, live CloudSyncChecks, release tooling
```

### One store, one context

`Store` uses the container's `mainContext` — the same one `@Query` hands to
views. A second context would look tidier but is a trap: views pass queried
objects straight into store mutations, so the edits land in `mainContext` while
`Store.save()` checks its own (permanently clean) context, and nothing persists
or reaches the widget.

### Why the editor is AppKit-backed

SwiftUI's `TextEditor` cannot express what an outliner needs — Return that splits a
block, ⇥ that re-parents it, ⌫ that merges into the row above, arrow keys that walk
between blocks. Each block therefore hosts a bare `NSTextView` (explicit TextKit 1,
so `sizeThatFits` can measure synchronously) and `DocumentView` arbitrates the keys.
Everything else is SwiftUI.

---

## Checks

```bash
./Tools/check.sh
```

Compiles the pure-logic sources against a set of assertions — 71 checks covering
natural-language date parsing (relative days, weekdays, times, explicit dates,
repeat phrases, and *not* firing on ordinary prose) and the recurrence engine
(weekday sets, month-end clamping, overdue catch-up, end conditions), plus
regression checks for every bug found in review: decimals like "swift 6.2" being
eaten as dates, `9 p.m.` parsing as 09:00, "tonight" resolving to midnight,
monthly series sticking on the 28th after a February, and every-N-weeks drifting
across a 53-week year.

A second suite compiles `RichTextCodec` itself and checks the prefix/suffix
splice that lets a plain text field retitle a task without dropping its inline
styling — including typing *inside* a bold word.

The iCloud suite writes a pre-sync SQLite schema in one process and migrates and
reopens it in separate processes. It checks CloudKit schema constraints, media
backfill and recovery, downloaded-file export/duplication/undo, system-record
convergence and out-of-order references, unavailable accounts, operation errors,
remote-change notifications, and preservation of unreadable stores. These
regressions are offline and do not access an Apple Account.

Live development-container verification is separate and requires a
development-signed app with an embedded iCloud provisioning profile:

```sh
./Tools/run-cloud-sync-checks.sh /path/to/Debug/openlist.app --account-only
./Tools/run-cloud-sync-checks.sh /path/to/Debug/openlist.app --connection
./Tools/run-cloud-sync-checks.sh /path/to/Debug/openlist.app --initialize-schema
./Tools/run-cloud-sync-checks.sh /path/to/Debug/openlist.app --run
```

Connect the Mac to AC power and let it recover from low battery before running
the live checks. A diagnostic deadline is not proof of a failed migration:
macOS may defer the underlying
background network operation without sending it while battery power is low.

The live check runs a headless native app with independent stores in an isolated
App Group subdirectory. Each replica runs in its own process, matching separate
app launches rather than concurrent stacks in one app. It waits for actual server records, compares imported
content and 2 MiB assets, and checks remote edits and deletion using synthetic
UUID-tagged fixtures. It never opens the personal database and refuses Production
signatures. Transfers are asynchronous and a one-Mac check cannot establish
cross-device push delivery; test the UI on two physical Macs before release.
Each transfer has a ten-minute diagnostic deadline and completed phases are
checkpointed. The verified return import is checkpointed before deleting local
fixtures, so a deletion timeout can be resumed without waiting for a removed task.
Use `--resume /path/to/OpenlistCloudCheck-UUID` to continue a
retained fixture without creating new test data.
Production schema deployment and Developer ID provisioning
are documented in [release maintenance](CONTRIBUTING.md#releases).
If a network failure prevents confirming fixture deletion, rerun with
`--cleanup /path/to/the/reported/OpenlistCloudCheck-UUID` once iCloud is
reachable. Recovery reads record identifiers only, deletes only that fixture's
UUIDs, confirms their absence, and removes its isolated local stores.

MCP checks exercise the official protocol client, authentication and loopback
boundaries, the bundled stdio bridge, and real Store operations against isolated
disk fixtures, including permission changes, recurring completion, failed-save
rollback and separate-process reopening. Swift package dependencies are fetched
on the first build or check; no extra runtime is needed by the installed app.

`Tools/screenshot.sh out.png ['keystroke "2" using command down' ...]` captures
the running app's window and can drive it with keystrokes first, so UI changes
can be verified rather than assumed. It is window-scoped — it never grabs the
rest of the desktop — and needs Screen Recording (capture) plus Accessibility
(keystrokes) granted to the terminal app. `OPENLIST_WINDOW=front` targets
Settings or Quick Add instead of the main window.

`Tools/add-widget-target.py` regenerates the widget target in the project file and
is idempotent.
