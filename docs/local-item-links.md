# Local item links

Copy Link in a task menu (a row's, or Task ▸ Copy Link for the selected or
inspected task), a list menu, gallery card, or sidebar copies a URL for that
identity and says "Link copied" in the tray. Openlist resolves the current
task/list when the link is opened, so renaming a task or moving it to another
list does not change its link. Duplicating a task/list gives the copy fresh item
IDs; old links continue to open the original.

Links work on the same Mac and in the same local library. They do not share
content, grant access, contact a server, or locate a library on another Mac.
A link lands as a search result does: a task opens on its list, or the Inbox,
with its row focused and its inspector open, and a list opens at its top. An
archived target opens on its list page, which says it is archived, and stays
archived. Nothing is unfolded: a done task in a folded Completed group, or a
subtask under a folded task, stays hidden in the document while its inspector
opens, and stored completion visibility and collapsed ancestors never change.
Missing, deleted, changed-to-text, and wrong-library targets explain why they cannot
open. Tasks and lists in Trash stay unavailable until explicitly restored from
Trash or through deletion Undo.
The same saved link then works again. Following a link never restores content,
and restoring content does not replay a previously rejected link.

## Version 1 contract

Production registers only `openlist`; Openlist Dev registers only
`openlist-dev`. Both use this structure:

```text
openlist://v1/<library-uuid>/task/<task-uuid>
openlist://v1/<library-uuid>/list/<list-uuid>
openlist-dev://v1/<library-uuid>/task/<task-uuid>
```

Generated UUIDs are lowercase and hyphenated. The parser accepts upper/lowercase
UUIDs and schemes, but only the exact `v1`, `task`, and `list` route vocabulary.
Credentials, ports, query parameters (including an empty `?`), fragments,
percent-encoded route components, extra or empty path segments, non-task block
routes, and unknown versions are rejected. Input is never a command or file
path. Clipboard content contains only the version and opaque library/item
UUIDs, with no names, private paths, or authentication tokens.

The singleton main window receives URL events. Incoming deliveries wait for
both store bootstrap and the main window; the initial Today navigation runs
before the queue drains. A delivery is consumed once. Intentionally opening
the same link again creates a new reveal request. Links activated by the
existing rich-text editor use the same handler; other URL schemes retain their
normal system behaviour.

Plain task notes show explicit **Open task link** / **Open list link** buttons
below detected local references. Multiple references are numbered in note
order, with repeated URLs shown once. These controls use the same internal
handler without changing the note text, formatting, or editor selection.

## Library identity and backup/restore

The local SQLite store already persists a UUID. Openlist reads `NSStoreUUIDKey`
using Core Data's public `metadataForPersistentStore(type:at:options:)` API after
SwiftData opens the selected store, including an active restored generation.
This adds no synchronized model, preference, or
second identity file. No new or session UUID is substituted when reading
fails: copying and opening item links fail closed while existing content stays
available.

This is deliberately a local store identity, separate from CloudKit's account
or record IDs. Another Mac's independently created store is a different
library even when it synchronizes the same content. Development, production,
and isolated review stores have independent identities.

Full-library backup and restore preserve the store metadata UUID and item UUIDs,
so existing links remain valid when restoring that library at a different local
store location. Return to Original uses the original store's identity again.
Restoring a different full library adopts its identity, so links from the
previously selected library are rejected even if item UUIDs happen to match.
A newly created library or a future content import into another library must
keep that destination's distinct identity. A literal
file copy of a database preserves its UUID: such copies are the same logical
library for link purposes, and whichever copy is installed in the app's active
store location is the one that opens. This feature does not discover or choose
between copied databases. An explicit future “duplicate as independent library”
operation must assign a new identity while the store is closed, using supported
metadata APIs, before generating any links.

Apple documents the UUID's copy behaviour in
[NSStoreUUIDKey](https://developer.apple.com/documentation/coredata/nsstoreuuidkey).
The URL entry follows SwiftUI's
[external-event scene routing](https://developer.apple.com/documentation/swiftui/scene/handlesexternalevents(matching:)).

Owned child documents keep their own list UUIDs in links. Moving or renaming a
child never redirects its saved URL to its parent. Opening an archived child's
URL reports archive inherited from any ancestor; a retained ancestor makes the
child unavailable until restoration. A genuinely missing parent preserves the
child's recoverable document access and its original ownership reference.
