#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/library-backup-checks" \
  openlist/Model/*.swift Tools/InboxChecks/LegacyInboxMembership.swift Shared/ListAccent.swift Shared/ReviewSession.swift Shared/AppGroup.swift \
  openlist/Services/LibraryBackupPackage.swift openlist/Services/LibrarySnapshots.swift openlist/Services/BackupStagedStore.swift openlist/Services/BackupSnapshotReader.swift openlist/Services/LibraryRestoreStorage.swift \
  openlist/Services/MediaStore.swift openlist/Services/BlockTree.swift \
  openlist/Services/ICloudConfiguration.swift openlist/Services/ICloudError.swift \
  openlist/Services/RichTextCodec.swift openlist/Design/Theme.swift Tools/LibraryBackupChecks/main.swift
"$OUT/library-backup-checks" "$OUT/Fixture" write
"$OUT/library-backup-checks" "$OUT/Fixture" reopen
"$OUT/library-backup-checks" "$OUT/ClosedSource" prepare-closed
"$OUT/library-backup-checks" "$OUT/ClosedSource" read-closed
