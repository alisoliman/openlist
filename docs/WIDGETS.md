# Widgets

Implemented 24 September 2026 from the "Openlist — macOS widgets" design
([mockup](design/openlist-widgets/mockup.png), [design logic](design/openlist-widgets/mockup-logic.js);
the same design's full export, with its markup and sample props, is in
[openlist-next-v2/widgets](design/openlist-next-v2/widgets/)). The deployment
target was raised to macOS 27.0 in the same change, which lets widget intents run
in the app process.

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

- **Ticking off.** A checkbox is a toggle that runs `ToggleTaskIntent`. The
  system draws it ticked the moment it is tapped, as the design's closing disc,
  and dims the row beside it while the intent runs in the app; the row settles
  out with the reload that follows. A tick queued for the app (see the fallback
  queue below) draws the design's faded, struck-through row until the app
  applies it. The tick goes through the window's own completion, so the tray
  reports it, the change log lists it and Undo takes it back, as for a tick in
  the window, and the task's open subtasks close with it. Actions carry the
  task's occurrence, so a stale tap never completes the next occurrence of a
  repeat. In medium and large widgets, tapping a row's title opens the task.
- **Work.** Start, Pause, Resume and Done drive the same session as the toolbar's
  work notch, through the same actions as its buttons. The clock ticks by itself
  through the system's live stopwatch text. Start never opens the Work panel, and
  records whatever the plan says, as Start in the app does; one that fails to save
  says so in the app's tray. A widget never switches what you are recording: a
  Start while other work runs is ignored. Every work button names the session it
  was drawn for, so a stale widget cannot pause or finish different work.
- **Links.** Widgets open `openlist://widget/…` routes (`openlist-dev://` in Dev
  builds): capture (optionally into a list, or due today from the Today widget),
  Inbox, Triage, Today, Calendar, Activity, a task, or a list. The app claims these
  before item-link handling. Screen links wait until the library and main window
  are ready, so a cold launch lands on the link's screen, then bring Openlist
  forward. Calendar opens on today's range, whichever range it was left on; Triage
  shows the Inbox as triage for that visit, and Inbox follows this Mac's choice.
  A task or list link lands as an item link does: a task opens on its list with
  its row focused and the inspector open, and the folded parents and done lines
  on its path show for the visit, since widgets list subtasks and completed
  tasks the page may be hiding. Quick Add opens the floating Quick Add card over
  the app you are in, on the widget's list, without waiting for the main window.
  macOS may make Openlist the active app as it opens the widget's link, and show
  its window behind the card; the card then gives focus back to the app you were
  in, and hides Openlist again if it was hidden, when it closes. With VoiceOver
  on, Openlist becomes active on purpose, so VoiceOver can read the card.
- **Counts.** Late goes by day, as on the app's Today screen: a task is overdue
  once its due day has passed, so a timed task whose time has passed today is
  still due today. Large Today keeps two of its rows for work due today when
  there is that much (three of five overdue at most), and the app publishes
  each group's rows separately, so a long backlog never pushes the day's own
  work out. Done today counts what the app's Today screen does: tasks completed
  today. A reopen or Undo takes one away, and a repeat that rolls forward is
  open again. Activity counts the completions that still stand, repeats
  included, like the Activity screen: an Undo or a reopen takes one back. The
  Inbox count is the Inbox badge's: a subtask goes with the open task above it,
  and one under done tasks only counts on its own. A List widget's rows follow
  the list's page, sorted by its Sort within each run of tasks between headings.
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
   blocks, the meetings read for the whole week, before today included, and read
   again whenever the calendars reload: on an EventKit change, and on the
   calendar coordinator's refresh at least every five minutes while the app
   runs), the work session in absolute times (so heartbeats don't change it),
   the activity window, and tomorrow's rows so the widgets can start the next day
   even when the app hasn't run since midnight. A sorted list's order reads its
   whole document, and is kept until the list's tasks, the blocks above them,
   its top-level blocks or its Sort change. The publisher skips unchanged
   snapshots and reloads only the widget kinds a change affects. It refreshes
   after saves, when the calendar's plan or work session changes
   (`CalendarCoordinator.onWidgetStateChange`), and when the accent, serif titles,
   the first weekday or the calendars reload. Changes to the plan alone are
   throttled while the app is in the background, so a moving block doesn't spend
   WidgetKit's reload budget.
2. **Intents** (`Shared/WidgetIntents.swift`). The intents are compiled into both
   targets with `allowedExecutionTargets = .main`. The system performs them in the
   app, launching it in the background if needed. `WidgetCommandProcessor`
   validates each command, applies it through the `Workbench`'s actions
   (`WidgetTaskActions`), the ones the window's rows and work controls use, and
   rewrites the snapshot before the intent returns.
3. **Fallback queue** (`Shared/WidgetCommand.swift`). If an intent is ever
   performed in the extension, the command goes into a coordinated App Group file,
   a Darwin notification wakes the app, and every widget reloads to draw it. The
   app drains the queue on launch, on activation and on that notification. The
   widget draws queued commands over the snapshot. A newer tap on the same task
   supersedes an older one. Start, Pause and Resume older than two minutes are
   dropped rather than replayed, and the widget stops drawing them at the same
   moment; ticks, unticks and Done wait up to six hours. At launch the app also
   moves onto the queue any taps an earlier build's widget left in its own
   `widget-actions` folder, and removes the folder.

Time-driven changes are timeline entries prepared in advance. Inbox ages
advance, Up Next counts down every minute and the Agenda's now line moves every
quarter hour, all without the app running. Tasks turn late at the reload a
minute past midnight, when the widgets also start the new day from the rows the
app published for tomorrow.

Instrument Serif lives in `Shared/Fonts`, so both bundles carry it. The widget
registers it at launch and also declares it with `ATSApplicationFontsPath`.

## Verification

- `Tools/run-widget-checks.sh`: snapshot coding and tolerant decoding, links,
  command queue, pending-command overlay, the Up Next state machine, agenda and
  heatmap layout, wording, and timeline dates.
- `Tools/run-widget-snapshot-checks.sh`: the publisher against a real store and
  calendar coordinator.
- `Tools/run-widget-action-checks.sh`: every command, stale taps, the queue and its
  Darwin signal, an earlier build's queue, and link routing on cold launch. It
  drives the processor through a stand-in for the `Workbench`'s actions.
- `Tools/run-widget-workbench-checks.sh`: the processor through the app's own
  `Workbench`: a tick's subtasks, date, change log, tray and Undo, the window's
  completion dwell, and the work controls. It builds the whole app target, so it
  is the slowest suite to compile.
- `Tools/render-widgets.sh [kind…]` draws every widget, state and mode to
  `build/widget-renders`. It renders at the design's sizes, for comparison with the
  mockup, and at the sizes this Mac's widget host reports (small 164 pt, medium
  344 × 164), to catch truncation.

## Departures from the design

Where WidgetKit, or the app, sets other terms than the design:

- Only a row's circle ticks the task, so a tap elsewhere can't tick one the
  widget can't undo. While a tick's intent runs, the system dims the row beside
  its circle (`invalidatableContent`) in place of the design's faded,
  struck-through row, which only a tick queued for the app draws.
- A small widget can only open its own link, so small Today's rows open Today,
  not the task.
- A tick queued while Openlist is quit stays drawn closing until the app applies
  it, where the design's row settles out after its dwell; the counts already
  show it. A task published done and reopened in the widget goes after the
  list's open rows until the app publishes the list's own order, and leaves the
  Agenda, as a reopened task leaves the calendar.
- Start, Pause and Resume that reach the app over two minutes after the tap are
  dropped, where the design's always act; a queued tick and its untick cancel
  out.
- Large Today's New task opens Quick Add as the app's Today add row does: a
  task typed without a date is due today, so it shows in the widget. The
  design's footer opens plain Quick Add.
- Large List's add chip names the whole list ("Add to Weekend in Kyoto"), since
  lists have no short names, where the design's names a short one ("Add to
  Kyoto"); a long name truncates.
- A List widget whose chosen list is gone shows the first list after the Inbox,
  as an unconfigured one does, or the Inbox when that is the only list. With no
  lists at all it reads "No lists yet"; the design always has a list.
- Quick Add counts an Inbox capture's first hour in five-minute steps ("now",
  "15m"), where the design's ages start at "2h".
- Activity and Summary's week count every completion that still stands, a
  repeat's too, as the Activity screen does, while Today's "N of M done" and
  Summary's Done tile count the tasks sitting done today, as the app's Today
  does. A repeat finished today counts in the first and not the second, where
  the design has one count.

## Remaining validation limits

Ad-hoc Dev builds cannot share the App Group, so their widgets show the Open
Openlist prompt; use `Tools/build-dev.sh --signed` to exercise real data. The
intent path into the app process, the live stopwatch text and the desktop host's
use of the bundled serif were built to Apple's documented behavior, but no widget
was placed on the desktop by hand in this pass.
