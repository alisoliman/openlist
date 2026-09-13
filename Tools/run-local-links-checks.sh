#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/link-checks" \
    openlist/Model/Block.swift openlist/Model/BlockKind.swift openlist/Model/Recurrence.swift \
    openlist/Model/CalendarTypes.swift openlist/Model/TaskList.swift openlist/Model/SidebarSection.swift \
    openlist/Model/SearchOptions.swift openlist/Model/SearchHit.swift openlist/Model/ContentReveal.swift \
    openlist/Model/LocalLink.swift Shared/ListAccent.swift openlist/Services/LibraryIdentity.swift openlist/Services/NoteItemLink.swift \
    openlist/Services/LocalLinkNavigation.swift openlist/Services/ReminderNavigation.swift \
    openlist/Services/BlockTree.swift openlist/Services/Navigator.swift \
    Tools/LocalLinkChecks/main.swift
"$OUT/link-checks"
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/identity-checks" \
    openlist/Model/LocalLink.swift openlist/Services/LibraryIdentity.swift Tools/LocalLinkChecks/identity.swift
"$OUT/identity-checks" prepare "$OUT/original"
cp -R "$OUT/original" "$OUT/restored"
"$OUT/identity-checks" migrate "$OUT/original"
"$OUT/identity-checks" reopen "$OUT/original"
"$OUT/identity-checks" restore "$OUT/restored"
python3 -B Tools/LocalLinkChecks/check_registration.py
