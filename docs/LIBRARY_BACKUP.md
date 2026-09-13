# Manual library backup and restore

Settings > Data provides **Back up library** and **Restore backup**. Markdown
export remains a readable document export; an `.openlistbackup` directory
package is the versioned reconstruction format.

Backups are **unencrypted**. They contain private task and note text, files,
labels, calendar history, and activity for subjects that may since have been
deleted. Store packages somewhere private. Clearing history or deleting data
in Openlist does not erase previously exported backups or retained recovery
files. There is no automatic backup schedule, retention cleanup, encryption,
cloud backup destination, third-party import, or merge import in this slice.

## Snapshot boundary

The app commits current editing drafts before export. An independently owned,
read-only Core Data coordinator uses the public SwiftData model bridge and a
pinned query generation to read all record types. Changes committed after the
snapshot begins are not included. Export does not copy a live SQLite file,
change CloudKit configuration, or mutate source records.

Core Data can remove an old external blob during concurrent replacement or
deletion even while its row generation is pinned. The reader first fetches the
IDs with non-null stored media attributes in that same generation and requires
all those payloads to hydrate. Missing expected bytes abort export; they never
fall back to potentially newer cache files. Only records whose persisted bytes
were originally nil can read their legacy local file. Missing legacy files
also stop the export. Retry after synchronization finishes.

A synchronized library backup describes the committed, complete local library
on this Mac, not a promise that all server changes have downloaded. Unresolved
live references—including an Inbox alias whose destination has not arrived in
a CloudKit import—fail validation. Wait for synchronization and retry. No
cloud account or real CloudKit transfer is exercised by the offline tests.

## Version 1 contract

`manifest.json` records the format version, library UUID, creation time, library
checksum, and media filenames, sizes and SHA-256 digests. `library.json` contains
explicit records. Files live under `Media/<digest>`; user filenames are metadata
and are never interpreted as package paths. Package readers use `openat` and
`O_NOFOLLOW`, reject symlinks/non-files/traversal, and verify bytes before preview.
The package is staged in the system-provided item replacement directory on the
destination volume, then published with a coordinated, exclusive rename only
after successful readback. This respects the save panel's sandbox grant.
Existing destinations are never replaced. A process interruption may leave
system-managed staging data, but not a successful-looking destination.

The contract includes every persisted property of all nine current model types:

| Records | Included state |
| --- | --- |
| TaskList | IDs, Inbox/alias identity, archive, title/summary, icon/color, ordering, section and display/availability preferences, timestamps |
| Block | IDs, hierarchy, rich/plain text, all task/recurrence/reminder/calendar payloads, labels, media and timestamps |
| SidebarSection and TaskLabel | IDs, names/colors, ordering, collapse/default/alias state and timestamps |
| Attachment | IDs, owning task, filename/display metadata, exact bytes, ordering and timestamps |
| ActivityEvent | IDs, full history including old snapshots and undecodable legacy detail bytes |
| WorkSession and CompletionRecord | IDs, occurrence and historical subject references, times, corrections, planned intervals and snapshots |
| SchedulePlacement | IDs, task/occurrence reference, explicit preferred/pinned intervals |

Parent and alias cycles, duplicate model IDs, missing live relationships and
unsupported values are rejected. Historical activity/work/completion/placement
references may outlive their subjects and are retained. Legacy file-only media
are embedded into the restored record, preserving the file bytes. Attachment
`byteCount` must match the actual file bytes; a mismatch is reported, not silently
rewritten. New model types or persisted fields must update this versioned
contract; schema-coverage tests fail if a property is omitted. Future Trash
records must join this all-record path, not a visible-task query.

Portable settings include completed-task visibility, date parsing, default task
destination, list-deletion confirmation, first weekday, Today/Lists sorting, and
calendar estimates, availability, breaks and date overrides. Excluded current-Mac
state includes appearance, window layout, menu-bar/hotkey controls, device ID,
permissions, external-calendar connection/selection, MCP credentials/configuration,
notification delivery state and synchronization configuration. Device IDs inside
historical work records remain historical facts.

The first version supports up to one million records, 64 MB of JSON metadata,
128 MB per media asset and 256 MB of media in a package. Validation and package
I/O run outside the UI actor. These are format limits, not a claim of measured
performance at every maximum.

## Replace, quit, and recover

Choosing a backup only validates it and displays a preview. **Restore and Quit**
is explicit replacement confirmation. Open Openlist again after it quits to
finish. It builds a separate local-only generation; it does not reset, replace
or merge the original cloud library. The staged store adopts the original
backup's library UUID through public metadata APIs while closed, preserving
local task/list links along with item UUIDs.

The quit request waits for confirmation dismissal and enters AppKit from a
normal run-loop callback, so the delegate can finish its asynchronous final save
and reminder drain. Save failures keep the pending restore and show a retry or
cancel action; they do not force the application to close.

On the next launch, before any app or CloudKit container opens, the app verifies
the staged store fingerprint, creates a logical pre-restore backup, then writes
one atomic library-selection record. The original database and media remain
untouched. A failed pre-commit attempt retains the old selection. Interruption
after selection replays the complete new selection on the next launch. Selected
stores are checked again at the actual container factory; a missing or unreadable
selected store cannot silently become an empty library.

Portable preferences apply before observers are created, once per selection UUID.
An interruption during preference application replays all keys; later ordinary
launches preserve preference edits. The selected generation owns its media cache.
Before any environment/publisher is constructed, a changed selection invalidates
task reminder state and submits removal of old task and calendar notifications.
Widgets and eligible future reminders are rebuilt from selected saved records;
past reminders do not replay. A separate selection marker is written only after
the reminder reconciliation pass finishes without a global read/recovery error.
An interruption after journal cleanup still repeats the reset if that marker is
missing. OS removal APIs have no completion callback; this is an idempotent
reset/reconciliation boundary, not a guarantee of notification display. Review
sessions never call OS notification APIs.
A restored open work session is paused at its last
recorded heartbeat rather than claiming work continued after the backup. The
original backup bytes and history are retained.

**Return to original library** selects the retained original store and its
preferences after quit/reopen, including its previous iCloud behavior. Changes
in the restored library are not merged. A readable departing library gets a
recovery backup. If the restored store is unreadable, explicit return can still
open a verified original; it retains the unreadable files and reports why a new
logical backup could not be created. Startup errors expose pending-restore cancel
and original-return actions as applicable.

**Show recovery files** opens `LibraryRecovery` beside the original store.
`Backups` holds logical pre-restore packages; `Generations` holds restored stores
and their own caches. These are retained until deliberately removed outside the
app; there is no automatic cleanup policy. Do not remove the selected generation.

## Validation

`Tools/run-library-backup-checks.sh` uses only generated isolated libraries. It
checks complete DTO/schema coverage; archive, nested rich content, UUIDs, large
external storage, legacy files and history; malformed paths, versions, references,
checksums and symlinks; failed publication/staging; restart journal interruption,
settings replay, original return, and recovery from a damaged generation. A
separate process reopens the reconstructed SwiftData store and compares records
and library identity. Native chooser, preview/cancel and actual quit/relaunch
validation must be recorded separately from these automated checks.
`Tools/run-application-quit-checks.sh` additionally runs real windowless AppKit
processes to verify asynchronous termination replies, cancellation and retry.
