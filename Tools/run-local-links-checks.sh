#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/link-checks" \
    openlist/Model/Block.swift openlist/Model/BlockKind.swift openlist/Model/Recurrence.swift openlist/Model/TrashMetadata.swift \
    openlist/Model/CalendarTypes.swift openlist/Model/TaskList.swift openlist/Model/ListHierarchy.swift openlist/Model/ListCover.swift openlist/Model/SidebarSection.swift \
    openlist/Model/SearchOptions.swift openlist/Model/SearchHit.swift openlist/Model/ContentReveal.swift \
    openlist/Model/LocalLink.swift openlist/Model/BlockSelection.swift openlist/Services/DragPayload.swift Shared/ListAccent.swift openlist/Services/LibraryIdentity.swift openlist/Services/NoteItemLink.swift \
    openlist/Services/LocalLinkNavigation.swift openlist/Services/ReminderNavigation.swift \
    openlist/Services/BlockTree.swift openlist/Model/ListViewMode.swift openlist/Services/Navigator.swift \
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
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/restore-link-checks" \
    openlist/Model/*.swift Shared/ListAccent.swift Shared/ReviewSession.swift Shared/AppGroup.swift \
    openlist/Services/LibraryIdentity.swift openlist/Services/LocalLinkNavigation.swift openlist/Services/Navigator.swift openlist/Services/DragPayload.swift \
    openlist/Services/LibraryBackupPackage.swift openlist/Services/BackupStagedStore.swift \
    openlist/Services/BackupSnapshotReader.swift openlist/Services/LibraryRestoreStorage.swift \
    openlist/Services/MediaStore.swift openlist/Services/BlockTree.swift \
    openlist/Services/ICloudConfiguration.swift openlist/Services/ICloudError.swift \
    openlist/Services/RichTextCodec.swift openlist/Design/Theme.swift Tools/LocalLinkChecks/Restore/main.swift
for phase in prepare restore return different; do
    "$OUT/restore-link-checks" "$OUT/SelectedLibrary" "$phase"
done
