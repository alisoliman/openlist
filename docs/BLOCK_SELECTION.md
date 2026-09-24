# Row selection and bulk actions

On Next screens (Today, Tasks, labels, a list's Completed group and the Inbox's
groups), ⌘-click or ⇧-click adds a row to the selection or takes it out, **X**
toggles the focused row, and ⌘A selects every visible row. Plain click focuses a
row and clears the selection; Escape clears it too. A task's round checkbox
still means completion.

While rows are selected, the selection bar at the bottom of the window offers
**Done** (E), **Today** (T), **Tomorrow** (M), **Plan** (P), **Star** (F) and
**Trash** (D). Each acts on the whole selection as one change, reported in the
tray with Undo. A row drags onto a list in the sidebar, or onto a line of a list
document, to move there.

The list document keeps its own outline selection, scoped to that document, for
its structural commands and drags.

## Files

`Next/Workbench.swift` owns the screens' selection, focus and visible row order;
`Next/NextBars.swift` draws the selection bar and `Next/NextRow.swift` the rows,
their clicks and drags. `Model/BlockSelection.swift`, through
`Services/Navigator.swift`, holds the document's outline selection.
`Services/DragPayload.swift` carries and validates multi-root drags, and
`Next/NextSidebar.swift` accepts them.

## Store invariants

Complete and Reopen are explicit operations; the reopen path uses
`Store.setBulkCompletion`, whose one Undo restores each task's completion
exactly. Move uses `Store.moveSelection`: it preserves the selected display
order and descendants, and registers one move Undo. Trash takes the selected
tasks with everything nested under them to durable Trash, with one Undo.

Bulk snapshots exclude retained and permanently erased blocks, retained lists,
and merged list aliases before selection, hierarchy, completion or move
validation. A raw alias is never accepted as an available document owner. Move
Undo requires its affected content and original parent/list destinations to
remain available; older Undo cannot revive Trash content. Failed atomic bulk
actions roll back their pending changes.

`moveSelection(... expandsParent: true)` expands a collapsed destination in the
same save as a positional move. One move Undo/Redo includes that expansion only
while its expected collapse state remains unchanged; later explicit collapse
choices are preserved.

Versioned drag payloads carry a per-Navigator session nonce. Legacy single UUID
payloads are accepted only when the same running Navigator has an active
matching single-row drag; arbitrary strings and malformed internal payloads are
rejected, never inserted as text. Drop handlers recheck the target model before
dispatching a mutation, so a target deleted during payload loading produces an
unavailable-target notice and no partial drop. Both app manifests export
`app.openlist.block-drag` as `public.data`; `Tools/verify-drag-types.py` checks
both manifests, and the Dev and Release verifiers run it on the built
Info.plist.

## Checks

`Tools/run-block-selection-checks.sh` covers the outline selection model,
`Tools/run-drag-payload-checks.sh` malformed, cross-session and manifest cases,
and `Tools/run-bulk-action-checks.sh` bulk completion, moves, Trash, stale
selections and destinations, save failures and separate-process reopening.
