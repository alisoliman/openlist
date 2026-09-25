# Widgets

Implemented 24 September 2026 from the "Openlist — macOS widgets" design
([mockup](design/openlist-widgets/mockup.png), [design logic](design/openlist-widgets/mockup-logic.js)).
The deployment target was raised to macOS 27.0 in the same change, which lets
widget intents run in the app process.

Seven desktop widgets replace the earlier Today, Summary and Lists widgets. The
Today, Summary and List widgets keep their kind identifiers, so widgets already on
the desktop upgrade in place.

| Widget | Kind | Sizes | Shows |
|---|---|---|---|
| Today | `OpenlistToday` | S · M · L | Overdue and due-today tasks, progress ring, "+ New task", done today |
| Up Next | `OpenlistUpNext` | S · M | NOW / NEXT / WORKING / PAUSED, Start, Pause and Done, later today |
| Quick Add | `OpenlistQuickAdd` | S · M | Capture; medium adds the newest Inbox captures and Triage |
| List | `OpenlistLists` | M · L | A chosen list (configurable), with an optional completed section |
| Agenda | `OpenlistAgenda` | L · XL | Today's meetings and planned blocks, or the week, with a now line |
| Summary | `OpenlistSummary` | S · M | Due today, overdue, Inbox, done, and this week's completions |
| Activity | `OpenlistActivity` | S · M | 10 or 21 weeks of completions, streak, today, week and month |

## Behavior

- **Ticking off.** A checkbox runs `ToggleTaskIntent`. The row shows its closing
  state straight away and settles out when the app republishes. Actions carry the
  task's occurrence, so a stale tap never completes the next occurrence of a
  repeat. Tapping a row's title opens the task.
- **Work.** Start, Pause, Resume and Done drive the same session as the toolbar's
  work notch. The clock ticks by itself through the system's live stopwatch
  text. Start never opens the Work panel. A Start the calendar refuses (outside
  the list's hours, or during a meeting) changes nothing, and the widget shows the
  real state after it reloads. Every work button names the session it was drawn
  for, so a stale widget cannot pause or finish different work.
- **Links.** Widgets open `openlist://widget/…` routes (`openlist-dev://` in Dev
  builds): capture (optionally into a list, or due today from the Today widget),
  Inbox, Triage, Today, Calendar, Activity, a task, or a list. The app claims these
  before item-link handling, and waits until the library and main window are ready
  so a cold launch lands on the link's screen. The main window comes forward with
  Quick Add, because URLs are delivered to the main window scene.
- **Counts.** Done today counts what the app's Today screen does: tasks completed
  today. A reopen or Undo takes one away, and a repeat that rolls forward is open
  again. Activity counts every completion, repeats included, like the Activity
  screen, and a reopened completion stays in its history.
- **Rendering modes.** Every widget is designed for light, dark and the desktop's
  in-background (vibrant) mode, where accents collapse to white. Checkboxes,
  rings, bars and heatmap cells are the accentable parts.
- **List configuration.** The List widget's Edit Widget sheet offers every active
  list, with its path for nested lists, and a Show completed switch. An unset (or
  since removed) list falls back to the first list after the Inbox.

## How it works

The widget never opens the SwiftData store. There are three channels between the
app and the extension:

1. **Snapshot** (`Shared/WidgetSnapshot.swift`). `WidgetSnapshotPublisher` builds a
   JSON snapshot from the store, the calendar coordinator and settings, and writes
   it to the App Group. It holds today's rows and counts, the Inbox, every active
   list with its open and completed rows, the week's agenda (meetings and planned
   blocks), the work session in absolute times (so heartbeats don't change it),
   the activity window, and tomorrow's rows so the widgets can start the next day
   even when the app hasn't run since midnight. The publisher skips unchanged
   snapshots and reloads only the widget kinds a change affects. Changes to the
   plan alone are throttled while the app is in the background, so a sliding
   block doesn't spend WidgetKit's reload budget.
2. **Intents** (`Shared/WidgetIntents.swift`). The intents are compiled into both
   targets with `allowedExecutionTargets = .main`. The system performs them in the
   app, launching it in the background if needed. `WidgetCommandProcessor`
   validates each command, applies it through the same Store and calendar paths
   the app uses, and rewrites the snapshot before the intent returns.
3. **Fallback queue** (`Shared/WidgetCommand.swift`). If an intent is ever
   performed in the extension, the command goes into a coordinated App Group file,
   and a Darwin notification wakes the app. The app drains the queue on launch, on
   activation and on that notification. The widget draws queued commands over the
   snapshot. A newer tap on the same task supersedes an older one. Work commands
   older than two minutes are dropped rather than replayed, and the widget stops
   drawing them at the same moment; ticks wait up to six hours.

Time-driven changes are timeline entries prepared in advance. Tasks turn late on
time, Inbox ages advance, Up Next counts down every minute and the Agenda's now
line moves every quarter hour, all without the app running.

Instrument Serif lives in `Shared/Fonts`, so both bundles carry it. The widget
registers it at launch and also declares it with `ATSApplicationFontsPath`.

## Verification

- `Tools/run-widget-checks.sh`: snapshot coding and tolerant decoding, links,
  command queue, pending-command overlay, the Up Next state machine, agenda and
  heatmap layout, wording, and timeline dates.
- `Tools/run-widget-snapshot-checks.sh`: the publisher against a real store and
  calendar coordinator.
- `Tools/run-widget-action-checks.sh`: every command, stale taps, the queue and its
  Darwin signal, and link routing on cold launch.
- `Tools/render-widgets.sh [kind…]` draws every widget, state and mode to
  `build/widget-renders`. It renders at the design's sizes, for comparison with the
  mockup, and at the sizes this Mac's widget host reports (small 164 pt, medium
  344 × 164), to catch truncation.

## Remaining validation limits

Ad-hoc Dev builds cannot share the App Group, so their widgets show the Open
Openlist prompt; use `Tools/build-dev.sh --signed` to exercise real data. The
intent path into the app process, the live stopwatch text and the desktop host's
use of the bundled serif were built to Apple's documented behavior, but no widget
was placed on the desktop by hand in this pass.
