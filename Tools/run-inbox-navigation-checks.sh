#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# The visit's document is Navigator's alone (`Navigator.reveal`). A view's own
# set of revealed lists, turned back to Tasks on leaving, once saved Tasks over
# an Inbox this Mac shows as Document; the checks below can't see a view.
if grep -rnE 'revealedDocuments|settleRevealedLists' openlist; then
    echo "A per-visit revealed-document set is back outside Navigator; Navigator.reveal owns the visit's document." >&2
    exit 1
fi
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/inbox-navigation-checks" \
    openlist/Model/Block.swift openlist/Model/TrashMetadata.swift openlist/Model/BlockKind.swift \
    openlist/Model/Recurrence.swift openlist/Model/CalendarTypes.swift openlist/Model/ListCover.swift openlist/Model/TaskList.swift openlist/Model/ListHierarchy.swift \
    openlist/Model/SidebarSection.swift openlist/Model/SearchOptions.swift openlist/Model/SearchHit.swift \
    openlist/Model/ContentReveal.swift Shared/ListAccent.swift \
    openlist/Services/BlockTree.swift openlist/Model/ListViewMode.swift openlist/Model/BlockSelection.swift openlist/Services/Navigator.swift \
    Tools/InboxNavigationChecks/main.swift
"$OUT/inbox-navigation-checks"
