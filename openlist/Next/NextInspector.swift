//
//  NextInspector.swift
//  openlist
//

import SwiftData
import SwiftUI

/// The 360pt panel that slides in from the right with one task's details.
struct NextInspector: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let task: Block
    /// Drafts belong to `draftID`, which lags `task` until they are committed.
    @State private var title = SyncedTextDraft()
    @State private var note = SyncedTextDraft()
    @State private var draftID: UUID?
    /// The open popover, and the task it was opened on. The shell reuses this
    /// view for every task, so a popover never carries over to the next one.
    @State private var picker: (section: DetailPicker, taskID: UUID)?
    @State private var titleSelection: TextSelection?
    @State private var noteSelection: TextSelection?
    @FocusState private var focus: Field?

    enum Field { case title, note }

    private var workbench: Workbench { env.workbench }

    /// A search hit or link that landed in this task's title or note.
    private var reveal: ContentReveal? {
        guard let request = env.navigator.contentReveal, request.taskID == task.id else { return nil }
        return request
    }
    private var readyRevealID: UUID? { env.navigator.isSearchOpen ? nil : reveal?.id }

    var body: some View {
        let list = library.list(task.listID)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let list { NXListGlyph(list: list, size: 12) }
                Text(list?.displayTitle ?? "No list")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NX.ink(0.55))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button { env.navigator.closeTask() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 16, height: 16)
                }
                .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 6,
                                                padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                                                foreground: NX.ink(0.45), hoverForeground: NX.ink))
                .help("Close (Esc)")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let reveal {
                            ContentRevealNotice(request: reveal, finish: env.navigator.finishReveal)
                        }
                        titleRow
                            .id(ContentReveal.Anchor.taskTitle(task.id))
                        properties(list: list)
                        TaskReminderStatus(block: task, attentionOnly: true)
                        planCard
                        VStack(alignment: .leading, spacing: 8) {
                            noteBox
                                .id(ContentReveal.Anchor.taskNote(task.id))
                            TaskNoteLinks(note: task.note)
                        }
                        NXInspectorSubtasks(task: task)
                        NXInspectorFiles(task: task)
                        activity
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.automatic)
                .task(id: readyRevealID) {
                    guard readyRevealID != nil, let reveal else { return }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    if reveal.field == .note {
                        focus = .note
                        noteSelection = SearchProjection.range(of: reveal.query, in: note.value).map { TextSelection(range: $0) }
                        proxy.scrollTo(ContentReveal.Anchor.taskNote(task.id), anchor: .center)
                    } else {
                        focus = .title
                        titleSelection = SearchProjection.range(of: reveal.query, in: title.value).map { TextSelection(range: $0) }
                        proxy.scrollTo(ContentReveal.Anchor.taskTitle(task.id), anchor: .top)
                    }
                }
            }

            HStack(spacing: 6) {
                Button {
                    // Save what is being typed first, so it goes to Trash, and
                    // comes back on Undo, with the task and its subtasks.
                    NotificationCenter.default.post(name: .commitPendingTaskTitles, object: nil)
                    workbench.trash([task.id])
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash").font(.system(size: 12.5))
                        Text("Trash").font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(NXHoverButtonStyle(hover: NX.red.opacity(0.1), radius: 8,
                                                padding: EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9),
                                                foreground: NX.ink(0.6), hoverForeground: NX.redText))
                Button(action: copyLink) {
                    HStack(spacing: 5) {
                        Image(systemName: "link").font(.system(size: 12))
                        Text("Copy Link").font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 8,
                                                padding: EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9),
                                                foreground: NX.ink(0.6), hoverForeground: NX.ink))
                .help("Copy a link to this item in this Mac’s Openlist library")
                Spacer(minLength: 8)
                startButton
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }
        }
        .frame(width: 360)
        .frame(maxHeight: .infinity)
        .background(NX.inspector)
        .overlay(alignment: .leading) { Rectangle().fill(NX.ink(0.1)).frame(width: 0.5) }
        .shadow(color: NX.shadowWarm.opacity(0.1), radius: 17, x: -14)
        .contentShape(Rectangle())
        .onTapGesture {}
        .onAppear {
            load()
            adoptRequestedPicker()
        }
        .onChange(of: task.id) { oldID, _ in
            // The shell reuses this view for every task: save the old task's
            // drafts before loading the new one's.
            commitTitle()
            commitNote()
            releaseSubtaskCommands(for: oldID)
            if picker?.taskID != task.id { picker = nil }
            load()
        }
        .onChange(of: task.text) { _, _ in title.receive(task.displayTitle) }
        .onChange(of: task.note) { _, _ in note.receive(task.note) }
        .onChange(of: focus) { old, new in
            if old == .title { commitTitle() }
            if old == .note { commitNote() }
            if new != nil { releaseSubtaskCommands(for: task.id) }
        }
        .onChange(of: workbench.focusID) { _, _ in releaseSubtaskCommands(for: task.id) }
        .onChange(of: workbench.selection) { _, _ in releaseSubtaskCommands(for: task.id) }
        .onChange(of: env.requestedPicker) { _, _ in adoptRequestedPicker() }
        .onReceive(NotificationCenter.default.publisher(for: .commitPendingTaskTitles)) { _ in
            commitTitle()
            commitNote()
        }
        .onDisappear {
            commitTitle()
            commitNote()
        }
    }

    private func load() {
        draftID = task.id
        title.reset(to: task.displayTitle)
        note.reset(to: task.note)
        titleSelection = nil
        noteSelection = nil
    }

    /// The task the drafts were loaded from. Unlike `store.block(id:)` this
    /// also finds it in Trash, so when a menu or shortcut trashes the open
    /// task, what was typed goes with it and comes back on Undo or Restore.
    private var draftTarget: Block? {
        guard let id = draftID else { return nil }
        let descriptor = FetchDescriptor<Block>(predicate: #Predicate { $0.id == id })
        guard let block = try? env.store.context.fetch(descriptor).first,
              block.modelContext != nil, !block.isDeleted else { return nil }
        return block
    }

    /// Writes only what the user typed, to the task the draft was loaded from.
    private func commitTitle() {
        guard let target = draftTarget else { return }
        if let edited = title.editedValue(normalize: { $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
           !edited.isEmpty, edited != target.displayTitle {
            env.store.setText(edited, for: target)
        }
        title.reset(to: target.displayTitle)
    }

    private func commitNote() {
        guard let target = draftTarget else { return }
        if let edited = note.editedValue(normalize: { $0 }), edited != target.note {
            env.store.setNote(edited, for: target)
        }
        note.reset(to: target.note)
    }

    /// Editing a subtask hands menu commands to its outline. Working anywhere
    /// else, or on another task, hands them back to the Next screens.
    private func releaseSubtaskCommands(for id: UUID?) {
        guard let id, env.activeDocument?.rootBlockID == id else { return }
        env.activeDocument = nil
    }

    /// ⌃D and ⌃L open their popover on the inspected task.
    private func adoptRequestedPicker() {
        guard let requested = env.requestedPicker else { return }
        env.requestedPicker = nil
        openPicker(requested)
    }

    private func copyLink() {
        // An earlier link's error would otherwise hide this copy's result.
        env.localLinks.error = nil
        env.copyLink(to: .task(task.id))
        if env.localLinks.error == nil { workbench.showTray("Link copied", icon: "link") }
    }

    // MARK: Title

    private var titleRow: some View {
        let closing = workbench.closing[task.id]
        return HStack(alignment: .top, spacing: 10) {
            NXCheckbox(filled: task.isCompleted || closing != nil, closing: closing, priority: task.priority,
                       title: task.displayTitle, size: 18) {
                workbench.toggle(task.id)
            }
            .padding(.top, 3)
            TextField("Task", text: $title.value, selection: $titleSelection, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(task.isCompleted ? NX.ink(0.45) : NX.ink)
                .strikethrough(task.isCompleted, color: NX.ink(0.45))
                .focused($focus, equals: .title)
                .onSubmit { focus = nil }
                // Esc saves and stops editing; the next Esc closes the panel.
                .onExitCommand { focus = nil }
        }
        .overlay {
            if let reveal, reveal.field != .note {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(style.accent, lineWidth: 1.5)
                    .padding(-5)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Properties

    private func properties(list: TaskList?) -> some View {
        let recurrence = task.recurrence
        // Labels sit centred against their values, as in the design's grid.
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 11) {
            GridRow {
                propertyLabel("List")
                VStack(alignment: .leading, spacing: 4) {
                    Text(list?.displayTitle ?? "No list")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NX.ink)
                        .lineLimit(1)
                        .padding(.bottom, 2)
                    NXFlow(spacing: 4) {
                        ForEach(library.lists, id: \.id) { option in
                            NXInspectorPill(isOn: option.id == task.listID, padding: EdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 7)) {
                                if option.id != task.listID { workbench.move([task.id], to: option.id, quiet: true) }
                            } label: {
                                NXListGlyph(list: option, size: 13)
                            }
                            .help(option.displayTitle)
                        }
                    }
                }
            }
            GridRow {
                dueLabel
                // A date that isn't one of the fixed choices comes first, as
                // its own pill; it opens the picker rather than rescheduling.
                let options = dueOptions
                let customLabel = options.count > 4 ? options.first?.label : nil
                NXFlow(spacing: 4) {
                    ForEach(options, id: \.label) { option in
                        NXInspectorPill(isOn: isDue(option.offset), padding: Self.duePillPadding) {
                            if option.label == customLabel { openPicker(.due) }
                            else { workbench.schedule([task.id], offset: option.offset) }
                        } label: {
                            Text(option.label)
                        }
                        .help(option.label == customLabel ? "Date and time (⌃D)" : "")
                    }
                }
                .popover(isPresented: pickerBinding(.due), arrowEdge: .bottom) { schedulePopover(.due) }
            }
            GridRow {
                propertyLabel("Repeat")
                NXInspectorPill(isOn: recurrence != nil) { openPicker(.repeatRule) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "repeat").font(.system(size: 10.5, weight: .semibold))
                        Text(recurrence?.displayText ?? "Never")
                    }
                }
                .help(recurrence?.displayText ?? "Repeat this task")
                .popover(isPresented: pickerBinding(.repeatRule), arrowEdge: .bottom) { schedulePopover(.repeatRule) }
            }
            GridRow {
                propertyLabel("Reminder")
                NXInspectorPill(isOn: task.reminderAt != nil) { openPicker(.reminder) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bell").font(.system(size: 10.5, weight: .semibold))
                        Text(task.reminderAt.map { "\(NXFormat.dueLabel($0)) \(NXFormat.clock($0))" } ?? "None")
                    }
                }
                .popover(isPresented: pickerBinding(.reminder), arrowEdge: .bottom) { schedulePopover(.reminder) }
            }
            GridRow {
                propertyLabel("Priority")
                HStack(spacing: 4) {
                    ForEach([TaskPriority.none, .low, .medium, .high], id: \.self) { priority in
                        let on = task.priority == priority
                        NXInspectorPill(isOn: on) { workbench.setPriority(task.id, priority) } label: {
                            HStack(spacing: 5) {
                                Circle().fill(on ? .white : Self.priorityColor(priority)).frame(width: 6, height: 6)
                                Text(Self.priorityTitle(priority))
                            }
                        }
                    }
                }
            }
            GridRow {
                propertyLabel("Labels")
                NXFlow(spacing: 4) {
                    ForEach(library.labels, id: \.id) { label in
                        let on = task.labelIDs.contains(label.id)
                        let color = label.nxColor
                        Button { workbench.toggleLabel(task.id, labelID: label.id) } label: {
                            Text("#\(label.name)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(on ? .white : color)
                                .padding(.vertical, 5)
                                .padding(.horizontal, 8)
                                .background(on ? color : color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .animation(.easeOut(duration: 0.14), value: on)
                    }
                    NXInspectorPill(isOn: false) { openPicker(.labels) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                            if library.labels.isEmpty { Text("Add label") }
                        }
                    }
                    .help("Find or create a label (⌃L)")
                    .accessibilityLabel("Edit labels")
                    .popover(isPresented: pickerBinding(.labels), arrowEdge: .bottom) {
                        LabelPicker(block: task).id(task.id).environment(env)
                    }
                }
            }
            GridRow {
                propertyLabel("Starred")
                Button { workbench.star([task.id]) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: task.isStarred ? "star.fill" : "star")
                            .font(.system(size: 11.5, weight: task.isStarred ? .semibold : .medium))
                        Text(task.isStarred ? "Starred" : "Not starred")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(task.isStarred ? NX.amberText : NX.ink(0.66))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(task.isStarred ? NX.amber.opacity(0.16) : NX.ink(0.05),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Star (F)")
            }
        }
    }

    private func openPicker(_ section: DetailPicker) { picker = (section, task.id) }

    /// One popover per row; the schedule rows each open the shared picker on their section.
    private func pickerBinding(_ section: DetailPicker) -> Binding<Bool> {
        Binding(get: { picker?.section == section && picker?.taskID == task.id },
                set: { if !$0, picker?.section == section { picker = nil } })
    }

    private func schedulePopover(_ section: DetailPicker) -> some View {
        // Staged input belongs to the task the popover was opened on.
        TaskSchedulePicker(block: task, initialSection: section)
            .id(task.id)
            .environment(env)
    }

    private func propertyLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(NX.ink(0.45))
            .frame(width: 78, alignment: .leading)
            .gridColumnAlignment(.leading)
    }

    /// The Due label doubles as the date and time picker, so the four day
    /// pills keep the row to themselves. It shows the due time when there is one.
    private var dueLabel: some View {
        Button { openPicker(.due) } label: {
            HStack(spacing: 5) {
                Text("Due")
                if task.includesTime, let due = task.dueDate {
                    Text(NXFormat.clock(due)).monospacedDigit()
                } else {
                    Image(systemName: "calendar").font(.system(size: 10.5, weight: .medium))
                }
            }
            .font(.system(size: 11.5, weight: .medium))
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 5,
                                        padding: EdgeInsets(top: 3, leading: 5, bottom: 3, trailing: 5),
                                        foreground: NX.ink(0.45), hoverForeground: NX.ink))
        .padding(.leading, -5)
        .help("Date and time (⌃D)")
        .accessibilityLabel("Due date and time")
        .frame(width: 78, alignment: .leading)
        .gridColumnAlignment(.leading)
    }

    /// Native type sets wider than the design's, so the day pills trim their
    /// sides to fit Today, Tomorrow, Next week and None on one line.
    private static let duePillPadding = EdgeInsets(top: 5, leading: 6, bottom: 5, trailing: 6)

    /// A week from today, matching `Store.setDueNextWeek`, so it never equals Tomorrow.
    private var nextWeekOffset: Int { 7 }

    private var dueOptions: [(label: String, offset: Int?)] {
        var options: [(String, Int?)] = [("Today", 0), ("Tomorrow", 1), ("Next week", nextWeekOffset), ("None", nil)]
        if let due = task.dueDate {
            let offset = NXFormat.dayOffset(due)
            if ![0, 1, nextWeekOffset].contains(offset) { options.insert((NXFormat.dueLabel(due), offset), at: 0) }
        }
        return options
    }

    private func isDue(_ offset: Int?) -> Bool {
        guard let due = task.dueDate else { return offset == nil }
        return offset == NXFormat.dayOffset(due)
    }

    static func priorityColor(_ priority: TaskPriority) -> Color {
        NX.priorityStroke(priority) ?? NX.ink(0.25)
    }

    static func priorityTitle(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "None"
        case .low: "Low"
        case .medium: "Med"
        case .high: "High"
        }
    }

    // MARK: Plan card

    private var planCard: some View {
        let planned = workbench.isPlanned(task)
        let estimate = task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : env.workbench.defaultEstimate
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 13)).foregroundStyle(style.accent)
                Text("Plan for today").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NX.ink)
                Spacer(minLength: 6)
                NXToggle(isOn: planned, label: "Plan for today") { workbench.plan([task.id]) }
                    .help(task.isCompleted ? "Completed tasks can’t be planned" : "Plan for today (P)")
                    .disabled(task.isCompleted)
            }
            // Planning skips completed tasks, so the switch says so.
            .opacity(task.isCompleted ? 0.45 : 1)
            HStack(spacing: 8) {
                Text("Estimate").font(.system(size: 11.5, weight: .medium)).foregroundStyle(NX.ink(0.5))
                Spacer(minLength: 6)
                stepper("minus") { workbench.setEstimate(task.id, delta: -5) }
                // Like the design's 44pt cell, a wider value overflows it evenly.
                Text("\(estimate) min")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(NX.ink)
                    .contentTransition(.numericText())
                    .fixedSize()
                    .frame(width: 44)
                stepper("plus") { workbench.setEstimate(task.id, delta: 5) }
            }
            .padding(.top, 11)
            Text(slotText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NX.ink(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
            // Its popover, sheet and expansion belong to one task.
            NXInspectorPlanOptions(task: task)
                .id(task.id)
                .padding(.top, 9)
        }
        .padding(12)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(NX.ink(0.1), lineWidth: 0.5))
    }

    /// Reads the plan the calendar grid draws, so flexible blocks count and past ones don't.
    private var slotText: String {
        let now = Date.now
        guard let placement = env.calendar.visibleBlocks
            .filter({ $0.taskID == task.id && $0.occurrenceID == task.occurrenceID && !$0.isCompleted && $0.end > now })
            .min(by: { $0.start < $1.start }) else {
            return "Not in the calendar yet — ⌘K › Find a slot"
        }
        let offset = NXFormat.dayOffset(placement.start)
        let day = offset == 0 ? "today" : placement.start.formatted(.dateTime.weekday(.abbreviated).day())
        return "In the calendar \(day), \(NXFormat.clock(placement.start))–\(NXFormat.clock(placement.end))"
    }

    private func stepper(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).frame(width: 15, height: 15)
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.1), rest: NX.ink(0.05), radius: 6,
                                        padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3),
                                        foreground: NX.ink(0.6)))
    }

    // MARK: Note & activity

    private var noteBox: some View {
        TextField("Add a note", text: $note.value, selection: $noteSelection, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .lineSpacing(3)
            .foregroundStyle(NX.ink(0.7))
            .focused($focus, equals: .note)
            .onExitCommand { focus = nil }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(NX.ink(focus == .note ? 0.05 : 0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if reveal?.field == .note {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(style.accent, lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
    }

    private var activity: some View {
        let captured = library.isInbox(task) ? "Inbox" : library.list(task.listID)?.displayTitle ?? "a list"
        // Newest first, like the log, with the capture always last.
        let entries = workbench.entries(for: task.id)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Activity")
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.74)
                .textCase(.uppercase)
                .foregroundStyle(NX.ink(0.36))
                .padding(.bottom, 8)
            ForEach(entries) { entry in
                activityRow(icon: entry.icon, text: entry.label, date: entry.at)
                    .transition(.offset(y: 6).combined(with: .opacity))
            }
            activityRow(icon: "plus.circle", text: "Captured in \(captured)", date: task.createdAt)
            NXInspectorHistory(task: task)
                .id(task.id)
                .padding(.top, 6)
        }
        .animation(style.ease(220), value: workbench.entries(for: task.id).count)
    }

    private func activityRow(icon: String, text: String, date: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: icon).font(.system(size: 11.5)).foregroundStyle(NX.ink(0.4)).frame(width: 14)
            Text(text).font(.system(size: 12)).foregroundStyle(NX.ink(0.66)).frame(maxWidth: .infinity, alignment: .leading)
            // "just now" moves on while the panel stays open.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(NXFormat.relative(date, now: context.date)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(NX.ink(0.36))
            }
        }
        .padding(.vertical, 5)
    }

    private var startButton: some View {
        let working = env.calendar.activeSession?.taskID == task.id
        // Paused work on this task resumes where it left off rather than starting over.
        let paused = workbench.isWorkPaused && workbench.workTask?.id == task.id
        return Button {
            if paused { workbench.toggleWorkPause() } else if !working { workbench.startWork(task.id) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: working ? "timer" : "play.fill").font(.system(size: 12))
                Text(working ? "Working…" : paused ? "Resume" : "Start working").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(working ? NX.ink(0.55) : .white)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(working ? NX.ink(0.06) : style.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(task.isCompleted)
    }
}

/// The inspector's small toggle pills: accent when on, faint grey when off.
struct NXInspectorPill<Label: View>: View {
    @Environment(\.nextStyle) private var style
    let isOn: Bool
    var padding = EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(isOn ? .white : NX.ink(0.66))
                .padding(padding)
                .background(isOn ? style.accent : hovering ? NX.ink(0.09) : NX.ink(0.05),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isOn)
    }
}
