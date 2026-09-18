# Frozen source evidence

Read-only excerpts from reviewed commit `6e6c0baa46f9a51cc5dec0ae202ca4ac88037986`. Line numbers refer to this commit. These preserve the research baseline if the active checkout changes.

## openlist/Views/RootView.swift

```text
 380      // MARK: - Content routing
 381
 382      private var contentArea: some View {
 383          VStack(spacing: 0) {
 384              CalendarWorkBanner()
 385              routedContent
 386          }
 387          .safeAreaInset(edge: .bottom, spacing: 0) {
 388              SelectionActionsBar(scopeID: env.navigator.rowSelection.scopeID)
 389          }
```

## openlist/Views/CalendarWorkBanner.swift

```text
  10      var body: some View {
  11          VStack(spacing: 0) {
  12              if let nudge = env.calendar.overrunNudge, nudge.needsConfirmation,
  13                 let task = env.store.block(id: nudge.taskID) {
  14                  HStack(spacing: 10) {
  15                      Image(systemName: "pause.circle.fill").foregroundStyle(Theme.accent)
  16                      VStack(alignment: .leading, spacing: 2) {
  17                          Text(task.displayTitle).font(.callout.weight(.semibold)).lineLimit(1)
  18                          Text("More time would move other tasks.")
  19                              .font(.caption).foregroundStyle(Theme.secondaryText)
  20                      }
  21                      Spacer(minLength: 4)
  22                      Button("Done") { env.calendar.complete(task: task) }
  23                      Button("Keep going · \(extensionMinutes(nudge)) min") { env.calendar.acceptMoreTime() }
  24                          .buttonStyle(.borderedProminent).tint(Theme.accent)
  25                  }
  26                  .padding(.horizontal, 12).frame(minHeight: 54)
  27                  .background(Theme.rowSelected)
  28                  .accessibilityElement(children: .contain)
  29                  .accessibilityLabel("Confirm more work time")
  30              } else if let session = env.calendar.activeSession {
  31                  TimelineView(.periodic(from: .now, by: 30)) { context in
  32                      HStack(spacing: 10) {
  33                          Image(systemName: "play.circle.fill").foregroundStyle(Theme.accent)
  34                          VStack(alignment: .leading, spacing: 2) {
  35                              Text(session.title).font(.callout.weight(.semibold)).lineLimit(1)
  36                              if let nudge = env.calendar.overrunNudge, nudge.taskID == session.taskID {
  37                                  Text("Still working? I’ll allow \(extensionMinutes(nudge)) more minutes.")
  38                                      .font(.caption).foregroundStyle(Theme.secondaryText)
  39                              } else {
  40                                  Text("Working · \(env.calendar.recordedMinutes(for: session, now: context.date).formatted(.number.precision(.fractionLength(0)))) min this session")
  41                                      .font(.caption).foregroundStyle(Theme.secondaryText)
  42                              }
  43                          }
  44                          Spacer(minLength: 4)
  45                          Button("Pause") { env.calendar.pause(reason: "Paused") }
  46                          if let task = env.store.block(id: session.taskID) {
  47                              Button("Done") { env.calendar.complete(task: task) }
  48                                  .buttonStyle(.borderedProminent).tint(Theme.accent)
  49                          }
  50                      }
  51                  }
  52                  .padding(.horizontal, 12).frame(minHeight: 54)
  53                  .background(Theme.rowSelected)
  54              } else if let id = env.calendar.resumeTaskID {
  55                  HStack(spacing: 10) {
  56                      Label("Resume \(env.store.block(id: id)?.displayTitle ?? "your task")?", systemImage: "pause.circle")
  57                          .font(.callout).lineLimit(2)
  58                      Spacer(minLength: 4)
  59                      Button("Later") { env.calendar.dismissResume() }
  60                      Button("Resume") { env.calendar.resume() }
  61                          .buttonStyle(.borderedProminent).tint(Theme.accent)
  62                  }
  63                  .padding(.horizontal, 12).frame(minHeight: 54)
  64                  .background(Theme.rowSelected)
  65              } else if let nudge = env.calendar.startNudge,
  66                        let task = env.store.block(id: nudge.taskID) {
  67                  HStack(spacing: 10) {
  68                      Image(systemName: "clock").foregroundStyle(Theme.accent)
  69                      VStack(alignment: .leading, spacing: 2) {
  70                          Text("Up next: \(task.displayTitle)").font(.callout.weight(.medium)).lineLimit(1)
  71                          Text("Your time starts when you do.")
  72                              .font(.caption).foregroundStyle(Theme.secondaryText)
  73                      }
  74                      Spacer(minLength: 4)
  75                      Button("Start") { _ = env.calendar.start(task: task) }
  76                          .buttonStyle(.borderedProminent).tint(Theme.accent)
  77                  }
  78                  .padding(.horizontal, 12).frame(minHeight: 54)
  79                  .background(Theme.rowSelected)
  80                  .accessibilityElement(children: .contain)
  81                  .accessibilityLabel("Ready to start")
  82              }
  83
  84              if let summary = env.calendar.rescheduleSummary, env.navigator.route == .calendar {
  85                  HStack(spacing: 8) {
  86                      Image(systemName: "arrow.triangle.2.circlepath").accessibilityHidden(true)
  87                      Text(summary.message).lineLimit(1)
  88                      Spacer(minLength: 4)
  89                      Button("Review") { showsRescheduleDetails = true }
  90                          .buttonStyle(.link)
  91                      Button("Dismiss rescheduling notice", systemImage: "xmark") {
  92                          env.calendar.dismissRescheduleSummary()
  93                      }.labelStyle(.iconOnly).buttonStyle(.plain)
  94                  }
  95                  .font(.caption).foregroundStyle(Theme.secondaryText)
  96                  .padding(.horizontal, 12).padding(.vertical, 7)
  97                  .background(Theme.chrome.opacity(0.5))
```

## openlist/Services/CalendarCoordinator.swift

```text
 183      func start(task: Block, now: Date = .now) -> Bool {
 184          guard task.isTask, !task.isCompleted, store.list(id: task.listID)?.isEffectivelyArchived == false else { return false }
 185          if activeSession?.taskID == task.id, activeSession?.occurrenceID == task.occurrenceID { return true }
 186          guard let boundary = nextBoundary(for: task, at: now), boundary > now else {
 187              notice = "This time is outside the list’s available hours or overlaps fixed busy time. Choose an available slot or update availability."
 188              return false
 189          }
 190          isUpdating = true
 191          defer { isUpdating = false }
 192          if activeSession != nil {
 193              pause(reason: "Switched task", now: now)
 194              guard activeSession == nil else { return false }
 195          }
 196          // Retry interrupted recovery before adopting any old same-device record.
 197          // An old open row must never turn app absence into elapsed working time.
 198          for orphan in store.workSessions() where orphan.deviceID == deviceID && orphan.endedAt == nil && orphan.id != activeSessionID {
 199              guard store.pauseWorkSession(orphan, reason: "Recovered before starting", now: min(now, orphan.lastHeartbeatAt)) else {
 200                  notice = store.persistenceError ?? "Previous work could not be recovered. Try again."
 201                  return false
 202              }
 203          }
 204          guard let session = store.startWorkSession(for: task, deviceID: deviceID, now: now), store.persistenceError == nil else {
 205              notice = store.persistenceError ?? "Work could not be started."
 206              return false
 207          }
 208          activeSessionID = session.id
 209          let baseline = baselineEnd(for: session, task: task, now: now)
 210          estimatedWorkEnd = baseline
 211          approvedWorkEnd = baseline
 212          usedAutomaticExtension = false
 213          showedFinishHeadsUp = false
 214          overrunNudge = nil
 215          startNudge = nil
 216          activeBoundary = boundary
 217          lastObservedAt = now
 218          resumeTaskID = nil
 219          notice = nil
 220          replan(now: now)
 221          return true
 222      }
 223
 224      func pause(reason: String = "Paused", now: Date = .now, replanning: Bool = true) {
 225          guard let session = activeSession else { return }
 226          let wasUpdating = isUpdating
 227          isUpdating = true
 228          // A button or lock notification may arrive before a delayed timer. The
 229          // last known hard boundary still limits recorded work in that case.
 230          let endpoint = recordingEndpoint(for: session, at: now)
 231          guard store.pauseWorkSession(session, reason: reason, now: endpoint) else {
 232              notice = store.persistenceError ?? "Work could not be paused. Try again."
 233              isUpdating = wasUpdating
 234              return
 235          }
 236          activeSessionID = nil
 237          activeBoundary = nil
 238          lastObservedAt = nil
 239          approvedWorkEnd = nil
 240          estimatedWorkEnd = nil
 241          overrunNudge = nil
 242          isUpdating = wasUpdating
 243          if replanning { replan(now: now) }
 244      }
 245
 246      func complete(task: Block, now: Date = .now) {
 247          store.toggleCompletion(task, now: now)
 248          tick(now: now, checkClockGap: false, materialChange: true)
 249      }
 250
 251      func deferTask(task: Block, to day: Date) {
 252          if activeSession?.taskID == task.id { pause(reason: "Deferred") }
 253          store.deferTask(task, to: day)
 254          if resumeTaskID == task.id { resumeTaskID = nil }
 255          replan()
 256      }
 257
 258      func resume() {
 259          guard let id = resumeTaskID, let task = store.block(id: id) else { resumeTaskID = nil; return }
 260          _ = start(task: task)
 261      }
 262
 263      func dismissResume() { resumeTaskID = nil; notice = nil }
```

```text
 341      func handleMacUnavailable(reason: String, now: Date = .now) {
 342          guard let session = activeSession, let task = store.block(id: session.taskID), !task.tracksAwayFromMac else { return }
 343          resumeTaskID = task.id
 344          pause(reason: reason, now: now)
 345          if activeSession == nil { notice = "Work paused because \(reason.lowercased()). Resume when ready." }
```

```text
 433      private func advanceActiveWork(session: WorkSession, task: Block, through now: Date, boundary: Date) {
 434          while let end = approvedWorkEnd, end <= now, end < boundary {
 435              let proposed = min(end.addingTimeInterval(15 * 60), boundary)
 436              let affected = displacedTaskIDs(from: end, to: proposed, excluding: task.occurrenceID)
 437              if usedAutomaticExtension && !affected.isEmpty {
 438                  let nudge = CalendarOverrunNudge(taskID: task.id, occurrenceID: task.occurrenceID,
 439                      kind: .needsConfirmation, estimatedEnd: end,
 440                      proposedEnd: proposed, movedTaskCount: affected.count)
 441                  pause(reason: "More time needs confirmation", now: end, replanning: false)
 442                  guard activeSession == nil else { return }
 443                  // Preserve everyone else's promised times while the user decides.
 444                  rescheduleOnly(task: task, now: now)
 445                  overrunNudge = nudge
 446                  startNudge = nil
 447                  return
 448              }
 449              let previous = plan
 450              approvedWorkEnd = proposed
 451              usedAutomaticExtension = true
 452              showedFinishHeadsUp = true
 453              overrunNudge = nil
 454              // Replan at the approved boundary, not a late callback: another block
 455              // may need to stay anchored there for the next extension decision.
 456              replan(now: end)
 457              summarizeMoves(from: previous, message: "Made room for continued work.", excluding: task.id)
 458          }
 459      }
 460
 461      private func updateFinishNudge(task: Block, now: Date, boundary: Date) {
 462          guard !showedFinishHeadsUp, !usedAutomaticExtension, let end = estimatedWorkEnd,
 463                end < boundary, now >= end.addingTimeInterval(-2 * 60) else { return }
 464          showedFinishHeadsUp = true
 465          let proposed = min(end.addingTimeInterval(15 * 60), boundary)
 466          overrunNudge = CalendarOverrunNudge(taskID: task.id, occurrenceID: task.occurrenceID,
 467              kind: .headsUp, estimatedEnd: end, proposedEnd: proposed,
 468              movedTaskCount: displacedTaskIDs(from: end, to: proposed, excluding: task.occurrenceID).count)
```

```text
 559      private func updateStartNudge(now: Date) {
 560          guard activeSession == nil, overrunNudge?.needsConfirmation != true else { startNudge = nil; return }
 561          let next = plan.blocks.first { block in
 562              !block.isActive && block.start <= now && block.end > block.start &&
 563                  store.block(id: block.taskID)?.occurrenceID == block.occurrenceID &&
 564                  store.block(id: block.taskID)?.isCompleted == false
 565          }
 566          startNudge = next.map {
 567              CalendarStartNudge(taskID: $0.taskID, occurrenceID: $0.occurrenceID,
 568                  scheduledStart: $0.start, graceEndsAt: $0.start.addingTimeInterval(5 * 60))
 569          }
 570      }
 571
 572      private func moveMissedWork(now: Date) {
 573          // Read the established plan before moving anything. A fresh plan starting
 574          // at `now` would hide missed starts forever and make the whole day drift.
 575          let missed = plan.blocks.filter {
 576              !$0.isActive && $0.occurrenceID != activeSession?.occurrenceID &&
 577                  $0.start.addingTimeInterval(5 * 60) <= now &&
 578                  $0.occurrenceID != overrunNudge?.occurrenceID
 579          }
 580          var handled = Set<UUID>()
 581          for block in missed where handled.insert(block.occurrenceID).inserted {
 582              guard let task = store.block(id: block.taskID), task.occurrenceID == block.occurrenceID, !task.isCompleted else { continue }
 583              if block.isPinned, let placementID = block.placementID { missedPlacementIDs.insert(placementID) }
 584              let previous = plan
 585              rescheduleOnly(task: task, now: now)
 586              summarizeMoves(from: previous, message: "Moved an unstarted task to the next free time.")
 587          }
 588          updateStartNudge(now: now)
 589      }
```

## openlist/Services/AdaptiveScheduler.swift

```text
 116          let placedIDs = Set(placements.filter { $0.end > now || $0.isPinned }.map(\.occurrenceID))
 117          let candidates = uniqueTasks.filter { task in
 118              task.selectedForToday || task.earliestStart != nil || placedIDs.contains(task.occurrenceID) || active?.occurrenceID == task.occurrenceID ||
 119                  (task.dueDate.map { $0 <= horizon } ?? false)
 120          }
```

## openlist/Views/TaskSchedulingSection.swift

```text
  21          VStack(alignment: .leading, spacing: 12) {
  22              HStack {
  23                  Toggle("Plan for today", isOn: Binding(get: { selectedToday }, set: { value in
  24                      if value { env.store.selectForToday(block) } else { env.store.deselectForToday(block) }
  25                      env.calendar.storeDidChange()
  26                  }))
  27                  .disabled(block.isCompleted)
  28                  Button { env.navigator.go(to: .calendar) } label: { Image(systemName: "arrow.up.right") }
  29                      .buttonStyle(.plain).help("Open calendar").accessibilityLabel("Open calendar")
  30              }
```

```text
  57              Toggle("Keep task together", isOn: Binding(get: { block.keepsSessionsTogether }, set: {
  58                  env.store.setKeepTogether($0, for: block); env.calendar.storeDidChange()
  59              }))
  60              Toggle("Track work away from this Mac", isOn: Binding(get: { block.tracksAwayFromMac }, set: {
  61                  env.store.setTracksAway($0, for: block)
  62              }))
  63              .help(block.tracksAwayFromMac ? "Tracking continues through lock or sleep, until a meeting or unavailable time." : "Locking or sleeping pauses active work.")
  64              HStack {
```

```text
  87              if !block.isCompleted {
  88                  HStack(spacing: 8) {
  89                      Button {
  90                          if isActive { env.calendar.pause(reason: "Paused") } else { _ = env.calendar.start(task: block) }
  91                      } label: { Label(isActive ? "Pause" : "Start", systemImage: isActive ? "pause.fill" : "play.fill") }
  92                      .buttonStyle(.borderedProminent).tint(Theme.accent)
  93                      Button("Defer…") { showsDeferral = true }
  94                      Spacer(minLength: 0)
  95                  }
  96              }
  97              HStack {
  98                  Text("\(env.calendar.trackedMinutes(for: block).formatted(.number.precision(.fractionLength(0)))) min recorded")
  99                      .font(.caption).foregroundStyle(Theme.secondaryText)
 100                  Spacer()
 101                  Button("History") { showsHistory = true }.buttonStyle(.link).font(.caption)
 102              }
 103          }
 104          .font(Theme.Font.body)
 105          .padding(12).background(Theme.canvas.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
 106          .popover(isPresented: $showsDeferral) { TaskDeferralPicker(block: block) }
 107          .sheet(isPresented: $showsHistory) { CalendarHistoryView(taskID: block.id) }
```

## openlist/Services/CalendarNotificationBridge.swift

```text
  43      func update() {
  44          guard ReviewSession.identifier == nil else { return }
  45          updateTask?.cancel()
  46          updateTask = Task { [weak self] in
  47              await Task.yield()
  48              guard let self, !Task.isCancelled else { return }
  49              guard !NSApp.isActive, let nudge = currentNudge else {
  50                  await service.clearCalendarNudges()
  51                  return
  52              }
  53              let alreadyPresent = await service.clearCalendarNudges(except: nudge.identifier)
  54              guard !Task.isCancelled, !NSApp.isActive, currentNudge?.identifier == nudge.identifier else { return }
  55              if alreadyPresent { lastPostedID = nudge.identifier; return }
  56              guard lastPostedID != nudge.identifier, await service.authorizeCalendarNudgeIfNeeded() else { return }
  57              guard !Task.isCancelled, !NSApp.isActive, currentNudge?.identifier == nudge.identifier else { return }
  58              let posted = await service.postCalendarNudge(identifier: nudge.identifier, title: nudge.title, body: nudge.body,
  59                                                           category: nudge.category, taskID: nudge.taskID, occurrenceID: nudge.occurrenceID)
```

```text
 103      private var currentNudge: Nudge? {
 104          if let nudge = calendar.overrunNudge,
 105             let task = store.block(id: nudge.taskID), task.occurrenceID == nudge.occurrenceID, !task.isCompleted {
 106              let kind = nudge.needsConfirmation ? "confirmation" : "heads-up"
 107              let dates = "\(stamp(nudge.estimatedEnd)).\(stamp(nudge.proposedEnd))"
 108              let id = "\(NotificationService.calendarRequestPrefix)overrun.\(nudge.taskID).\(nudge.occurrenceID).\(kind).\(dates).\(nudge.movedTaskCount)"
 109              let count = nudge.movedTaskCount
 110              let impact = count == 0 ? "" : " Keeping going will move \(count) other \(count == 1 ? "task" : "tasks")."
 111              let minutes = max(0, nudge.proposedEnd.timeIntervalSince(nudge.estimatedEnd) / 60)
 112              let duration = minutes.formatted(.number.precision(.fractionLength(0...1)))
 113              let unit = minutes == 1 ? "minute" : "minutes"
 114              let body = nudge.needsConfirmation
 115                  ? "Work is paused. Done, or keep going for \(duration) more \(unit)?\(impact)"
 116                  : "Still working? I’ll allow \(duration) more \(unit)."
 117              return Nudge(identifier: id, taskID: nudge.taskID, occurrenceID: nudge.occurrenceID,
 118                           category: nudge.needsConfirmation ? NotificationService.calendarOverrunCategory : NotificationService.calendarHeadsUpCategory,
 119                           title: task.displayTitle, body: body)
 120          }
 121          if let nudge = calendar.startNudge,
 122             let task = store.block(id: nudge.taskID), task.occurrenceID == nudge.occurrenceID, !task.isCompleted {
 123              let dates = "\(stamp(nudge.scheduledStart)).\(stamp(nudge.graceEndsAt))"
 124              let id = "\(NotificationService.calendarRequestPrefix)start.\(nudge.taskID).\(nudge.occurrenceID).\(dates)"
 125              return Nudge(identifier: id, taskID: nudge.taskID, occurrenceID: nudge.occurrenceID,
 126                           category: NotificationService.calendarStartCategory, title: task.displayTitle,
 127                           body: "Your planned session is ready. Start when you are ready; tracking never starts automatically.")
```

## openlist/Services/Store+Tasks.swift

```text
  13      func toggleCompletion(_ block: Block, now: Date = .now) {
  14          guard block.isTask else { return }
  15
  16          if block.isCompleted {
  17              reopen(block)
  18          } else {
  19              let before = captureCompletionUndo(for: block)
  20              complete(block, now: now)
  21              stageCompletionUndo(for: block, before: before, now: now)
  22          }
  23          save()
  24      }
  25
  26      func complete(_ block: Block, now: Date) {
  27          recordCalendarCompletion(for: block, now: now)
  28
  29          if var rule = block.recurrence,
  30             let next = RecurrenceEngine.nextDate(rule: rule, dueDate: block.dueDate, completedAt: now) {
  31              let completedCycleID = recurringCompletionCycle(for: block) ?? block.occurrenceID
  32              // Repeating tasks never sit in the completed state: they advance.
  33              rule.completedOccurrences += 1
  34              let previousDue = block.dueDate
  35              block.recurrence = rule.isFinished ? nil : rule
  36              block.dueDate = rule.isFinished ? nil : next
  37              block.isCompleted = false
  38              block.completedAt = nil
  39              block.occurrenceID = UUID()
  40              clearInboxForNextOccurrence(block)
  41              // Completing today's occurrence must not immediately fill today
  42              // again with a future repeat. An explicit Today choice clears this.
  43              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
  44              let nextEligible = !rule.isFinished && next >= tomorrow ? tomorrow : nil
  45              block.deferredUntil = nextEligible
```

## openlist/Services/Store+Calendar.swift

```text
 199      func pauseWorkSessions(for block: Block, reason: String, now: Date = .now) {
 200          for session in workSessions(taskID: block.id)
 201          where session.occurrenceID == block.occurrenceID && session.endedAt == nil {
 202              let isForeign = calendarDeviceID.map { $0 != session.deviceID } ?? false
 203              let endpoint = isForeign ? min(now, session.lastHeartbeatAt)
 204                  : min(now, calendarRecordingEndpoint?(session, now) ?? now)
 205              closeSession(session, reason: reason, now: endpoint)
 206          }
 207      }
 208
 209      private func closeSession(_ session: WorkSession, reason: String, now: Date) {
 210          session.endedAt = max(session.startedAt, now)
 211          session.lastHeartbeatAt = session.endedAt!
 212          session.pauseReason = reason
 213      }
 214
 215      /// Called before changing an occurrence's identity or deleting a task.
 216      /// History remains independent; only future placements are discarded.
 217      func discardTaskSchedule(for block: Block, reason: String, now: Date = .now) {
 218          pauseWorkSessions(for: block, reason: reason, now: now)
 219          for placement in placements(taskID: block.id) where placement.occurrenceID == block.occurrenceID {
 220              context.delete(placement)
 221          }
 222          block.selectedForDay = nil
 223          block.deferredUntil = nil
```
