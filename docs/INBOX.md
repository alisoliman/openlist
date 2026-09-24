# Inbox

Inbox is the system capture document for new, unorganized tasks and notes.
Filing an item into a list moves its whole branch out of Inbox. The same identity,
rich text, notes, nested tasks, attachments, labels and history remain intact.
Native Undo returns the branch to its original location.

A due date, completion, recurrence or reopening does not change ownership.
Completed visibility uses the existing per-list preference; pending branches
appear before completed branches, without separating children from their parent.
The sidebar, menu bar and widget count open tasks owned by the system Inbox.
Standalone notes remain visible and do not inflate task counts.

Inbox opens as triage. One card takes each open task in turn: **File into**
lists the first nine destinations (keys 1–9), **Or schedule — stays in Inbox**
sets one of the next eight days (T today, M tomorrow), and **Already done** (E),
**Discard** (D, to Trash), **Details** (↩) and **Keep for later** (→) finish the
card. The remaining tasks wait under **Up next**, and kept ones under **Kept for
later**, as ordinary rows. The header's document button shows the Inbox as its
document instead, with its notes and headings; this Mac remembers that choice,
and the widget's Triage link opens triage for that visit only.

## Compatibility

The old independent selected-task queue and its Add/Remove commands are removed.
Existing list-owned tasks remain in their lists. Existing Inbox content retains
its IDs and hierarchy. No task is copied, deleted or relocated during upgrade.

`Block.inboxMembershipData` remains an inert optional storage field solely for
CloudKit schema and lossless backup/restore compatibility. Runtime code never
interprets it or writes a new selection. Unknown payloads are retained byte for
byte; new content and copies have nil. The former codec lives only in test
fixtures that exercise earlier backup formats.

## Design

The triage card and its groups follow the Openlist Next v2 design in
[docs/design/openlist-next-v2](design/openlist-next-v2/); `openlist/Next/NextInbox.swift`
draws them.
