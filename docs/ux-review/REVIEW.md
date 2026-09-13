# Openlist UI and UX review

Reviewed September 13, 2026 against `088d5f4`, with implementation in `codex/ui-ux-review`.

## Design direction

Keep the app's quiet document canvas, native sidebar and list accents. Make capture one deliberate, lightweight action; preserve the user's insertion point; reveal secondary controls only when they are useful. Use native macOS materials for navigation and transient surfaces, readable task content, and motion that explains an actual state change. Avoid decorative animation, permanent empty forms, competing add actions, and controls that shift under the pointer.

This review combines source inspection, isolated persistence/editor checks, and native interaction with an ad-hoc signed Debug build. The final review app uses `OpenlistReviewSession=ux-review-final-20260913`, separate preferences and sample data under Application Support/Openlist-UIReviews; it disables CloudKit. Existing installed apps and personal lists are not the review fixture. The Debug fixture resolves its own storage before requesting the installed app's protected App Group container.

## Findings and decisions

| Priority | Area / source | Finding | Resolution |
| --- | --- | --- | --- |
| P1 | `TaskDetailPanel.swift` | Tasks → Cmd-N → Escape crashed. The stack reads `Block.labelIDs` from a deferred `DetailRow` content closure after deleting the empty capture. | Build row content eagerly, guard invalidated models, and replace empty persisted task capture with a value draft. Native old-path cancellation passed after the inspector fix. |
| P1 | `DocumentView.swift`, `BlockTextView.swift` | `/` on the last task draws a menu over previous tasks and the typing line. Placement used the row origin plus caret X, discarded caret Y, and clamped to document height with a hardcoded menu height. | Anchor to the actual text view/caret and visible scroll viewport; measure the popup and choose above/below placement. |
| P1 | Editor focus | Choosing a slash command or indenting reset the caret to the end. Selection replacement and deferred focus can also target stale positions. | Preserve insertion/selection offsets and validate deferred focus requests. |
| P1 | Capture entry points | Cmd-N creates an empty task immediately; list creation is inline; Quick Add and Cmd-K have different destination and feedback behavior. | Share a draft-based capture UI, visible searchable destination, Inbox fallback, optional current-list suggestion, metadata preview, and success/error states. Return inside a document remains inline block creation. |
| P1 | Capture surface sizing | The shared Quick Add content could be compressed to its minimum height, clipping its header and Add task footer when preview chips appeared. | Request the capture content's ideal vertical size in both the window and sheet. Native screenshots verify the whole form and footer remain visible. |
| P1 | Capture caret | Returning from destination search selected the entire title, so typing replaced the draft. SwiftUI TextSelection restoration was overridden by the native field editor's focus behavior. | Use a dedicated plain-text NSTextView, preserving its actual UTF-16 selected range and typing undo. Native insertion, selected-substring replacement, and Return/Shift-Return behavior pass. |
| P2 | `RootView.swift`, `SmartTaskRow.swift` | Three columns become cramped at narrow widths. Metadata consumes title width; a hover-only details button changes row geometry. | Adapt row layout without recreating title fields, reserve the details affordance, reduce gutters with available space, and yield the sidebar for a narrow inspector. |
| P2 | `TaskList.swift`, `ListScreen.swift`, `AppSettings.swift` | Global completed visibility affected only Inbox/Today; ordinary lists used independent Booleans. The per-list action was hidden in the ellipsis menu. | Discoverable Completed count/Show/Hide control and explicit inherit/show/hide policy. Keep completed tasks with their original notes, parents and descendants; the later completion follow-up places each completed branch below pending siblings. |
| P2 | `TasksScreen.swift` | Filter menu worked, but visible constraint text looked like controls while being noninteractive. | Make status, list and grouping directly actionable. Add clear/reset actions and remove the redundant duplicate filter menu. |
| P2 | `InboxScreen`, `InboxReviewView` | Inbox was an ordinary document with no guided way to process captures. | Optional review queue for moving, scheduling or consciously keeping tasks, with remaining count and undo. Scheduling keeps the task in Inbox; this is stated in the interface. |
| P2 | `TaskDetailPanel.swift` | Every empty scheduling/tag field, empty note editor, attachment placeholder and destructive footer competes with the title. | List and Due first; active metadata visible; secondary fields in More details; Add note and Attach file actions instead of empty input blocks. |
| P2 | `SettingsView.swift` | Six cramped fixed-size panes mix preferences with diagnostic explanations and repair actions. | Modern Tab API, flexible sizing, concise settings, collapsed sync explanations and reminder troubleshooting. |
| P2 | `AppCommands.swift`, `ShortcutsSheet.swift` | Commands can be enabled with no meaningful target; keyboard help is large and fixed-size. Cmd-K prioritizes creating a task even for an exact navigation match. | Context-aware availability, central capture, explicit editing semantics, improved palette ranking and adaptive help. |
| P2 | Motion and accessibility | Small checkbox/collapse effects exist, but state transitions are inconsistent and several custom animations ignore Reduce Motion. Hover affordances and symbolic-only labels weaken keyboard/VoiceOver discoverability. | Restrained changes tied to completion, group changes, disclosures and capture feedback; Reduce Motion checks; stable, named controls. |
| P1 | Window lifecycle | Capture's Open Task action and repeated New Task commands created duplicate main windows sharing one navigator. A blank title also obscured the Window menu entry. | Use a named singleton `Window` for the shared navigator. New Task restores a minimized window and presents capture; closing capture returns to the previous Inbox state. |
| P2 | Editor optical alignment (follow-up) | Text and `/` sit low inside the selected row: `lineHeightMultiple` adds leading before the baseline, while editor height uses the font's unrelated glyph bounding box. Heading section margins also sit inside the highlight; hover actions can change available text width. | Use natural TextKit line metrics with equal vertical insets and inter-line spacing. Keep heading margins outside the highlight and reserve the trailing action width. Native screenshots and 13 additional metric/caret checks cover this correction. |
| P2 | Completion feel (follow-up) | The system Tink sound feels delayed; completed tasks stay mixed among pending tasks, and the checkbox change is abrupt. | Remove completion audio, its setting and its callback. Add a brief checkmark bounce and fading ring, then spring the completed branch below pending siblings. The projection preserves manual order, parentage, notes and nested content. |

## Closure status

All implementation changes in the findings table are present in the review branch. This is not a claim that every visual detail was caught or every platform behavior was tested: the optical alignment defect above was missed in the original pass and corrected after user feedback.

| Scope | Status |
| --- | --- |
| Crash, editor caret, slash placement, unified capture, destination selection, capture sizing and single-window behavior | Implemented; automated checks and native journeys passed |
| Completed visibility, interactive filters, Inbox review, responsive rows, settings and detail hierarchy | Implemented; source review and relevant native journeys passed |
| Editor optical alignment and heading highlight bounds | Corrected in the follow-up; measured checks and native screenshots passed |
| Silent completion, pending-first ordering and restoration on reopen | Implemented; native motion frames, completion/reopen, nested ordering and recurring-task journeys passed |
| Context-aware shortcuts and command ranking | Implemented; Command-K and capture keyboard journeys passed. Existing Ctrl-D/L/T mappings retained for compatibility; their remapping remains a product decision |
| Reduce Motion and accessibility labels | Implemented and source-reviewed; physical VoiceOver and system Reduce Motion behavior remain unverified |
| Global Quick Add hotkey, live CloudKit, release signing/notarization, frame-time profiling | Not validated by this UI review |

## Modern SwiftUI decisions

- Retain `NavigationSplitView`, `.inspector`, Observation, SwiftData and native toolbar controls. AppKit remains justified for the outliner: SwiftUI TextEditor cannot provide its full structural keyboard behavior.
- Use `AnyLayout` to rearrange row children without replacing the title editor when width changes.
- Adopt the modern `Tab` API for settings. Use native materials and semantic foreground styles; do not add glass cards to every task.
- Keep model-reading closures short-lived. Never animate retained, deleted SwiftData model views indiscriminately.
- Use `accessibilityReduceMotion` for custom transitions and `Button`/`Menu` labels for actions.
- Keep the deployment target at macOS 26.5. Building with Xcode 27 does not justify silently raising the supported OS version.

Apple's guidance supports allowing standard components to inherit the platform's current design, grouping toolbar actions by purpose, and sizing windows from content constraints: [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass), [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/), [WindowResizability](https://developer.apple.com/documentation/swiftui/windowresizability).

## Migration and behavior contracts

- The completed preference adds an optional CloudKit-compatible attribute. Historical `false` preserves Hide. Historical `true` becomes Use app default because the old schema cannot distinguish a deliberate Show from its default. Inbox inherits by default. Explicit overrides and duplication persist.
- App-wide preferences remain per Mac; list overrides are model data. Offline migration checks do not prove production CloudKit schema deployment or physical cross-device synchronization.
- Destination suggestions are explicit and context-based. No semantic guess silently files a task. The default remains Inbox until the user picks another destination.
- Existing Ctrl-D/L/T task shortcuts remain for compatibility and are scoped by target availability. They are less idiomatic for native text editing than Command-based shortcuts; changing established mappings is a separate product decision.
- The completion follow-up supersedes the original decision to leave completed tasks at their exact manual position. Completed branches now appear below pending siblings at each outline depth. The stored order is unchanged, so reopening restores the manual position. Ordinary sibling prose remains in its document order; notes that must travel with a task remain its children or task note field. Repeating tasks stay pending for their next occurrence.

## Native evidence

- [Before: slash menu covers the editing line](evidence/before-slash-placement.png)
- [Before: task detail density](evidence/before-task-details.png)
- [Before: compact inspector](evidence/before-compact-inspector.png)
- [Before: settings](evidence/before-settings.png)
- [Before: capture preview clips the footer](evidence/before-capture-clipping.png)
- [After: simplified details](evidence/after-task-details.png)
- [After: completed visibility control](evidence/after-completed-visibility.png)
- [After: full-screen document measure](evidence/after-fullscreen.png)
- [After: slash menu above the caret](evidence/after-slash-placement.png)
- [After: wrapped-line slash placement](evidence/after-wrapped-slash.png)
- [After: compact inspector with sidebar yielding](evidence/after-compact-inspector.png)
- [After: focused Inbox review](evidence/after-inbox-review.png)
- [After: settings hierarchy](evidence/after-settings.png)
- [After: complete capture form and metadata preview](evidence/after-capture.png)
- [After: wrapped capture title with visible actions](evidence/after-wrapped-capture.png)
- [Before: editor optical alignment](evidence/before-editor-alignment.png)
- [After: slash aligned within the selected row](evidence/after-editor-alignment.png)
- [After: heading highlight excludes section margins](evidence/after-heading-alignment.png)
- [After: wrapped editor alignment](evidence/after-wrapped-editor-alignment.png)
- [Completion: before marking a task done](evidence/before-completion-move.png)
- [Completion: immediate acknowledgement](evidence/completion-motion-acknowledgement.png)
- [Completion: moving as one readable row](evidence/completion-motion-travelling.png)
- [Completion: settled below pending work](evidence/after-completion-move.png)

## Acceptance record

Native checks already passed during integration:

- Original Tasks filter opens, changes to Completed, and Reset returns to Open.
- Tasks → Cmd-N → Escape no longer crashes or leaves an empty task after the details fix.
- Global Hide removes completed nested work from Personal; per-list Show reveals Sourdough in the original parent hierarchy; Use app default hides it again.
- Inspector opens from a task's details button; compact task metadata moves below the title.
- Light and dark appearance both render with native materials and readable content.
- Full screen expands to a centered, bounded document measure; Exit Full Screen returns to the same list.
- Cmd-M minimizes the window. Cmd-N restores that same named `main` window and opens capture. Escape returns to the previous Inbox with unchanged task counts. Repeated capture/cancel cycles reuse the main window.
- Cmd-K → Today ranks Go to Today first; Return navigates without creating a task.
- Capture of “Review itinerary tomorrow #travel” previews the normalized title, date and label. Choosing Japan trip and saving adds one task there; Open task reveals Tomorrow and travel in its details.
- In the final native capture editor, place the caret before “omega” in “alpha omega tomorrow”, choose Reading, then type “NEW ”: the result is “alpha NEW omega tomorrow”. Selecting “omega”, removing the detected date and typing replaces only that substring. Shift-Return inserts a line without saving; Return saves once; Open task reuses the main window and Reading increases from 2 to 3.
- Quick Add and sheet capture both show their complete header, preview and actions. A four-line wrapped title grows the input and window without clipping the Add task footer. Cancelling the draft leaves list counts unchanged.
- Slash commands on the bottom row and a long wrapped line choose the available space above the caret. Mid-line `/h1` conversion preserves the suffix: typing resumes as “alpha NEW omega”. Escape dismisses the current command session; an outside click dismisses and reaches the target editor.
- Inbox review moves a task to Reading and Undo restores the original list/counts. Today schedules without moving out of Inbox. Keep advances the queue, with an explicit notice and Undo. The final review screen shows the queue on its own.

Automated validation:

- The combined `./Tools/check.sh` run exited 0: 71 logic checks, 14 splice checks, 64 editor/store checks, 28 capture/triage checks, 24 duplication checks, 28 export checks, 18 export integration checks, 34 lifecycle checks, 22 completed visibility/persistence checks, 193 migration/reopen checks, 36 signing checks, 20 transport tests, 261 MCP store/protocol checks and 40 helper packaging tests.
- Capture rollback checks deliberately use a read-only store and verify no task, label or event leaks. Corrupt-store and persistence-error output is expected from failure fixtures.
- Following the last native editor change, 12 additional hidden-window capture selection checks exited 0, covering exact selection restoration, Unicode offsets, metadata focus and Return semantics. This runner is now included in `Tools/check.sh`.
- The integrated arm64 Debug app builds with Xcode 27 (27A266a). Capture changes were also built for both supported Mac architectures in their implementation task.
- The alignment follow-up builds successfully and passes 77 editor/store checks (13 new checks). These measure optical centering for task, paragraph, three heading sizes and code; equal empty/populated row heights; and containment of a trailing-line caret. Native screenshots verify the selected slash row, heading highlight and wrapped paragraph. No full-suite rerun is implied by this focused follow-up.
- The same follow-up also passes 71 logic and 14 rich-text splice checks.
- The completion follow-up builds successfully and passes 85 editor/store checks and 34 lifecycle checks. Eight added ordering checks cover nested branches, attached notes, unchanged manual order, stable projection, reopening, collapse, empty documents and no lost/duplicated blocks.
- Native completion of Call Mum moves it below pending root tasks; reopening restores its place and task counts. Captured intermediate frames verify the acknowledgement and grouped row movement. The travelling row uses an opaque background and temporary stacking priority, avoiding text overlap. Geometry grouping keeps title, checkbox and chips together.
- Native completion of Oat milk places it below pending Sourdough while both stay under Do the weekly shop. Completing that repeating parent advances its due date from September 13 to September 20, keeps it pending and resets its subtasks for the new occurrence. Accessibility reports Pending/Completed from model state rather than the temporary visual acknowledgement.
- Completion audio, its settings property/key, playback callback and Settings toggle are removed. Native Settings shows Confirmations without the sound control. No notification/reminder audio behavior was changed. Reduce Motion disables the bounce, ring and row movement; this path was source-reviewed, not tested by changing system preferences.

Physical VoiceOver navigation, the system-wide Quick Add hotkey, production signing/notarization and live cross-device CloudKit synchronization were not validated. Reduce Motion handling was reviewed in code; system accessibility preferences were not changed. UI checks use native interaction and screenshots, not frame-time profiling. Historical explicit Show preferences cannot be distinguished from the old default, as described in the migration contract above.
