# Nested list documents

A child list is an independently titled document with its own stable UUID,
blocks, appearance, and display settings. `TaskList.parentListID` records its
single owning list. Tasks still belong to their own document through `listID`;
block indentation, sidebar sections, pins, and reference links do not establish
list ownership. The system Inbox cannot be a parent or a child.

Choose **New Child List** from a list's **…** menu, or from its menu in the
sidebar or the Lists gallery. A parent shows its children in a **Lists** group
above its document, and the sidebar nests them under their parent. **Move List…**
changes ownership while keeping the document's UUID, contents, appearance, and
sidebar pin. A list cannot move under itself or any descendant. Gallery cards and
search show document paths.

## Archive, Trash, and synchronization

Archiving an ancestor excludes its whole owned subtree from active work,
reminders, calendar planning, badges, widgets, and default search/list results.
Each child's own archive choice is preserved. Unarchiving the ancestor restores
only descendants without another archived ancestor or their own archive bit.

Deleting a list retains it and its currently owned available descendants as one
Trash group, with their original IDs, parent links, blocks, attachments, and
covers. Previously independently deleted children remain separate Trash groups.
Restoring a group restores its entire unit. If its former external parent no
longer exists or remains in Trash, the root recovers at top level with an
explanation. Permanent erasure applies only to the selected retained group.

Imports can arrive out of order. A missing parent reference is retained, with
the document presented at top level; a later parent reconnects it. Invalid imported cycles are broken deterministically
for presentation only. No repair silently destroys ownership information.
Late arriving children or blocks under a retained parent are excluded from active
surfaces immediately and reconciled losslessly into that Trash group. Missing
permanently erased parents never cause new records to be erased.

## Copy, export, and backup

Duplicate and template copy include all owned available descendants, including
archived descendants, with fresh list/block/media IDs, preserved document
boundaries, and activity attributed to each new document. Prior independent
Trash groups are excluded. Copying a child creates a sibling copy.

Single-document Markdown export keeps its existing behavior. A parent with child
documents exports a folder with one Markdown file per document and portable
parent/child links and assets.

Full logical backup preserves the complete parent graph and every Trash group.
Format 5 adds parent ownership and reads formats 1–5. Restore and Return retain
all nine model types and media. Cold predecessor-store reads migrate only a
private copy, never the retained original. The additive CloudKit model change
requires the production schema gate in CONTRIBUTING.md; offline checks and Dev
builds do not establish live iCloud readiness.
