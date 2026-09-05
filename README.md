# Openlist

A macOS clone of the personal side of [Superlist](https://www.superlist.com), built
with SwiftUI, SwiftData and the macOS 26 SDK (Swift 6 language mode).

Everything on Superlist's **Free** tier is implemented. Paid and gated features are
deliberately left out — see [Deliberately excluded](#deliberately-excluded).

---

## Running it

```bash
open openlist.xcodeproj      # then ⌘R
```

Requires Xcode 26 / macOS 26. The app is sandboxed and signs against the
`Y5UE64R7TQ.solimanali.openlist` App Group, which the widget extension shares.

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

### Also

Sidebar sections (create, rename, collapse, drag lists between them), list icons
and colours, per-list sort order, Markdown export, light/dark/system appearance,
Dock badge, and full local-first storage — the app has no network code at all.

Per-list *grouping* was cut rather than shipped half-working: grouping a rich
document that mixes headings, notes and tasks has no well-defined meaning, and
the Tasks screen already groups across every list by date, list, label or
priority.

---

## Deliberately excluded

These are Superlist's paid tiers or inherently collaborative, so they are out of
scope for a personal clone:

| Feature | Why |
|---|---|
| Voice AI ("Talk") | Basic tier and above |
| AI Meeting Notes, AI Chat, Make AI, email/Slack summarisation | Super tier |
| Integrations (Gmail, Slack, GitHub, Figma…) | Basic tier and above |
| Sharing, real-time collaboration, assignees, comments, voice messages | Not the personal side |
| Unlimited-lists / storage caps | Pricing mechanics, not features — lists here are uncapped |

---

## Layout

```
openlist/
  Model/       Block, TaskList, TaskLabel, SidebarSection, Attachment,
               ActivityEvent, Recurrence
  Services/    Store (+Blocks, +Tasks), BlockTree, DateParser,
               RecurrenceEngine, RichTextCodec, MediaStore, MarkdownExporter,
               NotificationService, QuickCaptureHotKey, WidgetSnapshotPublisher
  Editor/      BlockTextView (AppKit-backed), DocumentView, BlockRowView,
               SlashMenuView, MarkdownInputRules, BlockDragAndDrop
  Views/       RootView, SidebarView, screens, pickers, palette, settings
  Design/      Theme
Shared/        ListAccent, WidgetSnapshot, AppGroup   (app + widget)
OpenlistWidget/  WidgetKit extension
Config/          entitlements and the extension Info.plist
Tools/           LogicChecks/ and TextChecks/, widget-target generator
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
./Tools/run-logic-checks.sh
```

Compiles the pure-logic sources against a set of assertions — 65 checks covering
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

`Tools/screenshot.sh out.png ['keystroke "2" using command down' ...]` captures
the running app's window and can drive it with keystrokes first, so UI changes
can be verified rather than assumed. It is window-scoped — it never grabs the
rest of the desktop — and needs Screen Recording (capture) plus Accessibility
(keystrokes) granted to the terminal app. `OPENLIST_WINDOW=front` targets
Settings or Quick Add instead of the main window.

`Tools/add-widget-target.py` regenerates the widget target in the project file and
is idempotent.
