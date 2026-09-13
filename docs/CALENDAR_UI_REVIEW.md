# Calendar interface and development build review

This review concerns the calendar navigation and visual refinement following the
initial adaptive scheduling implementation. The scheduler, history, and external
calendar contracts remain documented in [Adaptive calendar](ADAPTIVE_CALENDAR.md).

## Components and design decision

The hourly schedule uses native SwiftUI components: `ScrollView`, `ScrollPosition`,
`onScrollGeometryChange`, native menu/date-entry controls, matched geometry for the
view selector, and smooth animations with Reduce Motion support. Scrolling owns
its state within the time grid, rather than invalidating the screen's navigation
and status controls at every pixel. Liquid Glass is reserved for the primary
navigation action; task content remains readable and opaque enough to scan.

Reviewed alternatives:

| Component | Result |
| --- | --- |
| [HorizonCalendar](https://github.com/airbnb/HorizonCalendar/blob/master/Package.swift) | Its package targets iOS and its SwiftUI interface wraps UIKit. It does not fit Openlist's native macOS target. |
| [ElegantCalendar](https://github.com/ThasianX/ElegantCalendar/blob/master/Package.swift) | iOS-only package; does not fit this Mac app. |
| [Mijick CalendarView](https://github.com/Mijick/CalendarView) | Supports macOS date/range selection, but does not replace hourly schedule layout, task dragging, or adaptive rescheduling. The small date navigator uses native SwiftUI without adding a dependency. |

Apple references: [scroll position and geometry](https://developer.apple.com/videos/play/wwdc2024/10144/),
[spring animation guidance](https://developer.apple.com/videos/play/wwdc2023/10156/),
[Liquid Glass design](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

The user-requested `swiftui-pro`, `swiftui-liquid-glass`, and
`swiftui-ui-patterns` skills were installed from their supplied GitHub repositories
and consulted for composition, scrolling, animation, and accessibility review.

## Native E2E acceptance

Use the `Openlist Dev` scheme or `./Tools/build-dev.sh --open`. It has a DEV-badged
icon, a distinct bundle identity, isolated local data, and no iCloud access.
The installed production app can remain open. Use disposable tasks in Dev.

The native acceptance run on 2026-09-13 verified:

1. Production and Dev coexist with visibly distinct app identities.
2. Empty-calendar guidance leads to task creation and selection for today.
3. Work availability overrides populate the schedule without changing deadlines.
4. All four scales show the same tasks and remain stable during repeated switching.
5. Now returns from another date/month and reveals the labeled current time.
6. Date picker, direct date entry, arrows, and keyboard shortcuts navigate correctly.
7. Zoom and inspector opening preserve the visible hour; date headers/time ruler stay aligned.
8. Blocks show readable names/times; dragging across dates saves a preferred placement.
9. Pinning, conflicting availability, and deadline coverage remain connected.
10. Explicit start/pause/completion and history corrections work from the refreshed surface.
11. Narrow/wide windows and Light/Dark appearance retain usable controls.
12. Relaunch preserves development tasks and preferences independently of production.

The app was driven through its actual macOS UI with disposable Dev tasks. The
production process remained running, while `lsof` confirmed Dev used only its
private `solimanali.openlist.dev` sandbox store. The compiled DEV icon was also
visually inspected; the app, widget and helper identities are checked by the
development build script.

Observed work included creating 30-, 45- and 15-minute tasks, a Sunday work-hours
override, all four scales, direct date entry, period arrows and keyboard
shortcuts, Now from another month, zoom preserving the visible hour, and task
inspection. A one-minute task was explicitly started, overran in real time and
extended by 15 minutes. Pause created a work record; correcting it to five
minutes updated history. Completing a recurring task produced a separate
occurrence record. Tasks, placements, corrections and the chosen calendar scale
survived relaunch.

The final run verified an approximately 890-pixel-wide week view: Now scrolled
to Sunday, with its tasks under the Sunday heading and the time ruler still
visible. Horizontal scrolling and all four scale controls remained usable.
Direct date entry across December 2027 / January 2028 displayed both years.
Calendar scale and Large zoom were confirmed after relaunch; the app was left
on the current three-day view with Comfortable zoom and its original System
appearance for manual testing.

Cross-day dragging was verified in both directions between visible columns,
including preserving the time when moving horizontally. An explicit pin at
12:30 inside a work break remained at that time, displayed a conflict on its
card and produced a readable notice. The latest interface counts pinned
conflicts as needing attention.

The native checks exposed and led to fixes for card drag targeting, valid future
preferences being displaced by the today fallback, silent rejection of
infeasible preferences, and scroll coordinates that include the sidebar's safe
area inset. Dragging uses SwiftUI's native `DragGesture` in the timeline's named
coordinate space and keeps its preview aligned with the final placement.

Validation completed:

- `./Tools/check.sh`: passed every suite, including 984 scheduling, 48 calendar
  persistence and 76 calendar runtime assertions, plus existing editing,
  lifecycle, exports, sync, signing, MCP and packaging regressions.
- `OPENLIST_DEV_CHECKS=1 ./Tools/run-mcp-checks.sh`: passed the real local
  transport, store/protocol and helper checks using the Dev identity.
- `./Tools/build-dev.sh`: built and verified the ad-hoc-signed app and nine
  development isolation checks.
- `./Tools/build-release.sh 0.1.0 1`: compiled and verified the unsigned arm64 app
  and widget, macOS version and release bundle metadata.

Reduce Motion is respected in source for view selection, navigation, zoom and
block movement; changing the system accessibility setting and a complete
VoiceOver journey were not part of this native run. Live EventKit permission and
account import, physical Mac lock/sleep delivery, cross-Mac CloudKit history
sync and production schema deployment remain integration checks. The ad-hoc
Dev build intentionally has no iCloud access and cannot share widget data via a
provisioned App Group; use a team-signed Dev build for that widget check.

## Completion history and seamless nudges

The follow-up review agreed that completed work remains on the timeline, with
actual recorded intervals when tracked and the original planned slot otherwise.
Completed occurrences have immutable titles and their own history; the live next
recurring occurrence is a separate task occurrence. A completed block never
reserves capacity, and reused time is laid out in adjacent lanes.

Native checks in the isolated Dev app verified:

- A task with a corrected five-minute work session moved from its future plan
  to its actual earlier work interval when completed, with a checkmark and muted
  strikethrough. Its future slot was freed.
- Both the completion message's **Undo** and native **⌘Z** restored the unfinished
  task and its preferred placement, while the work timer remained paused.
- Completing an unstarted recurring task retained the original scheduled slot,
  marked **Time not tracked**. Its history opened directly to that occurrence,
  and **Originally planned** disclosed the saved start/end. The next occurrence
  moved to tomorrow rather than reappearing in today's queue.
- The day, three-day, week and month views all retained completed history and
  counted it separately from future planned work.
- The quiet **Up next** bar appeared at the scheduled start without starting a
  timer. A one-minute task exposed a too-small visual target; the minimum
  rendered height is now 20 pixels, with overlap lanes accounting for that
  height without changing scheduled duration or capacity.

The implementation also separates routine editor/history changes from scheduling
inputs so navigation, title edits and historical corrections cannot keep sliding
the plan or restarting the missed-start grace period. Notification actions check
the current task occurrence and nudge identity to reject stale actions after
recurrence, completion or rescheduling. Calendar notifications are silent and
suppressed in the foreground, where the work bar is already visible.

The real-clock missed-start check held a one-minute task at its promised time
through the five-minute grace period. At expiry it moved only that occurrence
to the next free minute, showed a reviewable rescheduling notice, and retained
**0 min recorded** with an empty work-session history. After relaunching the
final Dev build, the same task had a readable short-block target. Explicit Start
then exposed the quiet **Still working? I'll allow 15 more minutes** caption
before the one-minute estimate elapsed.

The first real overrun moved the following 30-minute task from 15:23 to 15:38
and showed **1 task rescheduled**. Completing the active work freed that runway
and moved the following task to 15:25. The completed card remained at its actual
15:22 start, while its history preserved the original pre-start 15:53–15:54 plan.
Correcting that recorded session to two minutes updated the completed card and
left the following task at 15:25.

Final focused validation passed **984 scheduling**, **89 persistence/migration**,
**151 runtime**, and **1,003 layout** checks. The Dev and unsigned arm64 Release
builds passed, including app/widget/helper bundle checks and the nine development
isolation checks. Runtime scenarios include later extensions requiring approval,
delayed Pause/Done, fixed boundary changes, estimate edits during work or while
awaiting confirmation, and history-only changes preserving live placements.

Silent native notification delivery/actions, physical lock/sleep, live EventKit
account access, cross-Mac CloudKit delivery and production schema deployment
remain integration verification gaps. Reduce Motion is implemented and covered
by source review; a physical accessibility-setting/VoiceOver pass remains open.

The complete final `./Tools/check.sh` run exited successfully after the shared
recording-endpoint change, including the existing editor, lifecycle, export,
sync, signing, MCP and helper regressions. A final native relaunch retained all
four completed occurrences, the corrected two-minute interval, its original
15:53–15:54 planned slot, and the chosen three-day calendar view. Openlist Dev was
left open on that calendar with no active work session.
