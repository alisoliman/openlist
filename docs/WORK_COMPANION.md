# Work companion

Work has one stable place in the window: while a task is recording, or paused
with work that can resume, a work notch drops from the toolbar with its title,
elapsed time, **Pause** or **Resume**, **Done** and **Stop**. Clicking its title
opens the **Work** panel, as does **Work → Show Work**. Suggestions never open the
panel or begin recording by themselves.

The Work panel shows the task's planned slot, estimate, recorded time,
scheduling source and separate deadline. With nothing planned for now it offers
**Choose a task** and **Open calendar**.

## Behavior

- Starting (**Start working** in task details, **Start** on Calendar's
  **Planned now** banner, **Work → Start Selected Task** or **Task → Start
  Working**) and Resume explicitly create a work segment. **Pause** saves it and
  keeps the work on the notch to resume, across relaunches too. **Stop working**
  saves it, leaves the task open and ends the work, the tray saying how long was
  recorded.
- **Later… → Remind in 15 minutes** quiets the occurrence without changing its
  plan. **Later… → Move planned time…**, for a task with a block on the
  calendar, moves that block to another start, as long as it is. Its sheet lists
  what the new time would overlap, and the move is pinned as Plan's placement
  is, one change with Undo in the tray. The due date stays the same.
- Starting another task while one is recording switches straight away, saving
  the previous segment first, and the tray offers Undo.
- Recording continues past the estimate. The working block grows in 15-minute
  steps and later placements that day move out of its way, with Undo in the
  tray. When a meeting or a break leaves no more room, work keeps recording and
  the notch names what it is running into; at the end of the list's hours the
  block simply stops growing.
- **Complete task** (the Work panel, the notch's **Done**, **Work → Complete
  Current Task**) stops recording and completes the task as its row's checkbox
  does: it closes after the undo delay and the tray offers **Undo**, which
  reopens it without restarting time. A background notification's **Complete
  task** completes it at once, with Undo in the tray, and leaves the finished
  occurrence, recorded time and next recurrence in the Work panel, where **Undo
  completion** restores it.
- Task actions, the Work menu and the command palette share the same occurrence
  validation. Stale recurrence references cannot start a replacement occurrence.
- Background Work notifications are opt-in in Settings › Notifications. Start reminders are
  coalesced by occurrence and snooze revision.

## Verification

`Tools/run-calendar-runtime-checks.sh` exercises occurrence safety,
persistence, switching, extension and its Undo, recorded intervals, hard
boundaries, Move previews and failure recovery. No schema migration or external
dependency is involved.
