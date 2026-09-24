# Openlist Next v2 — native implementation notes

Source of truth: `body.html` (markup) and `design.jsx` (logic) in this folder.

## Architecture

- `openlist/Next/` holds the redesigned UI. Existing views remain for features the
  design doesn't cover (document editor, sheets for list move etc.).
- `NextTheme` — tokens (paper #FCFBFA, sidebar #F1EEEA, inspector #F7F5F2, ink #17161A,
  semantic colours), Instrument Serif (bundled, `Shared/Fonts`, so the widget has it too), density, motion.
- `Workbench` (@Observable, on AppEnvironment) — design interaction state: keyboard focus,
  visible order, completion dwell (`closing`), fresh/restored/flying rows, sidebar pulse,
  tray, session change log, inbox triage (kept/reviewed), G-prefix.
- `Workbench+Actions` — every design action (done, today, tomorrow, star, plan, priority,
  labels, move, trash, restore, keep, schedule, fit) goes through here: mutation via Store,
  undo registered on the window UndoManager (snapshot-based where Store has none),
  change-log entry, tray.
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
  target, as the row menu's do. Its key equivalents all carry a modifier, since a bare letter
  would fire while typing: ⌘D Mark as Done or Reopen (kept as the one key that completes a
  task while its line is being written), ⌃T/⌃M due today/tomorrow, ⇧⌘S Star. Help ▸
  Keyboard Shortcuts (⌘/) lists the design's single keys with the keys the list document
  and menus handle. Work ▸ Start Selected Task, Stop and Complete run `workbench.startWork`,
  `stopWork` and `finishWork`, as Task ▸ Start Working and the notch's ✕ and ✓ do.
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
  `OutlineEditor` engine under its `.nextDocument` policy, tasks on `NXTaskRowChrome` (the
  Next row's chrome with the live text as its title) and the other kinds in the same
  language. Done top-level tasks leave for the Completed group below. Each line's edit is
  one undo step with the design's label and a change-log entry. The Tasks presentation is
  the same document showing only its tasks. `Navigator.documentListID` (any list, and the
  Inbox shown as a document) and `documentOwnsEditorCommands` replace `hasDocumentEditor`.
- The inspector's "Subtask of" crumb and Subtasks section follow the design; Add subtask
  writes the new line in the list document (`Workbench.addSubtask`,
  `OutlineEditor.appendSubtask`). The Inbox's document mode is the same list document under
  the Inbox header. Native extras on the list page: the "…" options menu, the title renamed
  in place, the description, cover and nested lists, a drag grip on every line (drops go
  through `BlockDragAndDrop` under the design's nesting rules, and onto sidebar lists), and
  search reveal scrolling in `NXPage`. Open notes are remembered per task on this Mac.
- Where the list document departs from the design, to keep native data safe: a done
  top-level task stays in the document while a task under it is open; a line left empty
  goes only when it was new or emptied in its edit and holds nothing but text (Backspace
  also takes one that was already empty); a line's undo step leaves alone what anything
  else changed in its task meanwhile (`EditorEditSession`); a new line opens whatever
  heading or task folds it away. Headings and text take no key focus after Escape, as in
  the design; Return writes them again and J/K step to the tasks beside them.
- Inbox triage skips a subtask while an open task above it waits, as that task's card
  carries it; one under done tasks only is triaged as its own card.

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
