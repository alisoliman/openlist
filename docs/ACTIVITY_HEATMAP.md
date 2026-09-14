# Activity heatmap

Open **More → Activity** in the sidebar, or Activity in the View menu or command palette, to see the current
calendar week and the previous 11 weeks. The grid follows the first-weekday
preference and this Mac's current time zone. Each day is a keyboard-accessible
button with its date and numeric count; selecting it shows the saved completion
titles, list names, and local times. Numbers remain visible in every colored
cell, so color is never the only way to read the grid. The legend uses fixed
bands: 1, 2–3, 4–6, and 7 or more recorded completions.
**About these counts** contains time-zone and counting details. Missing history
and uncountable entries remain visible beside the grid rather than being hidden
in that disclosure.

## What counts

The source is committed `ActivityEvent` completion history, independent of the
Updates feed's latest-300 helper and of today's task state. An ordinary task
counts once by task UUID across all retained history. A recurring task or a
subtask in a recurring cycle counts once per task UUID and completed occurrence
cycle UUID. The first countable recorded completion supplies the day and saved title. Reopening
an ordinary task does not add another count. Undo keeps the historical performed
action, as in the task Activity timeline; Redo does not add another count.
Deduplication happens before restricting the visible date range.

New completion events capture the exact completed occurrence UUID, counting
cycle UUID, and recurrence status inside the existing optional Codable `changeData` payload.
This includes children completed directly under a recurring ancestor, children
completed by the parent, and the parent's final repeat. The existing completion
record's `wasRecurring` snapshot now includes inherited recurring cycles; its
existing Calendar work-history label therefore describes those children too.
The app adds no model, database field, account, or analytics service.

For older events, a retained completion record may supply missing metadata only
when its completion UUID and task UUID match that event. A calendar record
without an event never becomes heatmap history. Entries without enough task,
recurrence, occurrence, or date information are excluded and disclosed. Older
recurring children may have been recorded as ordinary tasks and can be
undercounted. Current hierarchy, current recurrence rules, and the earliest
event are never used to invent old facts or a coverage start date.

## Coverage, saving, and retention

There is no historical coverage ledger. Every total describes available
records and may be incomplete. A dash means a count is unavailable; it does
not establish that no tasks were completed that day. The day detail and empty
state explain this too. Clearing history, importing a library with partial
history, older app versions, and incomplete synchronization can leave gaps.

Activity reads through a fresh context and refreshes after saved changes,
remote database changes, app activation, date/time-zone changes, and changes to
the first-weekday preference. Uncommitted or failed task saves are not counted.
A read failure replaces the grid with an error and retry action instead of
showing stale totals or an empty-success state. Refresh is also available in the
page header.

Moving tasks or lists to Trash, restoring them, and permanently erasing them
retain the existing independent completion history. **Clear History** in
Updates and **Clear all activity history** in Settings clear the heatmap along
with task Activity entries. Calendar-only records cannot repopulate it.
**Delete all data** removes these events too. Clearing Calendar work history
does not remove new event-based counts; older entries that depended on calendar
metadata can become uncountable, which is disclosed. Whole-library backups
already preserve `changeData` bytes, including these optional fields. This
feature changes neither backup schema nor private migration behavior.

Inherited recurring children use their nearest recurring ancestor's cycle,
which stays stable when a child is repeatedly reopened before the parent
advances. Parent cascades can complete a self-recurring child without advancing
its own rule; reopening history preserves that unadvanced cycle for both the
child and its descendants. Completion Undo snapshots retain the same cycle for
Redo. The calendar's own occurrence UUID behavior is unchanged.
Multi-selection completion and reopening use the same cycle facts, including
their multi-root Undo/Redo. A failed atomic bulk action rolls back its pending
cycle metadata along with its task changes.

Run `./Tools/run-activity-heatmap-checks.sh` for date boundaries, DST/time-zone
grouping, repeated toggles, recurring children, Undo/Redo, committed reads,
failed writes/clear, old payload decoding, backup roundtrip, Trash retention,
and process relaunch coverage.
