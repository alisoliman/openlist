# List Tasks view

Lists offer Document and Tasks as two presentations of the same blocks. The
choice is stored per list in this Mac's preferences, including isolated Dev and
review-session preference suites. It adds no SwiftData or CloudKit fields.
List sorting and completed visibility retain their existing synced preferences.

Tasks includes every original descendant task once, regardless of collapsed
ancestors. It hides non-task blocks and the list description. Parent breadcrumbs
are resolved from all blocks in the list, so a task nested under a note or
heading retains that context. Completed visibility applies to each task
independently; shown completed tasks participate in the same queue and sort.
There are no groups or parent rows repeated around their children.

Manual task order is depth-first document order. All other sorts use the same
`ListSorting` comparisons as Document and retain outline order when keys tie.
Document still sorts only contiguous runs of root tasks and carries subtrees
with their parents. Both operations are read-only projections.

Smart task rows edit and complete their original blocks. Details retain normal
task subdocuments and metadata. Tasks mode has no drag reordering or document
structural commands. Switching mode clears selection, the open inspector and
its command target; exact-content search/reminder navigation switches back to
Document before revealing the target.

Capture from Tasks mode initially selects the current list and appends at the
destination document's root. Users can still choose another destination. The
request carries no projected index or parent reference. Ordinary capture keeps
its Inbox default and root-prepend behavior.

## Automated checks

- `Tools/run-list-tasks-checks.sh`: mixed headings, collapsed branches, rich
  prose, image bytes and nested tasks; every sort and stable ties; independently
  hidden completed tasks; identical payload snapshots before/after projection;
  original-identity mutations and preserved Document sorting boundaries.
- `Tools/run-capture-checks.sh`: task-mode root append preserves prior hierarchy
  and indices, while ordinary captures still prepend.
- `Tools/run-inbox-navigation-checks.sh`: mode-specific command ownership,
  inspector closure, back/forward, per-list preference relaunch and prose reveal.
- `Tools/check.sh`: complete repository regression checks.

## Native review fixture

Use an isolated Openlist Dev review library, never the production library.
Prepare one list with two headings separated by prose; two root tasks with
different dates/priorities; a nested child under a task; a task under a collapsed
heading; a completed parent with a separately reopened child; and an image or
rich text. Keep a copy of the original document/export for comparison.

1. Switch Document → Tasks with both mouse and keyboard. Verify only task rows
   appear, each once, and nested rows show their parent. Verify the description
   hides and the completed-state control remains visible.
2. Exercise all five sorts across heading boundaries. Show/hide completed work
   and confirm an open child remains available when its parent is hidden.
3. Edit a child title, open its details, change a date and complete/reopen it.
   Verify the same task changes in Document and no prose or ordering changes.
4. In Tasks mode, use Add task and ⌘N, including after closing an inspector.
   Confirm the current list is selected and new tasks append to its document
   root while appearing at their sorted queue position. Confirm choosing a
   different capture destination still works.
5. Switch away/back and relaunch the isolated app. Confirm each list remembers
   its own mode and that normal capture still starts in Inbox.
6. Switch back to Document/manual. Compare heading, image, formatting, hierarchy
   and original indices. Verify outline commands work again and Tasks mode has
   no manual drag controls. Search for hidden prose and verify it opens Document.
7. Check mode and sort controls with VoiceOver, a narrow window and an open
   inspector. BRI-25 integration must also cover modifier selection, toolbar
   actions and selection pruning when sorting or filtering this new queue.

Native review results are recorded by the release owner after running these
flows; build success alone is not evidence of native interaction success.
