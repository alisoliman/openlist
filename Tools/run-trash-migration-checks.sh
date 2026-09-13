#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
MODELS=()
for model in openlist/Model/*.swift; do
    case "$model" in
        */Block.swift|*/TaskList.swift) ;;
        *) MODELS+=("$model");;
    esac
done
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library -o "$OUT/pre-trash" \
  "${MODELS[@]}" Tools/TrashChecks/PreTrashBlock.swift Tools/InboxChecks/LegacyTaskList.swift \
  Tools/TrashChecks/PreTrashCompatibility.swift Shared/ListAccent.swift Tools/InboxChecks/ReviewSession.swift \
  openlist/Services/MediaStore.swift openlist/Services/BlockTree.swift Tools/InboxChecks/LegacyFixture.swift
# Reuse the full cold restore/Return matrix, asserting retained queue payloads.
python3 - "$OUT/RestoreChecks.swift" <<'PY'
from pathlib import Path
import sys
source = Path('Tools/InboxChecks/RestoreChecks.swift').read_text()
source = source.replace('read.blocks.allSatisfy { $0.inboxMembershipData == nil }',
                        'read.blocks.map(\\.inboxMembershipData) == expected.blocks.map(\\.inboxMembershipData)')
source = source.replace('Private migration leaves all old membership fields nil', 'Private pre-Trash migration preserves every Inbox payload')
Path(sys.argv[1]).write_text(source)
PY
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/trash-restore-checks" \
  openlist/Model/*.swift Shared/ListAccent.swift Shared/ReviewSession.swift Shared/AppGroup.swift openlist/Design/Theme.swift \
  openlist/Services/LibraryBackupPackage.swift openlist/Services/BackupStagedStore.swift openlist/Services/BackupSnapshotReader.swift openlist/Services/LibraryRestoreStorage.swift \
  openlist/Services/MediaStore.swift openlist/Services/BlockTree.swift openlist/Services/ICloudConfiguration.swift openlist/Services/ICloudError.swift \
  -parse-as-library "$OUT/RestoreChecks.swift"
mkdir -p "$OUT/Restore/Original"
"$OUT/pre-trash" "$OUT/Restore/Original/Openlist.store"
"$OUT/trash-restore-checks" "$OUT/Restore" restore
"$OUT/trash-restore-checks" "$OUT/Restore" return
