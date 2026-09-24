# Openlist Next v2 — native implementation notes

Source of truth: `body.html` (markup) and `design.jsx` (logic) in this folder.

## Architecture

- `openlist/Next/` holds the UI. `openlist/Editor/` is the list document's engine and its
  AppKit-backed line text; `openlist/Views/` keeps the sheets, pickers and notices the Next
  screens host where the design has none of its own (list move and delete, template copy,
  the shortcuts sheet, due, repeat and reminder pickers).
- `NextTheme` — tokens (paper #FCFBFA, sidebar #F1EEEA, inspector #F7F5F2, ink #17161A,
  semantic colours), Instrument Serif (bundled, `Shared/Fonts`, so the widget has it too), density, motion.
  `NXEditor` (`NextEditorTypography.swift`) holds the document text's metrics and ink as
  NSFonts and NSColors, apart from `NX` so the rich-text codec needs no SwiftUI tokens.
- `Workbench` (@Observable, on AppEnvironment) — design interaction state: keyboard focus,
  visible order, completion dwell (`closing`), fresh/restored/flying rows, sidebar pulse,
  tray, session change log, inbox triage (kept/reviewed), G-prefix.
- `Workbench+Actions` — every design action (done, today, tomorrow, star, plan, priority,
  labels, move, trash, restore, keep, schedule, fit) goes through here: mutation via Store,
  undo registered on the window UndoManager (snapshot-based where Store has none, putting
  back only the fields the step changed), change-log entry, tray. So do the native extras
  that edit the same things: the inspector's Schedule, Repeat, Reminder and label popovers
  (with tray), its title and note, and a list's title and description (edits: logged, no tray).
- Completion dwell defers the real `store.toggleCompletion` until dwell+300ms; Undo during
  dwell cancels. Pending closings flush on termination.
- `NextKeyMonitor` — NSEvent local monitor implementing the global key model when not typing.
- Shell replaces NavigationSplitView: custom sidebar (236), 52pt toolbar with drag gesture,
  inspector overlay (360), tray, selection bar, capture/search/palette overlays, work notch.
- Modal flags reuse `navigator.isSearchOpen` and `navigator.isCommandPaletteOpen`; ⌘N goes
  through `env.presentTaskCapture()`, which opens the workbench capture
  (`workbench.openCapture`), so menu commands keep working.
- The macOS menus are native extras. Task ▸ names its items as the palette and row menu do
  and runs the Workbench's actions on the tasks its commands reach (in a list document the
  line being written, else the workbench targets in that list); its titles read every
  target, as the row menu's do, so both say Reopen or Unstar when every target is done or
  starred (the palette and bulk bar keep the design's Star). Its key equivalents all carry
  a modifier, since a bare letter would fire while typing: ⌘D Mark as Done or Reopen (kept
  as the one key that completes a task while its line is being written), ⌃T/⌃M due
  today/tomorrow, ⇧⌘S Star. Help ▸ Keyboard Shortcuts (⌘/) lists the design's single keys
  with the keys the list document and menus handle. Work ▸ Start Selected Task, Stop and
  Complete run `workbench.startWork`, `stopWork` and `finishWork`, as Task ▸ Start Working
  and the notch's ✕ and ✓ do. View ▸ Collapse All folds only what the design's carets fold
  (tasks with lines under them, headings with a section); Expand All opens every fold, one
  an older list left on a list item too. A line that becomes a heading, or stops being one,
  opens, so such a fold never hides a new heading's section (the design keeps a block's
  flag, which folds a heading turned into a block and back again).
- Too narrow for the whole toolbar, the crumb truncates first, down to its first 80 pt,
  then the Undo label, which at last leaves only its icon; Actions and New task keep their
  labels.
- Reduce Motion (the setting or the system's) fades the inspector, the notch, the bottom
  bars and the overlay cards in rather than sliding them, as its hint says, where the design
  only shortens the slides.
- New route `.settings` for the in-window Settings page: the design's groups, then every
  other preference. ⌘, and Openlist ▸ Settings… open it; there is no Settings window.
- Quick Add from anywhere is ⇧⌥Space, not the design's ⌥Space: ⌥Space types a non-breaking
  space in every text field, so a global hot key on it would take that from every app. The
  Settings hint, menu bar, shortcuts sheet and README all name ⇧⌥Space.
- Trash keeps one entry per trashed task or list, not a row per subtask: the subtasks
  restore and erase with their task, whose row ends "· with N subtasks", and the sidebar
  counts entries.
- Lists are the design's document (`NextDocument.swift`): `NXDocumentOutline` draws the
  `OutlineEditor` engine, which keeps the design's rules (`OutlinePolicy`), tasks on `NXTaskRowChrome` (the
  Next row's chrome with the live text as its title) and the other kinds in the same
  language. Done top-level tasks leave for the Completed group below. Each line's edit is
  one undo step with the design's label and a change-log entry. The Tasks presentation is
  the same document showing only its tasks. `Navigator.documentListID` (any list, and the
  Inbox shown as a document) and `documentOwnsEditorCommands` replace `hasDocumentEditor`.
- The inspector's "Subtask of" crumb and Subtasks section follow the design; Add subtask
  writes the new line in the list document (`Workbench.addSubtask`,
  `OutlineEditor.appendSubtask`), after the task's last line and at its depth, as the
  design's does, but never past two levels and only under a task or list item, which
  older outlines can break. The Inbox's document mode is the same list document under
  the Inbox header, so unlike the design (whose Inbox has no document) an Inbox task lists
  Subtasks while the Inbox shows as its document, or once it has some; its Add subtask shows
  the Inbox as its document. Native inspector extras: the title and note are edited in place
  and files kept with the task. As the design, the note shows only when there is one; until
  then a quiet "Add a note" row stands in, with "Attach a file" beside it until the task has
  files, when Files shows. Files dropped anywhere on the panel are attached. The Schedule
  popover fits its section, up to 510pt, and its date and time controls are Next pills.
  Native extras on the list page: the "…" options menu, the title renamed in place, the
  description, cover and nested lists, a drag grip on every line (drops go through
  `BlockDragAndDrop` under the design's nesting rules, and onto sidebar lists, which drag
  on a private type of their own that no line takes), and search
  reveal scrolling in `NXPage`. The "…" menu's Copy as Markdown, beside Export as Markdown…,
  puts the Markdown Export writes on the clipboard (`MarkdownExporter.copyToPasteboard`) and
  says "Copied “List” as Markdown" in the tray. Its Hours picks the Work or Personal hours
  Plan and Start working use for the list, which the design takes from its section; the
  header's subtitle stays the design's "N open · Section". Open notes are remembered per
  task on this Mac.
- Today's, a list's and a label's Completed groups fold as one, as the design's
  `completedOpen`: the last fold shows on every screen (`NXCompletedFold`). Until the user
  folds one, each opens as its setting says: a list's own Completed Tasks (a native extra),
  else Show completed tasks. Deviation: they fold with Show completed tasks on too, where the
  design keeps them open, and changing that setting drops the fold, so every group opens as
  the setting now says (the design keeps an opened fold open when it goes off). A list's new
  Completed Tasks shows on that list at once; Today, labels and other lists keep the fold
  until the next one.
- A repeat reads in macOS sentence case ("Every day", "Every weekday"; a day's name keeps
  its capital, "Every Wednesday"), where the design title-cases a captured one ("Every
  Day"). The same words show in the inspector, the tray, Markdown export and MCP.
- Back and Forward, a native extra, return a page to where it was scrolled when it was left:
  each visit in the navigator's history keeps its own offset, which `NXPage` takes on
  appearing. Any other arrival (the sidebar, a link, a new visit from the history) opens the
  page at the top, or on what a search hit or link reveals.
- Where the list document departs from the design, to keep native data safe: a done
  top-level task stays in the document while a task under it is open; a line left empty
  goes only when it was new or emptied in its edit and holds nothing but text (Backspace
  also takes one that was already empty); a line's undo step leaves alone what anything
  else changed in its task meanwhile (`EditorEditSession`); a new line opens whatever
  heading or task folds it away. Headings and text take no key focus after Escape, as in
  the design; Return writes them again and J/K step to the tasks beside them.
- Inbox triage skips a subtask while an open task above it waits, as that task's card
  carries it; one under done tasks only is triaged as its own card.
- Widgets (`OpenlistWidget/`) depart from `widgets/` where WidgetKit sets the terms. Only a
  row's circle is its toggle, so a tap elsewhere can't tick a task the widget can't undo;
  while the tick's intent runs the system dims the rows beside their circles
  (`invalidatableContent`) in place of the design's faded, struck-through row. In medium and
  large a row's title and list line open the task; a small widget takes only its own link,
  so small Today's titles open Today. Quick Add's Triage link shows the Inbox as triage for
  that visit even where this Mac shows it as a document; its Inbox link follows this Mac's
  choice. macOS may make Openlist active as it opens a widget's link, bringing its window
  forward behind Quick Add's card; the card then gives focus back to the app you were in,
  and hides Openlist again if it was hidden, when it closes.
- Calendar: running work past its slot follows the design's overrun (the slot grows to the
  next quarter plus 15 min, later placements that day move out of its way, saved and
  undoable, stopping only at meetings and breaks; Undo still moves them back after Pause,
  Stop or Done). Where it departs, to keep the list's hours: the block also stops growing
  at their end, and a moved task stays inside its own list's hours that day (the design
  allows up to 21:00), or where it is when none are left. Work with no slot, which the
  design never grows, is drawn from when it started up to its estimate or the next placed
  task, then grows and moves later placements as a slot does. Time away from the Mac, for
  work that tracks away, stops counting at the next pinned task instead of moving it.
  Resumed work reads "working" until it grows again. Busy holds of 20 h or more (Out of
  office) aren't drawn as meetings but still keep Plan and the planner away, so the day's
  header names them.
- Calendar week: the design's week always has today on a Wednesday. Natively, Plan keeps to
  the week around today while it has hours long enough for the task (the design's "No free
  slot this week"), then goes on into the next week, as a deferral past it gets its own. A
  block landing past the days shown moves the Calendar's range there, and the header's
  ‹ Today › steps the range a day, three days or a week at a time.
- The tray is the one passing feedback, as in the design, and VoiceOver hears each message
  (with "Undo with Command-Z" when it offers Undo). Completions made outside Next's rows
  (menu bar, calendar, notifications, MCP) report there too, their Undo the Store's
  completion entry. One-off refusals (`Store.refuse`: a drop the document's rules don't
  allow, rearranging a sorted list) pass there; what needs dealing with (saving, sync,
  links, label maintenance, Trash failures, failed undos) stays a notice card, all of them
  in one place under the toolbar.
- Native extras that snap like the design's actions, with Undo and a log entry: Delete List
  (`Workbench.trashList`, "Moved “…” to Trash" with Open Trash), Delete Label (sidebar and
  Settings; Undo puts it back where it sat on each task), Merge labels, a list's Icon &
  Colour…, and the task menu's Duplicate and Use as Template…. The menu's Copy Text and
  Copy Content and Subtasks (for Paste in an empty document line) only copy. An Undo or
  Redo of a label or list change that fails says so in the tray, keeps the log as it was
  and leaves the stack. Deviation: a merge undoes in turn on the window's stack, by ⌘Z or
  the tray, where the old "Undo merge" card took back the latest merge out of order,
  keeping later changes. Deviation: "Confirm before deleting a list" stays a preference
  (on by default), asked in a Next sheet; the design asks nothing, as Undo covers it.
- A route to a list or label deleted since (Back to a list now in Trash) shows the dashed
  empty box with Open Trash, Open Lists or Open Tasks. A search hit in the note of a heading
  or text line (only native data gives those notes) shows that note under the line as the
  design's note block, the match in the accent.
- The editor's kinds past the design's five (Heading 3, Numbered, Quote, Code, Divider,
  Image) are a native extra: their lines draw and edit in the document, the Turn into
  card brings them up for their names after "/" (with no query it shows the design's
  five under its one header, and a single letter filters the five by label as the
  design's does), and a line's Turn Into menu lists them all. From the second letter
  the editor's search words bring kinds up too, so `/h1`, `/todo` or `/hr` find Heading,
  Task or Divider, and a query can list a kind whose label doesn't hold it. Only the
  design's prefixes (`# `, `## `, `- `, `* `, `[ ] `, `[] `, `> `) convert a line as it's
  typed, and only the design's five show one in the card; the editor's inline `**bold**`,
  `_italic_`, `~~strike~~` and `` `code` `` rules still style it, as the Format menu does.
  ⇧↩ types a soft break only in a code line, and a code line keeps its indent where the
  others are stored trimmed, as the design's commit does, once the caret leaves them.
  The card opens above its line when it wouldn't fit under it on the visible page, and a
  row the pointer moves onto takes the highlight.

## Status checklist

- [x] Theme tokens, font, settings props
- [x] Workbench state + actions + undo + tray + change log
- [x] Key monitor
- [x] Shell: sidebar, toolbar, notch, inspector host, tray, selection bar, overlays host
- [x] Row + group components
- [x] Today, List, Label screens
- [x] Tasks screen (query + sentence)
- [x] Inbox triage
- [x] Inspector
- [x] Capture, Search, Palette
- [x] Calendar (grid, not planned yet, plan, planned now, overrun)
- [x] Lists gallery, Activity (+ Changes), Trash (hold), Settings
- [x] Build + native verification screenshots
- [x] List document: lines, carets, notes, Turn into, completed split, keys, undo and log
- [x] Inspector subtasks and "Subtask of", Inbox document mode, list options menu,
      title in place, drag grip, search reveal
