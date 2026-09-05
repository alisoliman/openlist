# Openlist UI/UX remediation — 5 September 2026

Follow-up to [the original E2E review](ui-ux-review-2026-09-05.md), implemented in the same worktree. The original report remains a historical record of the reproduced defects.

## Changes and verification

| Finding | Implemented behavior | Verification |
|---|---|---|
| 1. Parent/subtask shortcut target | Focusing an inspector title, note, or metadata changes the command target to the parent. Smart-view task fields also reset stale document selection. | Native: focus child → parent title → Star updates parent; child → parent note → Due Today updates parent; parent completion targets parent and cascades through children as designed. |
| 2. Date picker mutates on opening | Explicit user bindings commit dates; loading due-date/recurrence state does not save. | Native: undated parent opens and dismisses Add date with no date chip or count change. Current Saturday's This weekend shows Sep 5. Date logic regressions cover weekend boundaries. |
| 3. Markdown loses rich text | Attributed content exports emphasis, strike, code, links and escaping. Images and attachments export into a sibling assets folder with portable links. | Export regression suite covers mixed runs, nested formatting, links, unusual filenames, asset collisions, failed writes and cleanup. Native export was interrupted by the Mac locking; no successful native media export is claimed. |
| 4. Structural merge lacks undo | Window undo manager now records split, merge, indent/outdent, paste, drag/drop and context-menu structural operations. Cross-list moves include both lists. Restores metadata, relationships and media bytes. Merges transfer compatible task details and attachments; conflicting schedules/status leave both rows unchanged with a notice. | Native: merge → Undo → Undo typing → Redo twice; type after merge → Undo typing → Undo merge. Model tests cover attachments/images, redo, cross-list descendants, conflicting schedules, first-row Backspace and permanent-list deletion protection. |
| 5. Archive leakage | Shared active-list policy controls Today, Tasks, labels, Completed, badges, menu bar and widget snapshot. Archive/unarchive cancels/restores eligible reminders. | Native: archive starred review list; Today count drops 4→3 and its task disappears. Visibility tests include disk reopen; reminder scheduling checked with isolated service stub. |
| 6. Inconsistent task title parsing | New inspector captures share date/label/recurrence parsing with other capture surfaces and show a preview plus Keep as text. | Native: Tasks → New task → `Inspector capture tomorrow at 6pm #review` → Return yields title `Inspector capture`, Tomorrow 18:00 and review label. |
| 7. Search keyboard navigation | Search focuses its input, highlights selected result, supports arrows/Return, scrolls selection and resets it when query/scope changes. | Native: ⌘F → type Merge without extra click → Down → Return opens matching task details and closes Search. |
| 8. Compact widgets | Small Today uses two multiline titles with metadata underneath. Small Summary gives labels full column width. | WidgetKit verification is recorded in the native follow-up artifact. |
| 9. Phantom initial task | Empty documents show an add affordance without persisting/counting a placeholder row. | Native: new list initially shows 0 open tasks; naming + Return + two task titles gives exactly 2 tasks. |

## Other actionable observations

- Full-title sidebar tooltips and Rename List distinguish long list names.
- Tasks shows active status/list/grouping constraints and a Reset filters action.
- Sorting applies only to contiguous task runs, preserving surrounding headings and prose.
- Contextual labels cover section controls, task completion/star/date clearing, labels and shortcut groups. Shortcut rows expose action and key together.
- Current-weekend date interpretation now includes today on Saturday/Sunday. Calendar-day arithmetic replaces fixed 24-hour assumptions in Today/badge/widget cutoffs.
- Denied notification permission provides an Open System Settings action and refreshes status on app activation.
- Import/export errors are visible. Media duplication stages all files first, cleans partial copies on failure and never silently shares owned files. Successful copies retain attachment metadata.
- Persistent-store failure shows a temporary-session warning; save errors show a retry banner. The original persistent store is preserved.
- Clearing Updates history now removes all events, including entries older than the previous 10,000-event limit. A 10,001-event regression reproduces the old failure and verifies the fix.
- Cancelling an unchanged empty inspector capture removes that placeholder and its creation history. Existing blank tasks and captures with notes, files, children or modified metadata remain.

## Isolated native environment

Built app and widget with Xcode Debug under `/tmp/openlist-ui-fixes-integration`. Copied the signed result to `/tmp/openlist-ui-review-isolated/openlist.app`, set `OpenlistReviewSession=fixes-20260905` in both app and widget Info.plists and re-signed with the existing development identity.

The Debug-only review marker separates the store, widget snapshot, media directory and preferences. The app opened with fresh sample fixtures; the original E2E lists and real user store were not used for destructive validation. All native actions used Computer Use. File inspection, compilation and isolated model checks used command-line tools. The latest signed package, including the final focus guard, is ready at `/tmp/openlist-ui-review-ready/openlist.app` for the remaining native checks after unlocking.

## Validation and limits

The original broad coverage ledger still applies to unchanged surfaces. This pass targets every reported defect and records additional gaps explicitly rather than claiming all possible state combinations.

- Real OS notification delivery remains dependent on the existing macOS permission state; scheduling policy is covered with an isolated stub.
- Persistent-store open failure was not induced in the native UI; the warning path is source-reviewed.
- Permanent UI deletion/reset is not performed against the user's normal store. Isolated model lifecycle checks cover the underlying data operations.
- Native menus occasionally return accessibility errors after executing. State is refreshed before continuing; these tool behaviors are not counted as app failures.

### Automated validation

App and widget Debug build succeeded. `git diff --check` passed. **228 checks passed** across these scripts:

| Command | Checks |
|---|---:|
| `Tools/run-logic-checks.sh` | 71 date/recurrence + 14 rich-text splice |
| `Tools/run-editor-checks.sh` | 31 editor/store |
| `Tools/run-export-checks.sh` | 28 rich-text/media export |
| `Tools/run-export-integration-checks.sh` | 18 full Store → MarkdownExporter integration |
| `Tools/run-visibility-checks.sh` | 10 archive visibility/disk persistence |
| `Tools/run-duplication-checks.sh` | 22 media ownership/failure handling |
| `Tools/run-lifecycle-checks.sh` | 34 lifecycle checks across three fresh processes |

The lifecycle suite uses a temporary on-disk SwiftData store and isolated media. It verifies list/block/attachment/label/section deletion, unrelated data preservation, reminders, Unicode/rich text/metadata/relationships after reopening, reset composition, and the next launch after reset. Native confirmation wiring is not represented by these model tests.

The full export integration suite uses the actual Store and MarkdownExporter with rich linked Unicode text, task notes/metadata, an inline PNG and a binary attachment. It verifies all relative links, byte-for-byte assets, relocation of the Markdown/assets package, unchanged source data and failed-write preservation/cleanup. This covers the full export engine without claiming the interrupted native file-dialog flow passed.

See [native verification](ui-ux-fixes-native-2026-09-05.md) for screenshots' observed results, exact widget provenance, tested cancellation flows and outstanding coverage. The Mac locked during final file-dialog testing, and Computer Use could not automatically unlock it. Manual unlock was requested. Remaining native checks are media export completion, light mode, drag/drop, menu-bar capture, and the final focus guard; OS notification delivery also depends on existing permission. These are explicit coverage limits, not passing results.
