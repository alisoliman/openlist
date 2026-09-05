# UI/UX fixes — native verification, 5 September 2026

## Main app verification

Computer Use exercised the Debug app in isolated session `fixes-20260905`. Later native checks used `/tmp/openlist-ui-review-final/openlist.app`; its normal user store was never selected for this pass. The latest source, including the subsequent focus guard, is packaged at `/tmp/openlist-ui-review-ready/openlist.app` and has not yet been relaunched natively.

| Flow | Observed result |
|---|---|
| New list | Untouched list shows zero tasks. Naming + Return, then entering two task titles, gives exactly two rows. |
| Structural undo | Merge `Merge first` + `Second`; Undo restores two rows. Another Undo removes prior typing from Second. Redo twice restores the merge. Typing a suffix after merge, then undoing suffix and merge, also restores both original rows. |
| Parent command target | Child editor → parent title → Star updates the parent toggle. Child editor → parent note → Ctrl+T schedules the parent. Parent completion targets the parent and completes its child according to existing cascade behavior. |
| Due picker | Add date opens and closes on an undated parent without scheduling it. The Saturday This weekend preset reads Sep 5. |
| Inspector capture | Tasks → New task → `Inspector capture tomorrow at 6pm #review` → Return produces `Inspector capture`, Tomorrow 18:00 and review label. |
| Search | Cmd+F accepts typing without an extra click; the result is highlighted; Down/Return closes Search and opens the matching task. |
| Archive | Archiving the starred verification list removes it from sidebar/Today and changes Today count from 4 to 3. Its archived state survived launch of the later build. |
| Cancel empty capture | Today Cmd+N temporarily changes Inbox/Today counts 3→4. Escape closes the inspector and restores both counts to 3 without leaving Untitled. |
| Keep as text | A new task `Keep literal tomorrow` exposes the option; activating it and pressing Return leaves the title literal and Add date unset. |
| Escape inference cancellation | Enter `Escape literal tomorrow`, press Escape, then find/open it through Search. The literal title persists, with Add date still unset. |
| Rich text and Unicode | Pasted `Bold linked task café 日本語`, applied bold and a link to `https://example.com/review`. Native AX confirms the styled linked text. Clipboard paste was used because key-by-key typing did not enter non-ASCII characters reliably. |
| Relaunch persistence | The later isolated bundle reopened the archived fixture state, review label, and parsed inspector task with its scheduled date. |

An additional focus issue was observed after empty-capture cancellation: AppKit selected the first smart-row title. The final source re-arms selection protection after inspector dismissal and retries when the query/focus arrives. That final small change builds, but native re-verification was blocked by the lock described below.

### Interrupted native coverage

The Mac locked while the native attachment/export file dialog was being exercised. Computer Use reported that automatic unlock failed; manual unlock was requested. Consequently, **no successful media-bearing native export is claimed** in this pass. Renderer/package/failure paths are verified separately by automated tests.

The temporary export fixture contains an incidental `openlist-isolated-summary.widgetkitsim` attachment selected by the file dialog before the lock. This is a generated review package, not user content. The intended text attachment and image were not subsequently inserted through the native UI. No destructive cleanup was performed.

Light-mode visuals, final drag/drop gestures, menu-bar capture and OS notification delivery remain unverified in this pass. Permanent UI deletion/reset was not executed; isolated model lifecycle tests cover the underlying operations and fresh-process persistence. The original review's unchanged-surface coverage remains available in its ledger.

## Widget verification

Verified through Computer Use in WidgetKit Simulator against the isolated review app, using the actual extension's timeline and screenshots. This is native rendering, not a SwiftUI preview or a claim based only on accessibility text.

- Extension path confirmed in Simulator **Info** for both Today and Summary: `/private/tmp/openlist-ui-review-isolated/openlist.app/Contents/PlugIns/OpenlistWidget.appex`.
- Both the copied app and extension have `OpenlistReviewSession=fixes-20260905`; their shared snapshot is scoped under `UIReviews/fixes-20260905`.
- The copied extension uses the development-only bundle identifier `solimanali.openlist.OpenlistWidgetReview`. Its extension and containing app were re-signed with the existing development identity, preserving entitlements and flags. The repository's production identifiers were unchanged.
- This distinct identifier was necessary because Simulator's document Info can show the requested bundle path while PlugInKit launches another installed build with the same identifier. Earlier renders from the original identifier were rejected as evidence. The corrected Info showed `solimanali.openlist::solimanali.openlist.OpenlistWidgetReview`, and the fixed layout plus isolated fixture counts confirmed the correct implementation and snapshot.
- Simulator environment: dark appearance, display scale 1, locale `en_US@rg=nlzzzz`, normal contrast, Reduce Motion/Transparency and Invert Colors off. No system appearance or accessibility preferences were changed.

| Widget | Native result | Evidence |
|---|---|---|
| Today small | Passed | At 21:06:03, both “Pay the electricity bill” and “Do the weekly shop” were fully readable. “Yesterday” appeared on one separate metadata line, followed by the other row's “Today”. `+1 more` accurately represented the third due task. |
| Today medium | Passed | At 21:06:28, all three isolated due tasks were readable, including “Call Mum” with its `23:56` time; list names and recurrence/star icons fit. |
| Today large | Passed | At 21:06:35, the same three tasks, dates, list names and metadata fit without clipping or broken date labels. |
| Summary small | Passed | At 21:09:55, “Done today” and all other labels appeared in full. Counts were Due today **2**, Overdue **1**, Inbox **3**, Done today **1**. |
| Summary medium | Passed | At 21:10:03, the same labels and counts were readable and correctly aligned. |
| Lists medium/large | Not repeated in this fix pass | The original review rendered both sizes. Archive exclusion and snapshot construction changed, but their current native rendering was not re-verified here. |

Today and Summary used the isolated snapshot after the parent verification task had archived its `UI Fix Verification` list. The three due tasks and Inbox count of three matched that isolated app's active state; they differed from the original store accidentally resolved by Simulator before the identity collision was fixed. The separate visibility/persistence checks verify archived task and subtask membership without changing their stored metadata.

The Simulator chooser displays duplicate kinds for installed builds and can select the wrong descriptor. To inspect Summary reliably, a natively saved `.widgetkitsim` document was copied to `/tmp/openlist-isolated-summary.widgetkitsim`, its descriptor was pointed at the verified review extension identity/path, and cached timeline data was omitted. Opening it through the native file dialog rendered the current isolated snapshot; its Info was checked afterward. Screenshots remain in the Computer Use observations for this task.

Menu-bar verification was not completed in this pass. The exact isolated app was selected and its Today screen confirmed, but a menu-bar popover was not opened. UI control was released to the parent task for the remaining native checks immediately after Summary verification.
