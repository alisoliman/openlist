# Openlist Next v2 — native implementation notes

Source of truth: `body.html` (markup) and `design.jsx` (logic) in this folder.

## Architecture

- `openlist/Next/` holds the redesigned UI. Existing views remain for features the
  design doesn't cover (document editor, settings window, sheets for list move etc.).
- `NextTheme` — tokens (paper #FCFBFA, sidebar #F1EEEA, inspector #F7F5F2, ink #17161A,
  semantic colours), Instrument Serif (bundled, `Resources/Fonts`), density, motion.
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
- Modal flags reuse `navigator.isSearchOpen`, `navigator.isCommandPaletteOpen`,
  `env.taskCaptureRequest` so menu commands keep working.
- New route `.settings` for the in-window design Settings page (full Settings window stays
  reachable via "More settings…").

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
