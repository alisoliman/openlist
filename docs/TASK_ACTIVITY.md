# Task activity

Open a task's details: **Activity** lists this session's changes to it and where
it was captured, and **Full history** below expands its saved changes, newest
first, with local dates, times and the list each happened in. **Load older
activity** adds 50 entries at a time. This query filters by the task's UUID
before applying its limit, so it reaches history older than the recent events
the Activity screen's **Changes** shows. Equal timestamps use the event UUID as a
stable second ordering key.

Activity's **Changes** and task history share `ActivityEvent` records.
New events capture committed titles, due dates (including whether a time was
specified), completion or reopening, and list moves. A recurring completion
records the completed occurrence and resulting next occurrence in one entry.
Children completed by a parent receive their own entries. Undo and Redo add
truthful inverse/new entries; they do not erase the prior action. Labels,
priority, and note differences are outside this timeline's new detail scope.

Outline title edits coalesce until a one-second pause or an explicit editor
action saves. Inspector titles and notes commit on submit, focus end, closing the
inspector, app focus loss, or quit. A save for another explicit action also
commits current model edits. Saving without a tracked change adds
no event. Sample data does not generate an invented action history.

Events retain the title and list name at their commit. Old records may contain
only the original text; the app displays that text without reconstructing
missing before/after values. Unreadable optional detail data takes the same
fallback. Existing events receive no fabricated migration data.

## Saving and retention

Tracked task edits and their generated history save in the same SwiftData transaction.
Store owns the save boundary; its context does not independently autosave.
Editor text has a debounce fallback, explicit editing actions save immediately,
and lifecycle handling commits local drafts before the final save. Quit is
cancelled when that save fails so the edit remains available for retry.

A failed save leaves pending local edits available and reports the save error.
SwiftData can temporarily return failed inserted events from its live cache;
the Store quarantines those attempt IDs, excludes them before task pagination,
and deletes them again before every later commit. A retry derives a fresh event
from the unchanged disk state, so an uncommitted action is never published as
history. External capture/MCP transactions retain their existing rollback
contract after first flushing earlier edits.

History has no new automatic age/count pruning. Deleting a task or list keeps
its recorded events; a task in Trash cannot be opened. **Clear all activity
history…** in Settings › Data explicitly removes Changes, the completion heatmap
and every task's history, after confirmation, while keeping tasks. **Delete
everything…** also removes the shared records. These deletions participate in existing iCloud
sync. Future Trash operations must keep this UUID-keyed history for retained
tasks; filtering a task out of an active list must not delete its events.

Activity can contain past titles, list names, and dates. It is stored locally
in the existing database and follows the app's existing optional iCloud sync.
iCloud sync is not a backup. Markdown exports do not include ActivityEvent
history; whole-library backups do (see [manual backup and restore](LIBRARY_BACKUP.md)).

## Write-path audit

| Writer | Save boundary |
| --- | --- |
| Outline rich/plain text and captions | Document change debounce; explicit editor-action save |
| Inspector task title | Store text debounce; submit/blur/disappear save |
| Due-date pickers, completion, recurrence, moves | Existing Store save/batch boundary |
| List title, summary, appearance, sorting | Existing synchronous Store save |
| Attachments and structural editor operations | Existing save and Undo commit boundary |
| Capture and MCP mutations | Preflush, mutation, throwing Store persistence; rollback on failure |
| App preferences | UserDefaults, independent of SwiftData autosave |
| Label merge | Existing isolated writer transaction; no new task field event |

Committed before-state reads are restricted to changed task UUIDs and their
list UUIDs. They do not scan a full task library for every keystroke. Focused
checks include a 10,000-task corpus and report the single-task save duration.
