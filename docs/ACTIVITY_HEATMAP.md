# Activity heatmap

Open **Activity** in the sidebar, press **⌘6**, or choose it in the View menu or
command palette to see the current calendar week and the previous 11 weeks. The
grid follows the first-weekday preference and this Mac's current time zone. Each
day is an accessibility button whose description carries its date, its numeric
count, that history may be incomplete, and how many entries have missing or
conflicting counting details. Clicking a day shows its saved completion titles,
lists and local times, and a title opens that task's details. Numbers remain
visible in every colored cell, so color is never the only way to read the grid.
The legend uses fixed bands: 1, 2–3, 4–6, and 7 or more recorded completions,
and the card sums the range with the current streak. **Changes**, below, is the
log of recent edits.

## What counts

The source is committed `ActivityEvent` completion history, independent of the
recent events **Changes** reads and of today's task state. An ordinary task
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
records and may be incomplete. An empty cell means no completion was recorded;
it does not establish that no tasks were completed that day. Clearing history,
importing a library with partial history, older app versions, and incomplete
synchronization can leave gaps.

Activity reads through a fresh context and refreshes after saved changes,
remote database changes, app activation, date/time-zone changes, and changes to
the first-weekday preference. Uncommitted or failed task saves are not counted.
A read failure replaces the grid with an error instead of showing stale totals
or an empty-success state; the next refresh tries again.

Moving tasks or lists to Trash, restoring them, and permanently erasing them
retain the existing independent completion history. **Clear all activity
history…** in Settings › Data clears the heatmap along with Changes and each
task's history. Calendar-only records cannot repopulate it. **Delete
everything…** removes these events too. Whole-library backups
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
