# List Tasks view

A list's **…** menu has **Show Tasks Only**. It is the same list document with
its headings, notes and prose hidden, each task nested under the tasks above it.
The choice is stored per list in this Mac's preferences, including isolated Dev
and review-session preference suites; lists open as their document and the
Inbox as triage until this Mac chooses otherwise. It adds no SwiftData or
CloudKit fields. List sorting and completed visibility keep their existing
synced preferences, and the same **Sort** and **Completed Tasks** choices apply
in both presentations.

Only tasks fold in Tasks mode: what a heading, list item or text line folds away
still shows, as tasks under the tasks above. Completed top-level tasks gather in
the **Completed** group under the document, open or folded by the list's
completed preference; done subtasks stay struck in place. In Tasks mode the top
level is the tasks': a done task with no task above it, under a heading, list
item or text line, gathers in **Completed** too. Neither presentation
rewrites stored order: **Manual** follows the original outline, and the other
sorts reorder only adjacent root tasks, carrying each subtree.

Lines edit and complete their original blocks, and details open the same task.
A search hit or link on a line, a line's note or the list's description shows
the list as its document for that visit, so hidden prose can be revealed,
without changing the saved choice. A reminder, link or search hit on a task, or
on the list itself, keeps the list as this Mac shows it.

Capture places the new task at the end of its list's document, as the design's
does, wherever it was captured from and in either presentation, opening the
folded headings it goes in (Undo folds them again); a list on show then shows it
at its sorted position. Capture elsewhere keeps its Inbox default. Users can
still choose another destination.

## Automated checks

- `Tools/run-inbox-navigation-checks.sh`: per-list presentation, command
  ownership, back/forward, preference relaunch and prose reveal.
- `Tools/run-capture-checks.sh`: capture appends to the document root, in the
  order captures are made, preserves prior hierarchy and indices, and opens the
  folded headings it goes in.
- `Tools/run-list-tasks-checks.sh`: `ListTasksProjection`, the flat queue of a
  list's tasks the List widget shows: mixed headings, collapsed branches, rich
  prose, nested tasks, every sort and stable ties, hidden completed tasks and
  unchanged payloads.
- `Tools/check.sh`: complete repository regression checks.
