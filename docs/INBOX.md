# Inbox

Inbox is the system capture document for new, unorganized tasks and notes.
Filing an item into a list moves its whole branch out of Inbox. The same identity,
rich text, notes, nested tasks, attachments, labels and history remain intact.
Native Undo returns the branch to its original location.

A due date, completion, recurrence or reopening does not change ownership.
Completed visibility uses the existing per-list preference; pending branches
appear before completed branches, without separating children from their parent.
The sidebar counts the tasks still to triage, as the design does: tasks the card
kept for later or scheduled, a repeating task that **Already done** rolled to its
next date, and subtasks under an open task, which go with its card, are left
out. Those the card set aside count again once **Review kept tasks** or a
relaunch starts triage over. The widgets count as the sidebar does, subtasks
under an open task left out, though they can't see what the card set aside in
the window; the menu bar counts every open task owned by the system Inbox.
Standalone notes remain visible and do not inflate task counts.

Inbox opens as triage. One card takes each open task in turn, with what it
holds under its title: the first lines of its note, then its day, priority,
labels, subtasks and files. **File into** lists the first nine destinations
(keys 1–9) and **Other list…** (L) every list, by name, in the command palette.
The list the task's words point to (the one whose name the title says, or
whose tasks share its words) is marked with a sparkle, and 0 files into it; a
suggested list past the first nine leads the column. **Or schedule — stays in
Inbox** sets one of the next eight days (T today, M tomorrow). ⇧T, ⇧M or a
⇧-click on a day picks it instead, for the list the card is filed into next:
the list's number then files it with that day, as one step with one Undo, and
Escape unpicks it.

R, or a click on the title, opens the card's edit line: the title to change,
and capture's tokens to add, a day in words ("dec 3", "in 2 weeks"), `@list`,
`#label`, `!priority`, `~estimate` or a repeat. Return writes it over the task;
a line naming a list files the card there, and one naming a day schedules it
in the Inbox, as the keys would, with the rest of what it says. A click on the
card's other controls while the line is open takes the edit with it.

**Already done** (E), **Discard** (D, to Trash), **Snooze** (S until tomorrow,
⇧S until next week, or the menu's weekend and month) and **Keep for later** (→)
finish the card. **Details** (↩) opens the task in the inspector and leaves its
card on top, where the triage keys still act on it. The remaining tasks wait
under **Up next**, kept ones under **Kept for later** and snoozed ones under
**Snoozed**, folded, as ordinary rows; with rows focused or selected there,
1–9 file them all and S snoozes them. The header's document button shows the
Inbox as its document instead, with its notes and headings; this Mac remembers
that choice, and the widget's Triage link opens triage for that visit only.

## Snooze

Keep for later sets a card aside for this session on this device. Snooze puts
it away until a day: it leaves triage's queue, its counts (the sidebar's, the
dock's badge and the widgets') and No date's pass, and comes back by itself
that morning, on every device, as `Block.deferredUntil` syncs with the task.
It isn't planned for that day, so it doesn't land on Today as well. Rows show
the day it's back; Stop snoozing on the iPhone's task page, or Clear beside
"Snoozed until" in the Mac's inspector, brings it back at once, as Undo does.

## iPhone

The iPhone's Inbox opens triage from **Triage one by one**: a card at a time,
each with **Delete**, **Already done**, **Snooze** and **Later**. A switch at the
top picks the pass. **Inbox** takes each capture, oldest first: pick a list, a
day or both, and **Next** files it in one step. The list its words point to
leads **Move to** with a sparkle; past eight lists, **More** finds any list by
name, nested ones by their path. A tap on the title edits it, tokens and all:
the title, repeat, labels, priority and estimate are written at once, with
Undo, and a day or `@list` it names is picked on the card for Next. The ⓘ button
opens the task's page over triage; Back returns to the card. **No date** takes
the open tasks in your lists that have no due date and aren't planned, deferred
or snoozed to a day, in the lists' order, a subtask going with its open parent.
A day's chip, or the date picker's **Set**, dates a No date card at once, with
Undo in the tray. **Snooze** offers tomorrow, the weekend, next week, a month
on or a date; **Later** skips a card until triage goes over what it kept or the
app relaunches. Under the captures, snoozed ones wait under **Snoozed** with the
day they're back, and **N without a date in your lists** opens the No date pass,
also once the Inbox is empty. **Select** (the ✓ in the top bar) picks several
captures to mark done, date, move or delete at once; moving picks the list in
the same searchable list as **More**, which a row's **Move to list** opens too.

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
