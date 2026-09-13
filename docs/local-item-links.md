# Local item links

Copy Link in a task menu or inspector, a list menu, gallery card, or sidebar
copies a URL for that identity. Openlist resolves the current task/list when
the link is opened, so renaming a task or moving it to another list does not
change its link. Duplicating a task/list gives the copy fresh item IDs; old
links continue to open the original.

Links work on the same Mac and in the same local library. They do not share
content, grant access, contact a server, or locate a library on another Mac.
An archived target opens with an explicit archived notice and stays archived.
A completed or nested task uses the same temporary exact-content reveal as
search, without rewriting completion visibility or collapsed ancestors.
Finish ends the temporary reveal. Missing, deleted, changed-to-text, and
wrong-library targets explain why they cannot open. There is currently no
Trash feature; a future Trash target must stay unavailable until it is restored
through an explicit action elsewhere.

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
normal system behavior.

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

Apple documents the UUID's copy behavior in
[NSStoreUUIDKey](https://developer.apple.com/documentation/coredata/nsstoreuuidkey).
The URL entry follows SwiftUI's
[external-event scene routing](https://developer.apple.com/documentation/swiftui/scene/handlesexternalevents(matching:)).
