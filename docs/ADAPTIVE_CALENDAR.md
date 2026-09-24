# Adaptive calendar

Openlist plans task sessions around available hours and the busy time in connected
macOS calendars. Open **Calendar** in the sidebar or press **⌘3**. The **Day**,
**3 days** and **Week** control shows the same schedule at different scales, and
the arrows beside it step back or on by that range; **Today** returns to the range
around today. Browsing another range does not change the rolling plan. The
current time has a marker, and movement respects Reduce Motion.

## Put work into the plan

Open a task’s inspector and turn on **Plan for today**, choose **Task → Plan for
Today**, or press **P** on a selected row. Tasks with a deadline inside the next
four weeks also enter the plan automatically. Undated backlog stays unscheduled
until selected, deferred to a day, or given an explicit placement. A selection that overruns its
day carries forward until the task is completed or deselected.

Planning intent is separate from **Due**, **Star**, and reminders. Selecting a task
for today does not manufacture a deadline. Due dates still work as they did
before: a date without a time permits work through the end of that local day; a
date with a time is an exact cutoff. Existing starred work remains in Today but
starring alone does not automatically put it on the calendar.

The default estimate is **30 minutes**. Edit a task’s estimate in its inspector,
or change the inherited default in **Settings > Calendar**. **Use default**
removes an individual override. An estimate is the expected total active time for
the current occurrence, so previously recorded work reduces its remaining time.

The planner first considers deadlines at risk, then work selected for today,
then other upcoming deadlines. Earlier deadlines and task priority break ties;
priority orders tasks selected for today. Flexible work uses available slots,
with overflow moving into later days. Work can split into sessions with a
configurable **25-minute** minimum by default. Short tasks can use shorter slots.
Turn on **Keep task together** to require one uninterrupted session for the
remaining work.

## Available hours and meetings

Each list chooses **Work** or **Personal** under **Hours** in its header's "…" menu,
or in its menu in the sidebar.
Tasks inherit that choice. Calendar settings define separate weekly hours,
breaks, and date-specific overrides for both categories:

| Default | Available hours | Breaks |
| --- | --- | --- |
| Work | Monday–Friday, 09:00–17:00 | 12:00–13:00 |
| Personal | Every day, 18:00–21:00 | None |

Saturday and Sunday have no default work hours. Add multiple available intervals
or breaks to any weekday. An override replaces that date’s weekly hours **and**
breaks; an empty available-hours list means a day off. All hours use the Mac’s
current local time zone. Calendar week display follows Openlist’s existing
**Week starts on** preference. Internally, weekday keys use Foundation’s numbering
(Sunday = 1, Monday = 2, … Saturday = 7).

Choose **Connect macOS calendars** in Settings → Planning, then select calendars
from accounts already configured on the Mac. macOS presents its EventKit
**full access** permission because that is the system permission that permits
reading events. Openlist’s adapter only reads calendars and events: it has no
external-event creation, edit, save, or deletion path.

Selected events become fixed busy time, including all-day events. Canceled,
explicitly free, and personally declined events do not block task scheduling.
The adapter refreshes when EventKit reports changes, periodically while the app
runs, or when **Refresh calendars** is selected. Permission and loading problems
are shown rather than represented as a successfully connected calendar.

## Work must be explicitly started

A calendar block is a plan, not a running timer. Click **Start working** in task
details, choose **Task → Start Working**, or use **Start** on Calendar’s
**Planned now** banner. Starting always records, even outside the list’s
available hours or during a meeting: hours and busy time shape the plan and its
warnings, not whether work may start. Starting another task switches straight away, and the
tray offers Undo. While work records, the toolbar’s work notch keeps **Done** and
**Stop** available on every page; see [the work companion](WORK_COMPANION.md).

At a planned start, the **Planned now** banner offers one-click **Start**. If it
is ignored for five minutes, only the missed task moves into the next free gap;
the rest of the day stays steady. Missed time is never logged as work.

Recording continues past the estimate. A minute before the working block ends,
it grows to the next quarter hour plus **15 minutes**, clipped to the next fixed
boundary, and later flexible work moves out of its way. The tray reports each
extension with Undo, which puts the previous blocks back (or, once another change
has replaced them, plans them afresh); work keeps recording, and the block is not
grown again until Redo or the next start. Undo is offered only while that work is
still running. An optional
background notification offers **Complete task** near the estimated finish.
Reaching an estimate never marks a task complete.

Routine moves animate quietly. Background calendar nudges use silent macOS notifications
when notification permission is available; the in-app work notch remains
available without that permission.

When a meeting, a break, or another task’s pinned time leaves the working block
no more room, work keeps recording and the work notch names what
it is running into. The end of available hours only stops the block growing, as
the planner never places work past it. Blocks the running work runs over stay
where they were rather than being moved as missed; pausing replans them and the
remaining work into the next available slot. **Defer…** pauses work, removes that
occurrence’s explicit placements, and chooses the next day on which planning may
start. Its deadline stays unchanged, even when deferral leaves too little time before it.
Undo takes a deferral back, placements included; **Clear** ends one, keeping the
task selected for today once its day has come.

Lock, screen sleep, system sleep, and inactive user-session notifications pause
active work and offer **Resume** on return. **Track work away from this Mac** is
a per-task exception: elapsed work can continue while locked or asleep, up to the
next meeting, break, pinned time, or the end of available hours, where it pauses
as if the Mac had been left then. Leaving the Mac outside those hours or during
busy time pauses it at once. The block is not grown while away. Resume always
requires an explicit action. Quitting Openlist ends active tracking. After
an interrupted process or restart, an unfinished local session is closed at its
last saved heartbeat and a resume prompt is offered; elapsed time while the app
was absent is not silently recorded as work.

## Place a task or move its planned time

**Not planned yet**, beside the calendar, lists open tasks due soon or picked for
today that have no block. Its **Plan** button, and **Task → Find a Slot**, place
the task in the next free slot around meetings and your hours, as one change with
Undo in the tray. That placement is pinned. In the Work panel, **Later… → Move
planned time…** saves a preferred placement instead, which can yield to busy time,
deadlines and changes in remaining work; when it can’t be kept, a notice says
why. Neither changes the task’s due date.

Pins can conflict with meetings, other pins, active work, availability, breaks,
deadlines, or the **Keep task together** choice. A conflicting pin does not count
as safe deadline coverage. A missed pin stays on the calendar as **carried
forward**, and the task’s details show where the calendar has it, while unfinished
work is replanned; it is never retrospectively treated as an active session.
Active sessions cannot be moved or pinned while running.

Pins beyond the four-week horizon remain fixed and are rated outside the
plan. A pin crossing the horizon contributes only its in-horizon portion to
coverage; its remaining fixed time is not silently moved into today.

## Understand deadline coverage

The plan covers today and the following 27 local dates. It rates each task’s
coverage from its required and before-deadline minutes. The rating stays inside the
planner, as its sessions do: a task’s details show only where the calendar has it.

| Status | Meaning |
| --- | --- |
| Scheduled | All remaining work has enough conflict-free scheduled time, before its deadline when one exists. |
| Cannot fit before deadline | A deadline within the planning horizon has less safe time than the task needs. Overflow can still be placed after it. |
| Outside planning horizon | The deadline is beyond the rolling plan, or some remaining work cannot be safely placed within its available capacity. The explanation distinguishes these cases. |

A task with a distant deadline can be selected for today to schedule it earlier.
Stepping to a later range does not promise that tasks beyond the horizon have
already been planned.

Only a recurring task’s **current occurrence** is scheduled. Completing it records
that occurrence and advances the existing recurrence rule, after which the next
occurrence can enter the plan. A future-dated next occurrence becomes eligible
from tomorrow, unless explicitly selected for today. The calendar does not manufacture additional
future occurrences to forecast every repetition across four weeks.

## Completed work stays on the calendar

Every range retains completed occurrences with a checkmark, muted color, and
strikethrough. Tracked work occupies its actual recorded intervals, including
approved time corrections. Work completed without Start keeps its original
planned slots and says **Time not tracked**. Older records without saved slots
use a completion marker rather than inventing a duration.

Completed blocks do not reserve capacity. Finishing early immediately frees
remaining time, and reused time appears side by side with completion history.
A done block's check reopens its task in the slots the block took, as one Undo
step; a repeat that has moved on stays done.

Completion reports in the tray with **Undo**, for the undo window set in Settings.
**⌘Z** also uses the native window Undo history. Undo restores the unfinished
occurrence and planning choices, retains recorded work, and leaves the timer
paused. Reduce Motion uses a simple fade.

## Work history and duration suggestions

**History**, under **More options** in task details, opens recorded sessions and
completion history. Session records retain the task title, occurrence,
start, end, and pause reason. Completion records preserve each occurrence,
including recurring tasks and completed descendants. History remains available
when an ordinary task or list is deleted; **Delete everything…** in
Settings › Data explicitly clears it.

Use **Correct time…** on a finished session to correct its minutes. The original
start and end remain intact; **Restore original duration** removes the correction.
Corrections affect remaining work and future suggestions.

Suggestions use recorded active work from similar **completed** tasks: earlier
occurrences of the same task or titles sharing substantial words. Up to 20 matching
completed occurrences contribute to a median rounded to five minutes. Planned
estimates and unfinished work are not training examples. **More options** in task
details explains its sample count and offers **Use … min**. Suggestions never
change estimates without that approval.

## Local storage and iCloud

| Data | Storage and behavior |
| --- | --- |
| Task selection, deferral, estimate override, keep-together, away-tracking choice, occurrence identity | Additive fields in the existing SwiftData task records. Participate in the existing private CloudKit sync when the build is provisioned. |
| List Work/Personal choice | Additive field on the existing list record, with Work as the migration default. |
| Preferred/pinned placements, work sessions, completion records and time corrections | Separate SwiftData models in the existing local store and CloudKit configuration. History uses snapshot fields rather than cascading task relationships. |
| Weekly hours, breaks, overrides, default estimate, minimum session | Per-Mac preferences, consistent with existing app-wide settings. |
| Connected calendar selection and permission, device identity | Per-Mac state. EventKit remains the external source of truth. |
| Generated schedule and fetched external busy events | Derived in memory. No generated EventKit events or remote scheduling service. |

Scheduling works offline using locally available task data. Each Mac derives its
plan from its own hours, connected calendars, and local clock. A session’s device
identity prevents another Mac’s open session from being adopted automatically as
this Mac’s active timer. This does not provide a distributed single-active-session
lock between Macs; simultaneous work and delayed CloudKit imports still require
normal reconciliation and, if necessary, a recorded-time correction.

## Developer invariants

- `AdaptiveScheduler` consumes value types from `CalendarTypes.swift` and returns
  a deterministic plan. It has no SwiftData, UI, EventKit, or wall-clock side effects.
- Fixed busy time and other task sessions share one occupancy timeline even when
  tasks inherit different availability categories. Breaks and date overrides are
  applied before allocation. Local calendar arithmetic must handle DST transitions.
- `CalendarCoordinator` owns this Mac’s active-session clock and replan lifecycle.
  Scheduling a block never starts it. Its 15-second timer checks boundaries and
  overruns, with saved heartbeats during ongoing work.
- `Store+Calendar` owns durable choices and work history. The existing task
  completion/recurrence lifecycle records an occurrence **before** advancing its
  identity, clearing placements, or resetting descendants. Duplicate, reopen, move,
  archive, and deletion paths must preserve these identities appropriately.
- Generated blocks are disposable. Save a `SchedulePlacement` only for deliberate
  moves or pins. Conflicting placements do not count toward safe deadline coverage.
- New SwiftData fields have migration defaults; no required external credential or
  calendar permission may block opening an existing local store.
- External calendar access is read-only by implementation, even though the macOS
  EventKit permission is named full access. Do not introduce EventKit write APIs.
- Corrections preserve observed timestamps. Suggestions require a user action before
  calling the estimate setter. Keep current occurrence time separate from historical
  recurring occurrences.

Production paths: `openlist/Services/AdaptiveScheduler.swift`,
`CalendarCoordinator.swift`, `ExternalCalendarSource.swift`, `MacWorkMonitor.swift`,
`Store+Calendar.swift`; model additions are under `openlist/Model`. The Calendar
screen is `openlist/Next/NextCalendar.swift`; the Work panel, history and pickers
are under `openlist/Views`.

## Validation

The focused checks run production code with deterministic or isolated inputs:

```sh
./Tools/run-scheduling-checks.sh
./Tools/run-calendar-persistence-checks.sh
./Tools/run-calendar-runtime-checks.sh
./Tools/run-calendar-layout-checks.sh
./Tools/check.sh
```

| Check | Coverage |
| --- | --- |
| Scheduling | Deadline competition, unscheduled backlog, overflow, minimum-session fragmentation, keep-together, overlapping work/personal hours, breaks/overrides, fixed events, active overruns, pin conflicts, horizon states, and DST. |
| Calendar persistence | Migration from a legacy SQLite fixture, reopen durability, recurrence/descendant history, duplication/deletion behavior, estimates, placements, suggestions, corrections, and explicit reset. |
| Calendar runtime | Explicit start, pause/resume, overrun shifts, fixed boundaries, completion/deferral, lock/away handlers, interruption/restart recovery, and external-source fixtures. |
| Calendar layout | Completed and future blocks sharing time, collision detection using minimum rendered heights, zero-duration markers, dense history, and deterministic lane ordering. |
| Full project checks | The focused calendar suites plus existing logic, editor, duplication, export, lifecycle, visibility, sync, signing, MCP, and helper checks. |

Before the completion-history and nudge refinements, validation on 2026-09-13 passed **984 scheduling assertions**,
**48 persistence checks**, and **76 runtime checks**. Persistence checks include
real read-only SQLite save failures and recovery, alongside legacy migration and
disk reopen. The full project check also passed. The final horizon-pin regression
was followed by another focused scheduling run. Debug and unsigned Release builds
passed, including release bundle validation.

Feasible future preferred placements take precedence over the automatic today
fallback, and infeasible moves explain the conflict.

Runtime handler tests do not prove physical Mac lock/sleep notifications; fixture
busy time does not prove live EventKit account permission/import behavior; schema
and local migration tests do not prove multi-Mac CloudKit delivery. Physical
lock/sleep, real connected calendar access, and cross-Mac calendar-history sync
and production CloudKit schema deployment remain integration verification gaps.
