# Manual library backup and restore

Settings › Data provides **Back up library…** and **Restore backup…**. Markdown
export remains a readable document export; an `.openlistbackup` directory
package is the versioned reconstruction format. Current exports use format 5, including retained legacy Inbox metadata, Trash, covers, and list ownership. Formats 1–4 upgrade explicitly; Inbox visibility follows ownership, never the legacy metadata. An older already-queued restore must be cancelled and its backup selected again so that the staged schema and fingerprint can be revalidated.

Backups are **unencrypted**. They contain private task and note text, files,
labels, calendar history, and activity for subjects that may since have been
deleted. Store packages somewhere private. Clearing history or deleting data
in Openlist does not erase previously exported backups or retained recovery
files. There is no encryption, cloud backup destination, third-party import, or
merge import.

**Back up library** under Settings › Library also takes a snapshot package each
day by default, keeping the newest 14 in Openlist's Application Support
`Backups` folder, and offers **Back up now…** and **Show Snapshots in Finder**.
Only packages named like a snapshot are listed or pruned.

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
required live references—including an Inbox alias whose destination has not arrived in
a CloudKit import—fail validation. Wait for synchronization and retry. No
cloud account or real CloudKit transfer is exercised by the offline tests.

## Current format contract

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
| TaskList | IDs, parent document ownership, Inbox/alias identity, own archive choice, Trash group/recovery metadata, title/summary, icon/colour, cover metadata and bytes, ordering, section and display/availability preferences, timestamps |
| Block | IDs, hierarchy, rich/plain text, all task/recurrence/reminder/calendar payloads, labels, media and timestamps |
| SidebarSection and TaskLabel | IDs, names/colours, ordering, collapse/default/alias state and timestamps |
| Attachment | IDs, owning task, filename/display metadata, exact bytes, ordering and timestamps |
| ActivityEvent | IDs, full history including old snapshots and undecodable legacy detail bytes |
| WorkSession and CompletionRecord | IDs, occurrence and historical subject references, times, corrections, planned intervals and snapshots |
| SchedulePlacement | IDs, task/occurrence reference, explicit preferred/pinned intervals |

Block parent and alias cycles, duplicate model IDs, missing required live relationships and
unsupported values are rejected. Historical activity/work/completion/placement
references may outlive their subjects and are retained. Legacy file-only media
are embedded into the restored record, preserving the file bytes. Attachment
`byteCount` must match the actual file bytes; a mismatch is reported, not silently
rewritten. New model types or persisted fields must update this versioned
contract; schema-coverage tests fail if a property is omitted. Nested list references
may remain unresolved during sync and are retained; imported list cycles remain
recoverable through the bounded hierarchy display. Retained document groups
must connect to their own Trash root without crossing document boundaries.

Portable settings include completed-task visibility, date parsing, default task
destination, list-deletion confirmation, first weekday, the previous design's
Today and Lists sort choices (carried and validated, though nothing reads them
now), and calendar estimates, availability, breaks and date overrides. Excluded current-Mac
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

Cold startup reads use a disposable framework-managed copy: Core Data's public
`replacePersistentStore` API opens the closed source read-only and copies its
store family into a private temporary directory. The same logical reader pins
the copy with persistent-history tracking enabled, which permits the initial
WAL bookkeeping required for a cold SwiftData store. Only that disposable copy
is writable; no CloudKit container, app bootstrap, or source migration runs.
Its UUID, schema, every record and expected payload are validated before use,
and scratch files are removed on success or a thrown failure. A process kill
can leave the private system-temporary directory for operating-system cleanup.
Original database, WAL, and external payload contents stay unchanged; SQLite
may update transient SHM read marks. Live export continues to use its original read-only pinned reader.

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
preferences after quit/reopen, including its previous iCloud behaviour. Changes
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

## Inbox schema upgrade

Format 2 adds the optional Inbox membership payload. Closed-store recovery recognizes the exact immediately previous schema by its public Core Data model hashes. It copies that source with read-only Core Data options, checks private file ownership, runs supported lightweight SwiftData migration only on the disposable copy with CloudKit disabled, checks the resulting files again, and validates every current DTO through the pinned reader. Database identity is checked before and after. The original database, WAL and external media are never migrated during preflight.

This also permits Return to the original library after only the selected restored generation has upgraded. Once original selection is committed, the ordinary app container performs its normal migration. A queued but not yet activated restore prepared by the old app is rejected with a cancellation/reselect action so its staged schema and fingerprint are rebuilt from the valid version 1 package. An unknown newer or unrelated schema is not guessed or migrated.


## Nested document schema upgrade

Format 5 adds optional `TaskList.parentListID`. Cold reads recognize the exact
pre-nesting, pre-cover, pre-Trash, and pre-Inbox schemas. The nine-model
pre-nesting migration matrix verifies private restore and cold Return while
leaving every authoritative original byte unchanged. Parent/child documents,
independent Trash groups, imported orphan references, and covers retain their
original IDs and bytes in logical backup. Run `Tools/run-nested-list-checks.sh`
for ownership, archive, copy/export, retention, late imports, and migration checks.


The startup-copy boundary follows Apple's public [store-copy guidance](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer)
and [SwiftData coexistence history requirement](https://developer.apple.com/videos/play/wwdc2023/10189/?time=376).
Separate-process closed-source checks compare all nine DTO types, all three external
payload attributes, source database/WAL/payload hashes, and scratch cleanup.

