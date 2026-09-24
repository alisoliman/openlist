# Work companion

Work has one stable place in the window: while a task is recording, or paused
with work that can resume, a work notch drops from the toolbar with its title,
elapsed time, **Done** and **Stop**. Clicking its title opens the **Work** panel,
as do **Work → Show Work** and the command palette. Suggestions never open the
panel or begin recording by themselves.

The Work panel shows the task's planned slot, estimate, recorded time,
scheduling source and separate deadline. With nothing planned for now it offers
**Choose a task** and **Open calendar**.

## Behavior

- Start (in task details, on Calendar's **Planned now** banner, from **Work →
  Start Selected Task** or **Task → Start Working**) and Resume explicitly
  create a work segment. **Stop working** saves it and leaves the task open; the
  resumable occurrence persists across relaunches.
- **Later… → Remind in 15 minutes** quiets the occurrence without changing its
  plan. **Later… → Move planned time…** previews the other planned work that
  would move before saving a preferred placement; it changes the preferred work
  time, not the deadline.
- Starting another task while one is recording switches straight away, saving
  the previous segment first, and the tray offers Undo.
- Recording continues past the estimate. The working block grows in 15-minute
  steps and later flexible work moves out of its way, with Undo in the tray.
  When a meeting, a break or a pinned task leaves no more room, work keeps
  recording and the notch names what it is running into. Availability, pins and
  fixed busy time still bound the plan.
- **Complete task** reports the finished occurrence, recorded time and next
  recurrence when applicable. **Undo completion** restores the occurrence without
  restarting time.
- Task actions, the Work menu and the command palette share the same occurrence
  validation. Stale recurrence references cannot start a replacement occurrence.
- Background Work notifications are opt-in in Settings › Notifications. Start reminders are
  coalesced by occurrence and snooze revision.

## Verification

`Tools/run-calendar-runtime-checks.sh` exercises occurrence safety,
persistence, switching, extension and its Undo, recorded intervals, hard
boundaries, Move previews and failure recovery. No schema migration or external
dependency is involved.
