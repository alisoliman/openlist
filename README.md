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

Lists can also own separately titled **child list documents**. Create one from
List options, navigate with breadcrumbs, or use **Move List** to change its
parent while retaining its contents and identity. Parent archive applies to
its subtree; parent deletion retains the subtree as one restorable Trash unit.
Duplicate, template copy, Markdown folder export, and full backup preserve the
document boundaries. See [nested lists](docs/NESTED_LISTS.md).

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
Completion is silent. Pointer actions give a brief checkbox acknowledgement
and settle completed tasks below pending siblings without a delay or bounce.
Keyboard actions and Reduce Motion update immediately. Each task carries its
subtasks and attached notes; reopening restores its stored manual position.

In **Settings → Labels**, renaming into an existing name offers a merge review
with the surviving label's name, color, and affected-task count. Matching trims
outer whitespace and leading `#` characters and ignores case; internal spacing
is preserved. Existing duplicate names expose **Merge duplicates**, where you
choose which label to keep. Nothing merges until you confirm.

Merging updates labels on all tasks, including nested, completed, and archived
work, while retaining the destination identity/color and historical activity
names. **Undo merge** stays available in Settings and the main window after
navigation, until dismissed, another merge, or app restart. Task content and
unrelated label edits made afterward are preserved by undo. The central merge
path includes all stored blocks without a visibility filter; future retained
Trash records must use that path or extend it if stored separately.

### Reusable copies

**Duplicate** copies a task's complete nested procedure, including prose, notes,
formatting, images and attachments. **Use as template…** is a separate action in
task and list menus for starting fresh work. Its confirmation offers **Keep
repeating rules** only when the source contains a repeat rule; it starts unchecked.

| Field | Duplicate | Use as template |
|---|---|---|
| Content, hierarchy, sibling order, collapse state, formatting, notes | Keep | Keep |
| Labels, priority, stars, estimates and planning preferences | Keep | Keep |
| Completion and completion date | Keep | Clear |
| Due date/time and reminder | Keep | Clear |
| Repeating rule and completed-occurrence count | Keep | Remove by default; opt-in keeps the pattern/count limit, resets progress to zero and clears the old end date |
| Selected day, deferral, calendar placements, work/completion history | Do not copy | Do not copy |
| Model and occurrence identities, block/list creation timestamps | Fresh | Fresh |
| Images and attachments | Independent files and retained bytes | Independent files and retained bytes |

Each copied task starts with its own creation event. Copying never transfers source
activity; task Undo/Redo appends deletion/restoration under the new task identity.

A task copy lands after its source in the same parent/list and opens selected in
the inspector. A list copy opens as an active, non-system list named “Name copy”,
keeping its description, appearance, display preferences and sidebar section.
Task copies in an archived list stay in that list. The source remains unchanged;
storage or file failures leave no partial copy. Task copies share the editor's
Undo/Redo, including the complete subtree and files. List copying retains its
existing behavior without Undo. Clipboard copying keeps its separate semantics.

### Document content on the clipboard

In a block's context menu, **Copy content and descendants** copies its complete
subtree, including hidden/completed descendants, notes, supported inline formatting,
images, and files. **Copy subtree as Markdown** exports just that subtree as readable
text; images/files are described by name, without private local file URLs.

Use **Paste content after this block** at a destination row, or **Paste content**
in the blank document area's context menu. ⌘V in an empty outline row also inserts
the internal content. Selected text and inline pastes retain normal text behavior;
ordinary ⌘C still copies the selected text. The insertion has fresh IDs and independent
media, and is one editor Undo/Redo operation. A blank destination row is retained.
Completed content remains completed and follows the destination's visibility/sort settings.

Content paste keeps text, formatting, links, notes, hierarchy, completion/date,
collapse, stars, priority, estimates, and planning preferences. **Dates, reminders,
repeating rules, selected day, and deferral are cleared by default.** The explicit
**Paste content including schedules** action also retains those scheduling values;
only eligible future reminders are reconciled after a successful save. Repeat progress,
occurrence IDs, calendar placements, work sessions, and prior history never transfer.
Every pasted task gets a fresh Created event; Undo/Redo records Deleted/Restored.
Links retain their original destinations rather than being rewritten to the new IDs.

Labels match destination names case-insensitively, without trusting source UUIDs.
Existing destination labels and colors win; missing labels are created with the
copied name/color in the same transaction. Undo removes a newly introduced label
only if it is still unchanged and unused elsewhere; Redo reuses or restores it.

The private version-1 clipboard payload embeds file bytes and supported text-style
runs, so deleting the source or restarting Openlist does not invalidate a retained
clipboard. Limits are 10,000 blocks, 512 nesting levels, 64 MB encoded data, 40 MB
total media, and 32 MB per asset (images also have a 100-million-pixel ceiling).
Unsupported versions, malformed trees/styles, invalid paths, corrupt images,
oversized data, missing source media, or failed storage writes report an error
without a partial insertion. Copy failures preserve the previous clipboard.
Pasting never fetches remote assets or executes content. External Markdown lists
keep supported structure; unsupported fences/whitespace/indentation stay as literal
text instead of being silently discarded. No multi-selection UI is added here.

### Views

**Inbox** (⌘1) · **Today** (⌘2) · **Calendar** (⌘3) · **Tasks** (⌘4) · **Lists** (⌘5) ·
**Activity** (⌘6), plus per-label views and a completed archive. Today groups
overdue, due-today, planned-for-today, and starred work; Tasks filters and groups
by list or date; Activity shows the completion heatmap, the selected day, and the
log of recent changes. Updates now lives under Activity.

The sidebar is flat: Inbox, Today, Calendar, Tasks, Lists, and Activity sit at the
top, followed by your list sections, pinned lists, and labels. Trash and Settings
are in the sidebar footer, and Trash also opens from the View menu.
The toolbar's **New task** button (N) is the shared task capture action on every page.

Inbox holds unorganized tasks and notes. Filing into a list moves the complete
branch out of Inbox; setting a due date keeps it there. Hover or focus a row for
filing, date, details and Trash icons, or use its native context menu. See
[Inbox](docs/INBOX.md) for behavior and compatibility.

Task details include a paginated **Activity** timeline with committed title,
date/time, completion, recurrence, and list-move changes. It shares history with
Updates; **Clear History** clears both after confirmation. Older entries retain
only the facts originally recorded. See [task activity](docs/TASK_ACTIVITY.md)
for save, retention, and export behavior.

The inspector keeps the title and active metadata above notes and subtasks.
Empty notes and files use add actions rather than empty forms. Creation and
completion timestamps are inside **Activity**; **More** contains Copy Link
and Delete. Priority and label controls remain named for
accessibility, and long label collections show a compact summary.
**Add subtask** uses the document editor's insertion and Undo path, placing the
caret in the new subtask immediately.

The sidebar's **Activity** heatmap shows 12 weeks of recorded completions with
daily counts and saved task details. Ordinary tasks count once; recurring tasks
and subtasks count once per recorded occurrence. Missing history stays explicit,
and clearing Updates history also clears the heatmap. See
[activity heatmap](docs/ACTIVITY_HEATMAP.md) for counting and coverage details.

Today's **Sort** menu orders tasks within each section by priority (highest first),
due date (earliest first, undated last), title (A–Z), creation date (oldest first),
or list position and stored document order. **Default** restores the original
task ordering within each section. Equal values use creation date, then task identity for stable
ties. This Mac remembers the choice; task membership, list documents, and synced
list preferences stay unchanged.

Tasks has a local **Filter task titles** field and a **Filter** menu for status
and list. It matches visible titles without case or accent differences;
notes, labels and parent titles are not searched. **Sort tasks** independently
orders every group by due date, title or creation date in either direction.
Grouping and **Sort tasks** live in **View**. Only active filters add a second
control line; clearing the last filter returns to the compact default.
Undated tasks stay last in due-date order; equal values use creation time then
task identity for stable ties. The page count counts each matching task once,
even when it appears under several labels. **Reset filters** clears title,
status and list constraints while keeping grouping and sorting; **Reset sort**
in the sort menu restores earliest due first. These Tasks choices are temporary
screen state and reset when the app relaunches. Sorting never rewrites documents.

### Adaptive calendar

Calendar offers **1-day, 3-day, 1-week, and 1-month** views of a rolling four-week
plan. Select tasks for today or give them upcoming due dates; undated backlog
stays unscheduled. Lists inherit separate work or personal hours, with weekly
breaks and date overrides. Estimates start at an editable 30 minutes. Work can
split into sessions, with a 25-minute minimum by default and a per-task
**Keep task together** option.

Use **Work** in the toolbar to review a suggestion's planned time, duration,
deadline, and source. Suggestions never open the panel or start tracking by
themselves. **Later → Remind in 15 minutes** quiets that occurrence without
moving the plan; **Move planned time** previews affected work separately.

Start work explicitly. The toolbar shows the active task and recorded minutes,
with **Stop** always available. **Stop working** saves the session and leaves the
task open; **Complete task** completes the occurrence. Stopped work can be resumed
as a new segment. Switching tasks asks before saving the old segment and starting
another. Completion can be undone without restarting a timer.

Overruns can continue in free time, but the **first extension that would move
other work pauses recording** and asks for approval. Work shows the affected
tasks' old and proposed times, rechecks the plan when accepted, and excludes time
spent waiting. Meetings, unavailable hours, lock, and sleep pause work; a task
can opt into tracking away from the Mac. Move blocks to express a preference or
choose **Pin time** for fixed placements. Deadline coverage distinguishes
**Scheduled**, **Cannot fit before deadline**, and **Outside planning horizon**.

The **Work** menu and command palette (⌘K) offer Show work, Start selected task,
Stop current session, Resume task, and Complete current task. Existing selected-task
shortcuts keep their meaning. Optional background work notifications are enabled
in Calendar settings; reminder suppression survives replanning and restarting.

Connected macOS calendars supply read-only busy time. Session and completion
history preserve recurring occurrences, support recorded-time corrections, and
offer duration suggestions that require approval. Only the current recurring
occurrence is planned. Task choices and history use the existing local-first
store and iCloud configuration; availability and calendar connections remain
per-Mac.

See the [calendar guide and developer invariants](docs/ADAPTIVE_CALENDAR.md) for
setup, scheduling behavior, storage boundaries, and validation scope.

Each list has a **Completed (count)** control to show or hide finished tasks below
pending siblings, preserving their notes and nested content. Settings → Tasks sets the app
default; each list can inherit it or explicitly show/hide completed tasks. On
upgrade, previously hidden lists stay hidden and lists using the historical
shown default adopt inheritance. Older versions did not distinguish an explicit
Show choice from that default. Inbox continues to inherit the app setting.
The default stays on each Mac; explicit list overrides sync with the list.
This compact control sits beside Document / Tasks. Its adjacent menu chooses
the visibility policy; an empty list uses the completed icon without a zero count.

Each list also has a **Document / Tasks** switch, remembered per list on this
Mac. Document keeps headings, notes, images and nested content. Tasks hides that
prose and shows every task once, including subtasks beneath collapsed blocks;
the parent breadcrumb keeps each subtask in context. Its sort menu orders the
whole list by due date, creation date, alphabetically or priority. **Document
order** follows the original outline, and equal sort keys keep that order.
Completed tasks follow the same sort and visibility preference; hiding a
completed parent does not hide its open subtasks in Tasks mode.

Editing, completing and opening details act on the original task. **Add task**
and ⌘N in Tasks mode start capture in the current list and place the new task at
the end of its document, then show it at its sorted position. You can choose
another destination in capture. Returning to Document restores the original
prose and hierarchy; its existing sort continues to order only adjacent root
tasks, carrying each subtree. Neither presentation rewrites stored order. Drag
reordering remains an operation of manual Document view. Search and reminder
links to exact content return to Document so hidden prose can be revealed.

The [list Tasks validation guide](docs/LIST_TASKS.md) covers the projection and
native interaction checks.

### Capture and navigation

⌘K quick command (creates tasks, jumps to lists, runs commands), ⌘F search across
tasks, notes and lists, ⇧⌥Space global quick-add from any app, and a menu bar
popover. ⌘/ shows the full shortcut reference.

Capture keeps the destination visible and previews detected dates, repeats,
and labels. Per-draft date detection lives in **Capture options** (the ellipsis);
the default is in Settings → Tasks. Return adds the task, and Escape cancels.
Navigation, command selection, and keyboard scrolling do not animate. Custom
pointer feedback lasts 140 ms; task rearrangement lasts 200 ms. Reduce Motion
disables custom movement.
Back restores native scroll coordinates, including the negative offset beneath
the toolbar, so returning to a page does not clip its heading or accumulate drift.
Rescheduling summaries and work notices live in the toolbar's Work panel, available
from every destination. Passive changes never displace the current document.
Save failures remain visible across the app.

Row-selection handles reveal on hover, selection, or keyboard focus without
changing the row's hit target. They stay available to accessibility, and
VoiceOver keeps them visible. Command-click, Shift-click, and arrow selection
retain their existing behavior; a task's round checkbox still means completion.

Search shows an honest total and loads results in batches of 80; **Load next**
and the arrow keys can reach every match. **Include completed** and **Include
archived** start on, retaining access to existing content. The Notes scope finds
non-task blocks; notes attached to tasks also match in All and Tasks. Matching
ignores case, accents and character width, and results include their list,
ancestor path and a matching passage when needed.
The **Search filters** button contains type, completion, and archive controls.
Non-default filters remain summarized below the query; Reset filters keeps the query.

Opening a result resolves its current identity. Tasks open their inspector and
reveal the matching title or note; other blocks open their owning list, scroll
to the exact result and temporarily expose collapsed/completed ancestors.
**Finish** or leaving the page ends this temporary reveal without changing
stored collapse, archive or completion settings. Missing results show an
unavailable message. Escape closes search and returns focus to its previous
control when no result was opened. Search preferences are local to the open
search session; no index or query history is persisted.

**Copy Link** in task and list menus copies a stable reference to that item in
this Mac's library. Links survive renaming and moving tasks, and can open
Openlist from another app. Archived content is clearly identified and stays
archived; missing or wrong-library targets show an explanation. Openlist Dev
uses a separate URL scheme. See the [local link and backup/restore contract](docs/local-item-links.md).

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
iCloud sync is not a backup. Settings > Data can create a complete, unencrypted
`.openlistbackup` package with library records, history and media. Restore previews
the package before explicit quit/reopen, opens a separate local-only library,
and retains the original library and a recovery backup. Return to the original
library through the same Data settings. See [manual backup and restore](docs/LIBRARY_BACKUP.md)
for the format, limits, recovery behavior and privacy details. App-wide
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
Client setup appears after MCP is enabled. **Connection options** contains the
port and token-reset controls; access and token warnings remain visible.

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
  Editor/      BlockTextView (AppKit-backed), OutlineEditor, DocumentView,
               BlockRowView, SlashMenuView, MarkdownInputRules, BlockDragAndDrop
  Next/        Openlist Next shell: sidebar, screens, rows, inspector,
               calendar, overlays, Workbench (shared UI state and actions)
  Views/       RootView, document screens, shared pickers, settings
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
so `sizeThatFits` can measure synchronously) and `OutlineEditor` arbitrates the keys.
`OutlineEditor` owns the caret, the `/` menu and every structural edit, and knows
nothing about how rows look, so `DocumentView` is only one renderer over it.
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

### Reminder scheduling and recovery

A task’s reminder time is saved intent. Openlist reports **Accepted by macOS**
only after the notification center returns a matching pending request for that
saved task occurrence. This does not prove that an alert was displayed: Focus,
notification preferences, and macOS delivery policy still apply. Local scheduling
status is rebuilt from the saved library and OS inventory after launch; it is not
synced as a task fact.

Task details and Settings → Tasks show permission problems and scheduling errors.
Use **Allow notifications** or **Open Notification Settings** for permission, and
**Retry reminder** / **Retry future reminders** for eligible future times. Recovery
never requests permission automatically and never replays expired reminders.
Expired intent remains visible. A previously delivered expired alert can remain in
Notification Center; completion, archive, deletion, removal or replacement of its
saved reminder clears obsolete pending and delivered alerts. Calendar nudges use a
separate namespace and ordinary reminder recovery preserves them.

There is at most one reminder request per task UUID. A custom reminder takes
precedence over an automatic due-time reminder; repeating tasks retain their
existing relative offset while replacing the occurrence. Saved dates represent
absolute instants and notification triggers include UTC so travel and DST do not
reinterpret an already scheduled time. Saved title/list changes update request
text. Unsaved changes never replace the prior OS request and are labeled separately.
Notification clicks wait for bootstrap and the main window, then reveal the exact
task through the same temporary expansion used by search, or explain that the
subject is unavailable. Review fixtures disable actual notification operations and
say so; injected tests simulate acceptance and failures without changing permissions.

For isolated native failure/retry checks, a bundle with `OpenlistReviewSession`
may opt into `OpenlistReviewReminderSimulation = true`. Every task’s first add
fails, Retry creates a **Simulated pending reminder**, and simulated inventory is
kept only in that review session’s defaults for relaunch checks. This opt-in never
creates a notification center or changes permission. It is not delivery evidence.

Quitting saves current edits, waits up to five seconds for reminder work, then
saves any edits made during that wait. A save failure cancels quitting. If macOS
does not answer within the limit, the app can quit with saved intent still
unconfirmed; the next launch reconciles it. Timeout never implies acceptance.

### Recovering deleted content

Delete moves a task subtree or an entire list to **Trash** in the sidebar.
Trash keeps content indefinitely; nothing is emptied automatically. Each item
shows its former location, deletion time, and retained file size. Restore keeps
original IDs, rich notes, nested content, files, labels, completion and list
ownership. Tasks in Trash are excluded from active views, search, widgets and
reminders. Only eligible future reminders resume after restoration.

An independently deleted child stays a separate Trash item when its parent or
list is later deleted. Restoring the parent restores only the content deleted
with it. If the original parent or list is unavailable, Restore explicitly
creates a pinned **Recovered items** list and keeps a separate provenance note;
it does not rewrite the original notes. Archived lists keep their archive state.

**Permanently Delete** and **Empty Trash** require confirmation and remove only
files with no remaining live or retained references. These actions cannot be
undone. Editor merges and abandoned empty captures use structural cleanup and
session Undo; they do not fill Trash. Settings → Delete everything permanently
removes both active content and Trash. Library backup format 3 includes Trash
and its media; versions 1 and 2 can still be imported. A restore already staged
by an older app must be cancelled and prepared again from the original backup.
