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

A list's document holds tasks, paragraphs, three heading levels, bullets,
numbered items, quotes, code and dividers, plus inline images. Subtasks are
written in the list's document. Indenting, dragging, Add subtask and pasted
Markdown nest only tasks and list items, only under a task or list item and two
levels deep at most, as the design's indent allows, and a line turned into a
heading or text goes to the top. Pasted Openlist content keeps the hierarchy it
was copied with, within those two levels, and an older outline keeps its own.
The inspector lists a task's subtasks with their progress, and a subtask shows
the task it belongs to.

Lists can also own separately titled **child list documents**. Create one with
**New Child List** in a list's **…** menu; a parent shows its children above its
document, and the sidebar nests them. **Move List…** changes a list's parent
while retaining its contents and identity. Parent archive applies to
its subtree; parent deletion retains the subtree as one restorable Trash unit.
Duplicate, template copy, Markdown folder export, and full backup preserve the
document boundaries. See [nested lists](docs/NESTED_LISTS.md).

Typing drives everything:

| Type | Get |
|---|---|
| `/` at the start of a line | the Turn into card, filterable, arrow-key driven |
| `[ ]` · `[]` · `-` · `*` · `#` · `##` | a task, a bullet, a heading or a subheading |
| `>` | a text line |
| `**bold**` · `*italic*` · `~~strike~~` · `` `code` `` | inline styling |
| paste of several lines | one line each; tasks and list items nest, two levels at most |

A line keeps its text as typed; labels and dates are read in capture.

⇥ / ⇧⇥ indent and outdent tasks and list items, two levels deep at most; ⌫ at the
start of a line turns a heading or list item into text, steps a nested line out,
and takes an empty line away, but never merges lines. ⌥⌘↑/↓ move a line with its
subtree, and a line's grip drags it to reorder or nest.

### Tasks

Due dates and times, reminders via `UserNotifications`, repeat rules (daily,
weekly-on-weekdays, monthly, yearly, every-N, anchored to either the schedule or
the completion date, ending never / on a date / after N times), labels, priority,
stars, and progress rollups from subtasks.
Completing a repeating task rolls it forward to the next occurrence rather than
marking it done.
Completing a task, by click or with **E**, strikes its row and leaves it in
place for the undo window (2–8 seconds, set in Settings → Motion & feedback);
then a top-level task moves to its Completed group, while a subtask stays struck
where it is. The tray reports each completion with Undo. The **Motion** setting
in Settings → Appearance sets how lively rows move, and **Reduce motion** drops
the bounces and slides. Each task carries its
subtasks and attached notes; reopening restores its stored manual position.

In **Settings → Labels**, renaming into an existing name offers a merge review
with the surviving label's name, colour, and affected-task count. Matching trims
outer whitespace and leading `#` characters and ignores case; internal spacing
is preserved. Existing duplicate names expose **Merge duplicates**, where you
choose which label to keep. Nothing merges until you confirm.

Merging updates labels on all tasks, including nested, completed, and archived
work, while retaining the destination identity/colour and historical activity
names. The merge reports in the tray with **Undo**, and ⌘Z takes it back too, in
turn with the window's other changes: changes made after it are undone first.
Undo brings the merged label back on each task that had it; label edits that reach
those tasks meanwhile from elsewhere, like sync or MCP, are kept. The central merge
path includes all stored blocks without a visibility filter; future retained
Trash records must use that path or extend it if stored separately.

### Reusable copies

**Duplicate** copies a task's complete nested procedure, including prose, notes,
formatting, images and attachments. **Use as Template…** is a separate action in
task and list menus for starting fresh work. Its confirmation offers **Keep
repeating rules** only when the source contains a repeat rule; it starts unchecked.

| Field | Duplicate | Use as Template… |
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

A task copy lands right after its source in the same parent/list and is
highlighted there; only a template copy also opens in the inspector. A list copy
opens as an active, non-system list named “Name copy”, keeping its description,
appearance, display preferences and sidebar section. Task copies in an archived
list stay in that list. The source remains unchanged; storage or file failures
leave no partial copy. Each copy, of a task or a list, is one change in the tray
with Undo. Task copies share the editor's Undo/Redo, including the complete
subtree and files; a list copy's Undo takes the copy to Trash. Clipboard copying
keeps its separate semantics.

### Document content on the clipboard

In a task's context menu, **Copy Content and Subtasks** copies its complete
subtree, including hidden/completed descendants, notes, supported inline formatting,
images, and files. Other apps receive it as readable Markdown, with images/files
described by name, without private local file URLs.

⌘V in a line of a list document inserts the internal content after that line, or,
when what it holds can't go there, beside a line that line is under, after the lines
under it; over selected text it pastes the text of the content's lines, a space
between them, and in other apps it pastes as Markdown. With nothing selected, Paste
and Match Style (⌥⇧⌘V) puts the content's Markdown in as lines of their own, as
pasted Markdown goes in. A list document's lines hold one line each, so a paste over
selected text puts a space for each line break it brings; a code line keeps them.
Ordinary ⌘C still copies the selected text.
The insertion has fresh IDs and independent media, and is one editor Undo/Redo
operation. Pasted into a new empty line, such as one just opened with Return, the
content takes that line's place when it fits there; otherwise it goes in where it
fits and the empty line goes. A line that was already empty is kept. Completed
content remains completed and follows the destination's visibility/sort settings.

Content paste keeps text, formatting, links, notes, hierarchy (within the list
document's two levels), completion/date, collapse, stars, priority, estimates, and
planning preferences. **Dates, reminders, repeating rules, selected day, and
deferral are cleared.** Repeat progress, occurrence IDs, calendar placements, work
sessions, and prior history never transfer.
Every pasted task gets a fresh Created event; Undo/Redo records Deleted/Restored.
Links retain their original destinations rather than being rewritten to the new IDs.

Labels match destination names case-insensitively, without trusting source UUIDs.
Existing destination labels and colours win; missing labels are created with the
copied name/colour in the same transaction. Undo removes a newly introduced label
only if it is still unchanged and unused elsewhere; Redo reuses or restores it.

The private version-1 clipboard payload embeds file bytes and supported text-style
runs, so deleting the source or restarting Openlist does not invalidate a retained
clipboard. Limits are 10,000 blocks, 512 nesting levels, 64 MB encoded data, 40 MB
total media, and 32 MB per asset (images also have a 100-million-pixel ceiling).
Unsupported versions, malformed trees/styles, invalid paths, corrupt images,
oversized data, missing source media, or failed storage writes report an error
without a partial insertion. Copy failures preserve the previous clipboard.
Pasting never fetches remote assets or executes content. External Markdown keeps
supported structure only when the whole paste reads as Markdown lines. A blank line,
trailing space, an indent a list wouldn't have or a fence anywhere in it brings the whole
paste in as a trimmed text line for each non-blank line, Markdown markers included, and a
fenced block as one code line that keeps its breaks and indent. No multi-selection UI is
added here.

### Views

**Inbox** (⌘1) · **Today** (⌘2) · **Calendar** (⌘3) · **Tasks** (⌘4) · **Lists** (⌘5) ·
**Activity** (⌘6), plus per-label views. Today groups overdue, due-today,
planned-for-today and starred work, with what was completed today; Tasks filters
by status and query words and groups by list or date; Activity shows the
completion heatmap, the selected day, and the log of recent changes.

The sidebar is flat: Inbox, Today, Calendar, Tasks, Lists, and Activity sit at the
top, followed by your list sections, pinned lists, and labels. Trash and Settings
are in the sidebar footer, and Trash also opens from the View menu.
The toolbar's **New task** button (N) is the shared task capture action on every page.

Inbox holds unorganized tasks and notes. Filing into a list moves the complete
branch out of Inbox; setting a due date keeps it there. Inbox opens as triage,
one task at a time: file it, schedule it, mark it done, discard it or keep it for
later. Its header button shows it as a document instead. See
[Inbox](docs/INBOX.md) for behaviour and compatibility.

Task details end with **Activity**: this session's changes and, under **Full
history**, a paginated timeline of committed title, date/time, completion,
recurrence, and list-move changes, with the creation and completion times. It
shares history with Activity's **Changes**; **Clear all activity history…** in
Settings › Data clears both after confirmation. Older entries retain only the
facts originally recorded. See [task activity](docs/TASK_ACTIVITY.md) for save,
retention, and export behaviour.

The inspector keeps the title and active metadata above notes and subtasks.
Empty notes and files use add actions rather than empty forms; removing a file
can be undone. Its footer has **Trash** and **Start working**; **Copy Link** is in the
task's menu and in Task ▸ **Copy Link**. Priority and label controls remain
named for accessibility.
**Add subtask** goes to the task's list document, opening it if needed, unfolds
the task and writes a new subtask line at the end of its subtasks, as one Undo
step.

The **Activity** screen's heatmap shows 12 weeks of recorded completions with
daily counts and saved task details. Ordinary tasks count once; recurring tasks
and subtasks count once per recorded occurrence. Clearing activity history also
clears the heatmap. See [activity heatmap](docs/ACTIVITY_HEATMAP.md) for
counting and coverage details.

Tasks shows every task in its lists' outline order, under **Open**, **Completed**
or **All**. Its query field combines words: `overdue`, `today`, `tomorrow`, `week`,
`later` and `undated` for dates, `starred`, `planned` and `high` for flags, a
list's key word, `#label`, and any other text to match titles. Suggestions
complete the word being typed, and the grouping label beside the field switches
between list, date and none. Settings → Appearance can swap the query for a
sentence of list and title filters. These choices are screen state and never
rewrite documents.

### Adaptive calendar

Calendar offers **day, 3-day and week** views of the work placed on it. Tasks
picked for today or due soon wait under **Not planned yet** until **Plan** or
**Task → Find a Slot** places them; undated backlog stays unscheduled. A rolling
four-week plan behind it drives the Work panel's suggestion and deadline
coverage. Lists inherit separate work or personal hours, with weekly
breaks and date overrides. Estimates start at an editable 30 minutes. Work can
split into sessions, with a 25-minute minimum by default and a per-task
**Keep task together** option.

The **Work** panel (**Work → Show Work**, or the toolbar's work notch while
working) shows a suggestion's planned time, duration, deadline, and source.
Suggestions never open the panel or start tracking by themselves. **Later… →
Remind in 15 minutes** quiets that occurrence without moving the plan; **Later… →
Move planned time…** moves a placed block, listing what the new time would overlap.

Start work explicitly, at any time. The toolbar's work notch shows the active task
and its elapsed time, with **Pause** or **Resume**, **Done** and **Stop** always
available. **Pause** saves the session and keeps the work to resume as a new
segment; **Stop working** saves it, leaves the task open and ends the work;
**Complete task** completes the occurrence. Starting another task switches
straight away, saving the old segment, and the tray offers Undo. Completion can
be undone without restarting a timer.

Recording continues past the estimate: the working block grows in 15-minute steps
and later placements that day move out of its way, with Undo in the tray. When a
meeting or a break leaves no more room, work keeps recording and the work notch
names what it is running into; at the end of available hours the block simply
stops growing. Lock and sleep pause work; a task can opt into tracking away from
the Mac, which still stops at the next meeting, break, pinned time or the end of
its hours. **Plan** on Calendar's **Not planned yet** column pins a task into its
next free slot, and **Move planned time…** in the Work panel pins its block at
another time, each as one change with Undo in the tray. A slot that goes by unworked stays on the
calendar as **carried forward**, and the task's details show where the calendar
has it. Deadline coverage, which the planner rates without showing,
distinguishes **Scheduled**, **Cannot fit before deadline**, and **Outside
planning horizon**.

The **Work** menu offers Show Work, Start Selected Task, Stop Current Session,
Pause or Resume Task, and Complete Current Task, acting in place as the notch's
buttons do; the command palette (⌘K) has **Start working**. Existing selected-task
shortcuts keep their meaning. Optional background work notifications are turned
on with **Notify me about planned work** in Settings → Notifications; reminder
suppression survives replanning and restarting.

Connected macOS calendars supply read-only busy time. Session and completion
history preserve recurring occurrences, support recorded-time corrections, and
offer duration suggestions that require approval. Only the current recurring
occurrence is planned. Task choices and history use the existing local-first
store and iCloud configuration; availability and calendar connections remain
per-Mac.

See the [calendar guide and developer invariants](docs/ADAPTIVE_CALENDAR.md) for
setup, scheduling behaviour, storage boundaries, and validation scope.

Settings → Tasks sets whether completed tasks show by default; each list can
inherit it or explicitly show or hide them under **Completed Tasks** in its **…**
menu, preserving their notes and nested content. On
upgrade, previously hidden lists stay hidden and lists using the historical
shown default adopt inheritance. Older versions did not distinguish an explicit
Show choice from that default. Inbox continues to inherit the app setting.
The default stays on each Mac; explicit list overrides sync with the list.
On a list's page, done top-level tasks gather in the **Completed** group under
its document, open or folded by that preference.

The list's **…** menu also has **Show Tasks Only**, remembered per list on this
Mac: the same document with its headings, notes and prose hidden, each task
under the tasks above it. Its **Sort** menu orders the list's top-level tasks by
due date, creation date, alphabetically or priority. **Manual** follows the
original outline, and equal sort keys keep that order.

Editing, completing and opening details act on the original task. **New task**
and ⌘N on a list start capture in that list and place the new task at the end of
its document, then show it at its sorted position. You can choose another
destination in capture. Turning Tasks Only off restores the original prose and
hierarchy; the sort orders only adjacent root tasks, carrying each subtree, and
neither presentation rewrites stored order. A search hit or link on a line, a
line's note or the list's description shows the document for that visit so
hidden prose can be revealed; one on a task or the list itself keeps the list
as it is shown.

The [list Tasks guide](docs/LIST_TASKS.md) covers the presentation and its checks.

### Capture and navigation

⌘K command palette (task actions, New task, and going to screens and lists),
⌘F search across tasks, notes and lists, ⇧⌥Space global quick-add from any app,
and a menu bar popover. ⌘/ shows the full shortcut reference.

Capture keeps the destination visible and previews detected dates, repeats,
labels, priority and estimates as you type: "tomorrow at 6pm" or "in 3 days" sets
the due date, "every monday" the repeat rule, `#label` a label, `!high` the
priority and `~15m` the estimate. A line written in a list's document keeps these
words as typed. Date detection follows Settings → Capture. Return adds the task,
Shift-Return adds it and keeps capture open for the next, Tab steps the
destination, and Escape cancels. Quick Add is the same card floating over the app
you're in, and focus goes back to that app when it closes.
Clicking or switching away also closes it, but the next Quick Add within five
minutes picks up what you'd typed. ⇧⌥Space works from launch, with or without
a window open; with VoiceOver on, Quick Add brings Openlist forward so
VoiceOver can read it.
Settings → Appearance sets the motion style. Settings → Motion & feedback sets
**Reduce motion**, which keeps state changes but drops bounces, rings and slides,
and the undo window a finished task stays in place for. Work notices live in the
Work panel, available from every destination. Passive changes never displace the current document.
Save failures remain visible across the app.

⌘-click or ⇧-click selects rows on a screen, and the selection bar completes,
schedules, plans, stars or trashes them together; a task's round checkbox still
means completion. See [row selection](docs/BLOCK_SELECTION.md).

Search (⌘F) finds tasks, notes, headings and lists, archived content included,
and lists the first 12 results, as the design does; keep typing to narrow them.
**Include completed** adds finished tasks. Matching ignores case, accents
and character width, and results include their list, ancestor path and a
matching passage when needed.

Opening a result resolves its current identity. Tasks open on their list, or the
Inbox, with their row focused and their inspector open, scrolled to the matched
title or note. Other blocks open their owning list's
document (the Inbox's too), scroll to the exact result, tint it briefly and
temporarily expose collapsed/completed ancestors. Leaving the page ends this
temporary reveal without changing stored collapse, archive or completion
settings. Missing results show an unavailable message.
Escape closes search. No index or query history is persisted.

**Copy Link** in task and list menus, or Task ▸ **Copy Link** for the selected
or open task, copies a stable reference to that item in this Mac's library.
Links survive renaming and moving tasks, and can open Openlist from another app.
Archived content is clearly identified and stays archived; missing or
wrong-library targets show an explanation. Openlist Dev uses a separate URL
scheme. See the [local link and backup/restore contract](docs/local-item-links.md).

### Widgets

Seven macOS widgets — **Today**, **Up Next**, **Quick Add**, **List**, **Agenda**,
**Summary** and **Activity** — drawn for full colour, dark and the desktop's
in-background rendering. The app publishes a small JSON snapshot into the shared
App Group container and reloads timelines when anything they show changes; the
widget never opens the SwiftData store, which keeps cross-process access out of
the picture entirely. Ticking a task off, and Up Next's Start, Pause and Done, are
App Intents: applied at once inside the app, or queued in the container for the
app when the system runs them in the extension. `Tools/WidgetPreviews/render.sh`
renders every kind and size from the design's sample data.

### iCloud

Provisioned builds automatically sync lists, nested tasks, notes, formatting,
labels, sections, activity, images and attachments with your private iCloud
database. Use the same Apple Account on your Macs and enable Openlist in iCloud
settings. **iCloud sync** in Settings shows account availability, transfer activity,
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
for the format, limits, recovery behaviour and privacy details. App-wide
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
move and archive them. Their writes follow the list document's rules: tasks and
list items go under a task or list item, two levels deep at most. Access is off
by default, read-only unless you allow changes, and protected by a
Keychain-backed token on a localhost-only endpoint.
No Node/Python runtime or cloud service is required.

Choose **Claude Desktop / stdio** or **VS Code / HTTP** in Settings, merge the
copied configuration into your client's MCP settings, and reconnect. Other local
clients can use the bundled stdio launcher or the Streamable HTTP endpoint with
its bearer token.
Client setup appears after MCP is enabled: the endpoint, the client
configuration with **Copy configuration** and **Copy token**, the **Port**, and
**Access token** with **Reset access token…**; access and token warnings remain
visible.

Keep copied configurations private: they contain your access token. Turning MCP
off disconnects clients; resetting the token revokes old configurations. Connected
AI clients may send the content they read to their own model providers.

Per-list *grouping* was cut rather than shipped half-working: grouping a rich
document that mixes headings, notes and tasks has no well-defined meaning, and
the Tasks screen already groups across every list by list or date.

---

## Deliberately excluded

Openlist focuses on personal, local-first workflows. These features are outside its current scope:

| Feature | Why |
|---|---|
| Voice AI ("Talk") | Outside the local task-management scope |
| AI Meeting Notes, AI Chat, Make AI, email/Slack summarization | Requires online AI services |
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
  Editor/      the list document's engine: OutlineEditor, OutlinePolicy (its
               rules), BlockTextView (AppKit-backed), MarkdownInputRules,
               BlockDragAndDrop
  Next/        Openlist Next shell: sidebar, screens, rows, the list document,
               inspector, calendar, overlays, settings, Workbench (shared UI
               state and actions), and the design tokens (NextTheme, NXEditor)
  Views/       RootView, menus, the Work panel, calendar history, shared pickers
Shared/        ListAccent, WidgetSnapshot, WidgetRoute, WidgetActions,
               WidgetIntents, AppGroup, Fonts   (app + widget)
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

SwiftUI's `TextEditor` cannot express what an outliner needs — Return that finishes a
line and opens the next, ⇥ that nests it, ⌫ that steps it out or turns it into text,
arrow keys that walk between lines. Each line therefore hosts a bare `NSTextView`
(explicit TextKit 1, so `sizeThatFits` can measure synchronously) and `OutlineEditor`
arbitrates the keys. `OutlineEditor` owns the caret, the `/` menu and every
structural edit under the design's rules (`OutlinePolicy`): its indent, Return,
Backspace and drag rules, and one undo step per line edited. It knows nothing about
how lines look: `NXDocumentOutline` in `Next/` draws every list, and the Inbox shown
as a document, as the Next design's document, its text set in `NXEditor`'s metrics.
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
eaten as dates, `9 p.m.` parsing as 09:00, monthly series sticking on the 28th
after a February, and every-N-weeks drifting across a 53-week year. "tonight"
reads as today with no time, as the capture design does.

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
Quick Add instead of the main window.

`Tools/add-widget-target.py` regenerates the widget target in the project file and
is idempotent.

### Reminder scheduling and recovery

A task’s reminder time is saved intent. Openlist reports **Accepted by macOS**
only after the notification center returns a matching pending request for that
saved task occurrence. This does not prove that an alert was displayed: Focus,
notification preferences, and macOS delivery policy still apply. Local scheduling
status is rebuilt from the saved library and OS inventory after launch; it is not
synced as a task fact.

Task details and Settings → Notifications show permission problems and scheduling errors.
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
Notification clicks wait for bootstrap and the main window, then open the task as
a search result does, on its list or the Inbox with its row focused, if it's drawn,
and its inspector open, unfolding nothing; or they explain that the subject is
unavailable. Review fixtures disable actual notification operations and
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
Trash keeps content indefinitely; nothing is emptied automatically. A task
entry shows where it came from and when it was deleted; a list entry shows its
item count and deletion time. Restore keeps
original IDs, rich notes, nested content, files, labels, completion and list
ownership. Tasks in Trash are excluded from active views, search, widgets and
reminders. Only eligible future reminders resume after restoration.

An independently deleted child stays a separate Trash item when its parent or
list is later deleted. Restoring the parent restores only the content deleted
with it. If the original parent or list is unavailable, Restore puts the item
in a pinned **Recovered items** list (the one there is, or a new one) and says
where it came from; that provenance is stored separately and never rewrites the
original notes. Undo sends it back to Trash and removes a Recovered items list it
made once that list is empty again. Archived lists keep their archive state.

**Hold to erase** and **Hold to empty Trash** act after a press and hold
(VoiceOver, which can't hold, asks in a sheet instead) and remove only files with
no remaining live or retained references. These actions cannot be undone. Empty
lines the document takes away and undone captures use structural cleanup and
session Undo; they do not fill Trash. **Delete everything…** in Settings → Data
permanently removes both active content and Trash. Library backups (format 5)
include Trash and its media, list covers and list ownership; formats 1–4 can
still be restored. A restore already staged by an older app must be cancelled
and prepared again from the original backup.
