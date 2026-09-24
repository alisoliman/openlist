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
document, to move there; a selected row takes the rows selected alongside it, in
screen order.

In a list document the line being written is the document's own selection,
scoped to that document, which its menu commands act on. A line's grip drags it
with the rows selected alongside it.

## Files

`Next/Workbench.swift` owns the screens' selection, focus and visible row order;
`Next/NextBars.swift` draws the selection bar and `Next/NextRow.swift` the rows,
their clicks and drags. `Model/BlockSelection.swift`, through
`Services/Navigator.swift`, holds the list document's selection and its scope.
`Services/DragPayload.swift` carries and validates multi-root drags, and
`Next/NextSidebar.swift` accepts them.

## Store invariants

Done and Reopen are explicit operations. Done completes each selected task
through `Store.toggleCompletion`, a repeat at once and the rest when the undo
window ends, grouped as one Undo for the batch. Reopen uses
`Store.setBulkCompletion`, whose one Undo restores each task's completion
exactly. A drag move uses `Store.moveSelection`: it preserves the selected
display order and descendants, and registers one move Undo.

Trash goes through `Store.trashBlocks` with the selected tasks that still exist
and everything nested under them, in one transaction with one Undo. It is not
all-or-nothing across the selection: a row trashed or erased since it was
selected is skipped and the rest go to Trash. `Store.trashSelection`, which
refuses a partly unavailable selection, is still checked but no screen uses it.

`setBulkCompletion` and `moveSelection` snapshot the selection first, excluding
retained and permanently erased blocks, retained lists, and merged list aliases
before selection, hierarchy, completion or move validation, and reject the
whole action if any selected row is unavailable. A raw alias is never accepted
as an available document owner. Move Undo requires its affected content and
original parent/list destinations to remain available; older Undo cannot
revive Trash content. A failed save rolls back the whole bulk action, Trash
included.

`moveSelection(... expandsParent: true)` expands a collapsed destination in the
same save as a positional move. One move Undo/Redo includes that expansion only
while its expected collapse state remains unchanged; later explicit collapse
choices are preserved.

Versioned drag payloads carry a per-Navigator session nonce. A document line
and a sidebar list take only those: an older single-row UUID payload and
malformed internal payloads are rejected, never inserted as text or moved. Drop handlers recheck the target model before
dispatching a mutation, so a target deleted during payload loading produces an
unavailable-target notice and no partial drop. A sidebar list drags on a
private type of its own, `app.openlist.list-drag`, which only the sidebar takes,
so a document line neither takes it in as text nor marks a drop for it. Both
app manifests export `app.openlist.block-drag` and `app.openlist.list-drag` as
`public.data`; `Tools/verify-drag-types.py` checks both manifests, and the Dev
and Release verifiers run it on the built Info.plist.

## Checks

`Tools/run-block-selection-checks.sh` covers the document selection's scope,
`Tools/run-drag-payload-checks.sh` malformed, cross-session and manifest cases,
`Tools/run-bulk-action-checks.sh` bulk completion, moves, `trashSelection`,
stale selections and destinations, save failures and separate-process
reopening, and `Tools/run-trash-checks.sh` the `trashBlocks` path the selection
bar's Trash takes, including trashing several roots as one change.
