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

Rows reveal filing, due date, details and Trash icons on hover, selection or
keyboard focus. Notes have filing and Trash. Help tags and accessibility names
explain every icon. Native secondary-click menus and existing editor shortcuts
remain available. Selection and dragging use the existing leading gutter;
there is no separate queue-order handle or ellipsis on Inbox rows.

## Compatibility

The old independent selected-task queue and its Add/Remove commands are removed.
Existing list-owned tasks remain in their lists. Existing Inbox content retains
its IDs and hierarchy. No task is copied, deleted or relocated during upgrade.

`Block.inboxMembershipData` remains an inert optional storage field solely for
CloudKit schema and lossless backup/restore compatibility. Runtime code never
interprets it or writes a new selection. Unknown payloads are retained byte for
byte; new content and copies have nil. The former codec lives only in test
fixtures that exercise earlier backup formats.

## Design references

Reviewed September 18, 2026. [Todoist's simple Inbox](https://mobbin.com/screens/a0df0fa0-3968-4919-b45d-478f1af8e75e)
provides a clear task column and inline capture. Its [contextual task actions](https://mobbin.com/screens/4c1351ef-54cc-47ff-aee1-e85019bdad39)
place date choices and project movement close to the task. These informed the
hierarchy and filing flow; Openlist retains its native rich document editor.

Apple's [context menu guidance](https://developer.apple.com/design/human-interface-guidelines/context-menus)
warns that hidden menus can be hard to discover and recommends relevant,
concise actions. [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
and [help](https://developer.apple.com/design/human-interface-guidelines/offering-help)
guide recognizable glyphs, native interaction and action-specific help tags.
[Drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop)
guidance supports Undo and alternative accessible actions. On macOS, secondary
click and visible-on-focus actions are the primary affordances; long press is
not required to discover or operate the app.
