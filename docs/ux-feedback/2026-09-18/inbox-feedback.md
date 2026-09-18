# Inbox interaction feedback — 18 September 2026

Status: Inbox rebuild implemented and opened in Openlist Dev. Up next remains a separate design scope.

## User feedback

1. The checkboxes do not align comfortably with the “1 open” count; the layout feels odd.
2. The three horizontal lines used for moving tasks are unnecessary.
3. Repeated ellipsis menus feel cluttered. Explore contextual icon actions, potentially revealed by a long press, instead of a submenu full of text.
4. “Selected” and “Unfiled” are confusing and do not communicate a useful distinction.
5. Completely rethink the “Up next” feature from a UI/UX perspective, with Mobbin research in a separate task.

## Inbox direction implemented

- Establish a consistent left alignment for the heading, count, and task checkbox column. Account for the currently reserved 22-point selection gutter; do not simply move the count to compensate for accidental padding.
- Remove the persistent trailing drag-handle icon. Keep reordering available through a deliberate row drag interaction and keyboard/accessibility actions. Preserve text selection and inline editing; dragging a task within Inbox must not move its source list.
- Replace each persistent ellipsis control with a small contextual set of action icons. Use hover, editing, row selection, keyboard focus and VoiceOver reveal. Native macOS secondary-click is the contextual entry point; no long-press gesture is required. Keep right-click and keyboard access. Use tooltips and accessible names, maintain a stable hit area, and keep completion distinct from removing a task from Inbox or moving it to a list.
- Present a single Inbox for new, unorganized tasks and notes. Remove the “Selected / Unfiled” split rather than renaming it.
- Preserve tasks, notes, source-list membership, and undo behavior through any redesign.

## Confirmed product decision

The user chose: “Only new, unorganized tasks and notes; filing them removes them from Inbox.”

Inbox is a capture-and-organize destination, not a manually selected cross-list task queue. Filing a task or note into a list removes it from Inbox. Scheduling is not filing: setting a due date alone does not change its location.

Remove the “Selected / Unfiled” split from the proposed interface. Preserve support for rich notes and task hierarchy in the single capture document.

Implementation covers the complete old membership path (Add/Remove from Inbox actions, independent queue ordering, commands, tests, and documentation; no separate membership integration API was present). Preserve existing task identities, source lists, rich content, and descendants. Tasks already filed in real lists must stay there; changing this model must not duplicate, delete, or move them into Inbox.

The earlier interactive queue proposal is superseded by this decision and should not be implemented as shown.

## Separate research scope: Up next

Research the full planning-to-work journey, including idle recommendations, starting, pausing, resuming, completion, and overruns. Explore alternatives to the global banner using Mobbin; present 2–3 options and a recommended visual direction before implementation.

Relevant source: `openlist/Views/CalendarWorkBanner.swift`.

## Evidence

- `inbox-original.png`: unannotated capture of the development inbox.
- `inbox-feedback.png`: copy opened in Shottr for user annotation. Do not assume annotations have been saved.
- The interactive inbox proposal in the conversation is exploratory and has not been implemented in the native app.

## Rebuild evidence

- `inbox-rebuilt-idle.jpg`: current development library with the single Inbox, aligned heading/count/checkbox column, and quiet rows.
- `inbox-rebuilt-actions.jpg`: focused task with filing, date, details and Trash icons. Editing no longer shows a second selected-row checkbox.
- [Behavior and sources](../../INBOX.md): Mobbin screens and current Apple HIG guidance used for the rebuild.

Native checks used an isolated review library: filing into Personal removed the
item and updated both badges; Cmd-Z restored it. Creating a plain-text note,
setting a date without filing, completing a task, hiding completed tasks while
keeping notes, and reordering via Format > Move Up were verified. Action icons
remain in the accessibility tree while visually quiet and appear on focus.
The development app was then reopened on its own existing Inbox without editing
its content.

The synthetic gutter-drag attempt did not reliably complete a reorder; one drop
was rejected safely and content stayed unchanged. Native menu reordering passed.
The underlying shared drag implementation was retained. The existing Up next
banner appeared/disappeared during review, changing row positions; include that
layout instability in its separate redesign.

Automated checks passed: Inbox ownership/migration/relaunch/read-only failure and
restore (56), navigation (34), bulk actions and relaunch (146), fragments (75),
hidden inspector lifetime (108), backup and closed snapshots (140), Trash and
pre-Trash migration (122), sync/schema (245), capture (45), task history (94).
The development build, bundle/signing verification and nine isolation checks
passed. These are targeted regression checks; the full repository check runner,
Release distribution, VoiceOver speech, and two-device CloudKit sync were not run.

## Combined Inbox and Work verification

The Inbox and Work companion commits were combined on `codex/inbox-work-interactions`.
A separately signed `Openlist Combined Review.app` used a new disposable sample
library, with CloudKit disabled. Native integration checks confirmed:

- Inbox has one capture document, aligned count/checkboxes, contextual row icons,
  and the Work toolbar without the former document-displacing banner.
- Start Selected Task from the Work menu starts the selected Inbox occurrence.
- Filing that actively recorded task into Personal removes it from Inbox while
  the toolbar continues recording the same task. Undo restores Inbox ownership.
- At the end of available hours, recording pauses with an explanatory notice.
- Completing from Work reduces the Inbox count. Work's Undo completion restores
  the pending task and count without restarting recording.

See [integrated Inbox and Work](inbox-work-integrated.jpg). This extends the
native evidence above; the previously recorded drag and accessibility limits
still apply. Full combined automated/build results are listed in the PR.
