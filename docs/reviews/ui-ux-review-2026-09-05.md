# Openlist E2E UI/UX review — 5 September 2026

**Remediation:** implementation and follow-up verification are tracked in [UI/UX fixes](ui-ux-fixes-2026-09-05.md). The findings below describe the original reviewed build.

Reviewed commit `1436dad` using Computer Use against a fresh native macOS Debug build. This is a review, not an implementation of fixes.

**Verdict:** the core app is usable, but task-command targeting, scheduling side effects, export fidelity, and structural undo need attention before calling the experience reliable.

## Method and environment

- Built the `openlist` scheme with Xcode using `/tmp/openlist-e2e-review` as DerivedData. Build succeeded.
- Launched `/tmp/openlist-e2e-review/Build/Products/Debug/openlist.app` through Computer Use.
- Exercised real controls, keyboard shortcuts, native file dialogs, and window resizing. Inspected accessibility state and screenshots after interactions.
- Reviewed the app in its existing System/dark appearance at approximately 1162 × 768 and 923 × 649 window sizes. Opening the inspector at the smaller size expanded the window to accommodate its minimum width.
- Rendered Today, Summary, and Lists in WidgetKit Simulator at every supported size. Simulator Info confirmed the extension came from this review build.
- Ran the existing logic suite: **65 logic checks and 14 rich-text splice checks passed**. These are not E2E tests and did not catch the UI defects below.
- Reopened the app and verified the review list, Unicode, formatting, labels, dates, section name, and capture items persisted.

Native AX actions occasionally returned `AXError.failure` after completing the action, and native menus sometimes required Return after a click. State was re-read before proceeding. These automation behaviors are not reported as product defects.

## Prioritized findings

### 1. P1 — task shortcuts can act on the subtask while the parent title has focus

**Reproduced twice.** Open a task with a subtask in its detail panel. Click the subtask editor, then click the parent task title and press ⇧⌘S. The subtask's star changes; the parent's Star control stays off. The focused AX element is explicitly the parent title at the time of the command.

This makes keyboard actions unreliable when switching between parent metadata and nested content. Other commands share the same selection routing, so completion and scheduling need regression coverage too; those additional commands were not used to assert this defect.

**Code:** `openlist/Views/TaskDetailPanel.swift:92` only tracks title focus for saving, while `openlist/Editor/DocumentView.swift:694` resolves commands through the existing selection. Update the active command target and selection when the parent title gains focus. Verify title, note, subtask, list-body, and smart-view transitions.

### 2. P2 — opening Add date silently assigns Today

**Reproduced on two undated tasks.** Open details and click Add date. Before choosing a preset or calendar date, Add date becomes Today, a date chip appears in the list, and the Today count increases. Merely dismissing the picker does not undo the mutation.

**Code:** `openlist/Views/DueDatePicker.swift:38` and `:186`. `load()` changes mirrored state and sets `isLoaded` in the same update; the later change callbacks can see `isLoaded == true` and call `apply()`. Initialize the state without treating hydration as a user choice, or commit through explicit user actions.

### 3. P2 — Markdown export discards inline formatting and links

**Reproduced and verified in the saved export.** Applied bold and italic to “Review paragraph,” attached `https://example.com`, then exported through ⇧⌘E. The native editor and a duplicated list retain the styled link. The export contains only `Review paragraph`, with no emphasis markers or link destination.

**Evidence:** [saved export](openlist-e2e-export-2026-09-05.md).

**Code:** `openlist/Services/MarkdownExporter.swift:54` and `:73` serialize `block.text`, not the attributed content. Add an attributed-content-to-Markdown serializer and verify emphasis, strikethrough, inline code, links, escaping, and mixed runs.

### 4. P2 — structural block merge cannot be undone

**Reproduced.** In Inbox create “E2E merge first,” press Return, type “second,” move to the beginning, and press Backspace. The result is one task, “E2E merge firstsecond.” ⌘Z leaves that single task unchanged. Typing an additional suffix and undoing does work, so this is specifically structural undo.

**Code:** `openlist/Services/Store+Blocks.swift:445` merges content, reparents children, then deletes the second block at `:464`, without registering an inverse operation. The code also does not transfer the removed task's metadata or attachments here; that is a source-level risk, not an additional metadata-loss scenario exercised in this review. Use one undo transaction that restores both blocks and their relationships.

### 5. P2 — archived lists still contribute active tasks to Today

**Reproduced.** Archived “E2E Review 2026-09-05 copy” from the Lists gallery. Its sidebar entry disappeared and the gallery count dropped from six to five. Today still showed that list's due “Task epsilon” and starred “Nested detail child”; its count stayed unchanged. Show Archived and Unarchive successfully restored the list.

This undermines the expectation that archiving removes a project from active work. If this is intentional, the command needs a clearer name and explanation.

**Code:** `openlist/Views/TodayScreen.swift:28` buckets all queried tasks without excluding archived list IDs. Apply a consistent active-list policy to Today, Tasks, labels, badges, reminders, and widget snapshots.

### 6. P2 — date parsing differs between task-creation surfaces

**Reproduced.** With “Read dates from what you type” enabled, Quick Command correctly turns “E2E capture tomorrow at 6pm #e2e-review” into a labelled task due tomorrow at 18:00. In a label view, ⌘N opens a task title field; typing “E2E label task tomorrow” and pressing Return keeps “tomorrow” in the title and leaves Add date unset. Closing details and moving the task do not parse it.

**Code:** `openlist/Views/TaskDetailPanel.swift:93` only saves on submit/focus loss, whereas `openlist/Editor/DocumentView.swift:616` uses capture parsing. Share the appropriate commit logic for newly created task titles, with consistent preview and cancellation behavior.

### 7. P2 — search results lack the keyboard activation path used by Quick Command

**Reproduced.** ⌘F, enter Review, then Down and Return. Search remains open without navigating to a result. Clicking a result works, and Notes scope correctly narrows results. Quick Command supports Down/Return successfully.

**Code:** `openlist/Views/SearchView.swift:72` handles Escape, but has no result-selection/activation handling for these keys. Add selected-result state, visible highlighting, arrows, Return activation, and scroll-to-selection. Ensure initial field focus is reliable as well; the field needed an explicit click on one opening during automation.

### 8. P2 — compact Today widget breaks date labels and over-truncates tasks

**Visually reproduced in the current extension.** In the small Today widget, “Yesterday” wraps as “Yesterda” / “y,” while “Pay the electricity bill” and “Do the weekly shop” are reduced to “Pay t…” and “Do the…”. The medium and large versions are readable.

**Code:** `OpenlistWidget/OpenlistWidgetBundle.swift:201` gives the due text no line limit or compact layout treatment. Use a compact date format or a separate metadata line, and reserve useful width for the title. The small Summary widget also truncates “Done today” to “Done tod…”.

### 9. P3 — naming a new list and pressing Return leaves an extra blank task

**Reproduced at the start of the review.** A new untouched list already reads “0 of 1 done.” Naming it and pressing Return creates a second task; after entering a parent and one child, the count is three and a blank task remains.

**Code:** `openlist/Editor/DocumentView.swift:629` seeds an empty task; `openlist/Views/ListScreen.swift:73` sends another new-task command after naming. Focus the seed row instead, and avoid counting placeholder rows as unfinished work.

## UI/UX observations

- The dark UI has a consistent visual hierarchy and readable document width. Task details, metadata chips, and list appearance controls use the same visual language.
- Long list names are truncated to nearly identical sidebar labels: the original review list and its copy are difficult to distinguish there. Consider a full-title tooltip and a rename affordance.
- Active Tasks filters are hidden inside a single generic filter icon. A view can show “0 tasks” while filters are active without naming those constraints in the header. Visible filter chips and a reset action would improve recovery.
- Alphabetical sorting moves headings, quotes, prose, and tasks together. It works mechanically but breaks the reading order of a rich document. Explain the behavior, or constrain sorting to task runs.
- Many metadata labels use small, low-emphasis text. The screenshots were readable at this size, but a contrast audit and larger text configuration were not performed; no WCAG compliance claim is made.
- Several controls expose generic AX names: section disclosure is “Forward,” label-color controls can be unnamed, and the Star toggle is just “off.” These need explicit contextual accessibility labels. The shortcut sheet's AX reading order also interleaves its two visual columns.
- “This weekend” on Saturday 5 September offers 12 September. This is internally consistent with a strictly-next-Saturday calculation, but the wording can surprise someone planning the current weekend.
- Settings labels the permission action “Allow notifications” even when status says notifications are turned off in System Settings. The code requests authorization again rather than directing the user to settings; denied-permission recovery should be explicit.

## Coverage ledger

| Area | Exercised | Result / limitation |
|---|---|---|
| Build and startup | Current Debug build, first launch, quit/relaunch | Passed; no crash observed |
| Navigation | Inbox, Today, Updates, Tasks, Lists, label pages, Completed via palette | Passed |
| Window layout | Standard window, compact resize, open/close inspector | Readable; inspector expands window |
| Inbox capture | ⌘N, Return, ordinary text editing | Passed; merge undo finding above |
| Today | Overdue, due today, starred, completed buckets; dated test task | Passed except archive leakage; bulk reschedule of existing tasks not executed |
| Updates | Created, scheduled, starred, completed/reopened events; click-through | Passed; history clearing not executed |
| Tasks filters | Open, Completed, All, Starred, Scheduled, No date; filter to review list | Expected counts and empty state observed |
| Tasks grouping | Due date, List, Label, Priority, Flat | All exercised |
| Completed | Task complete/reopen and completed filter; archive navigation | Passed |
| Lists | Create, rename, description, icon, color, duplicate, archive/show archived/unarchive | Passed with findings noted |
| List sorting | Manual, Due date, Date created, Alphabetical, Priority; return to Manual | Exercised |
| Sidebar sections | Create, rename, empty section, context menu | Passed; drag result unverified |
| Block editor | Slash menu and filtering; task, headings, paragraph, bullet, numbered, quote, code, divider, image | Created/rendered representative block types; not every heading-level permutation |
| Rich text | Bold, italic, link dialog, mixed Markdown paste, Unicode, code text | Persisted in app; export loses inline styling |
| Hierarchy | Return, Tab/Shift-Tab, keyboard move, detail subtask, progress count, Backspace merge | Passed except structural undo |
| Task details | Title, note, star, high priority, labels, due date, repeat, reminder, list move | Exercised; target-routing and date findings above |
| Recurrence | Enable weekly, weekday preset, finite occurrence count, preview, completion rollover | Rollover observed; not every recurrence permutation in UI; logic suite passed |
| Reminders | Presets, custom date UI, denied-permission explanation, reminder chip and date shift | UI exercised; actual delivery blocked by existing notification permission |
| Labels | Create in picker and Settings; apply; populated and empty label views; contextual ⌘N | Passed; destructive label deletion not executed |
| Search | Matching content, Notes scope, clicked result navigation, Down/Return | Mouse navigation works; keyboard finding above |
| Quick Command | Task preview, NLP capture, labels, command filtering, keyboard navigation | Passed |
| Quick Add | Global shortcut, preview, Return save feedback, Escape close | Passed; resulting task verified in Inbox/Updates |
| Files | Attach via native chooser; image insertion via slash menu | Attachment filename/size and inline image rendered; opening/removal not exercised |
| Export | Native save dialog to `/tmp`, saved content inspection | File produced; formatting loss confirmed |
| Settings | General, Tasks, Labels, Data, scrolling, reset confirmation and Cancel | Reviewed all tabs; preference changes and actual reset not executed |
| Shortcuts | Reference sheet, scroll, representative menu shortcuts | Reviewed; AX column-order issue |
| Widgets | Today S/M/L, Summary S/M, Lists M/L, current extension path and live snapshot | Rendered; small-size findings above |
| Drag/drop | Multiple block and list-to-section drag attempts | No verified move; cannot distinguish gesture automation limitation from app defect |
| Menu-bar popover | Source inspected; keyboard focus and SystemUIServer access attempted | Could not access it through available Computer Use surfaces; not E2E-verified |
| Light mode / accessibility variants | Theme/source inspection only | Not visually tested; app preference left at System |
| Destructive actions | Reset confirmation inspected and cancelled; delete controls inspected | No permanent deletion, history purge, or reset executed |

This ledger is deliberately explicit: it is broad end-to-end coverage, not a claim that every state combination or destructive operation passed.

## Additional source-level risks

- Image export writes a relative storage filename but does not export the corresponding asset. File attachments are not rendered into Markdown either (`MarkdownExporter.swift:45`). The image/attachment UI was exercised, but a media-bearing export was not used to reproduce this separately.
- Export and import paths frequently use `try?`, so failures can appear to do nothing. Failed-write and failed-import scenarios were not injected.
- The app falls back to an in-memory store if opening the persistent store fails, without a visible warning (`openlist/openlistApp.swift`). A migration/store failure was not induced.

## Suggested fix order

1. Make the focused parent/subtask the unambiguous command target.
2. Stop date-picker hydration from mutating tasks.
3. Add structural undo with complete metadata/relationship restoration.
4. Preserve formatted content and assets in export.
5. Define and apply archive visibility consistently.
6. Align capture parsing and search keyboard behavior.
7. Fix compact widgets, placeholders, accessibility names, and filter discoverability.

## Review artifacts and test data

- [Export evidence](openlist-e2e-export-2026-09-05.md)
- [Existing check output](openlist-e2e-checks-2026-09-05.txt)
- UI screenshots are present in this task's Computer Use observations.
- Local build log: `/tmp/openlist-e2e-build.log`.
- Review data remains in the app: two E2E review lists, an E2E Review section, e2e-review/e2e-extra labels, and E2E capture/merge items. The copy contains test media and attachments, including an incidental `bounds.swift` selected during native file-picker automation before exact-path selection was used. No existing task was intentionally edited or deleted.
- Only review documents/evidence were added to the repository; application source was not changed.
