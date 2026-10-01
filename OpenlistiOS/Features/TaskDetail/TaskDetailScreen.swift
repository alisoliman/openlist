//
//  TaskDetailScreen.swift
//  OpenlistiOS
//

import SwiftUI
import SwiftData
import UIKit

/// Task detail (mockup 12), pushed: the task's title and note to edit, When,
/// Priority, List and Labels, Plan for today and its estimate, its subtasks,
/// History (Activity), and Trash and Start working where the dock would be. Every change
/// but typing is one step with Undo in the tray.
struct TaskDetailScreen: View {
    let taskID: UUID
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        if let task = env.store.block(id: taskID), task.isTask, task.trashID == nil {
            TaskDetailPage(task: task)
        } else {
            OLScreen(identifier: PhoneRoute.taskDetail(taskID).screenIdentifier) {
                OLTopBar { OLBackButton(env.backTitle(for: .taskDetail(taskID))) { env.navigator.pop() } }
            } content: {
                OLEmptyState(symbol: "questionmark", tint: OL.muted, title: "This task is gone",
                             message: "It was moved to Trash or deleted on another device.")
                    .padding(.top, 80)
            }
        }
    }
}

private struct TaskDetailPage: View {
    let task: Block
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var title = SyncedTextDraft()
    @State private var note = SyncedTextDraft()
    @State private var newSubtask = ""
    /// The subtask field is up, from Add subtask.
    @State private var addsSubtask = false
    @State private var sheet: DetailSheet?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case title, note, subtask }

    private enum DetailSheet: String, Identifiable {
        case due, labels, history
        var id: String { rawValue }
    }

    var body: some View {
        let navigator = env.navigator
        let actions = env.actions
        let now = env.now
        let closing = actions.isClosing(task.id)
        let done = task.isCompleted || closing
        OLScreen(identifier: PhoneRoute.taskDetail(task.id).screenIdentifier) {
            OLTopBar {
                OLBackButton(env.backTitle(for: .taskDetail(task.id))) { navigator.pop() }
            } trailing: {
                OLIconButton(task.isStarred ? "star.fill" : "star", label: task.isStarred ? "Unstar" : "Star", kind: .bare,
                             iconSize: 22, tint: task.isStarred ? OL.today : OL.muted) {
                    actions.edit([task], task.isStarred ? "Unstarred “\(task.displayTitle)”" : "Starred “\(task.displayTitle)”",
                                 icon: "star") { env.store.toggleStar($0) }
                }
                .accessibilityIdentifier("detail.star")
                .accessibilityAddTraits(task.isStarred ? .isSelected : [])
                moreMenu
            }
        } content: {
            HStack(alignment: .top, spacing: 14) {
                OLCheckbox(done ? .done : .open, size: 28, title: task.displayTitle) { actions.toggle(task) }
                    .padding(.top, 0)
                TextField("Task", text: $title.value, axis: .vertical)
                    .font(OLFont.detailTitle)
                    .foregroundStyle(done ? OL.muted : OL.ink)
                    .strikethrough(done, color: OL.muted)
                    .focused($focus, equals: .title)
                    .submitLabel(.done)
                    .onSubmit { commitTitle() }
                    // A field that wraps takes Return as a new line; here it's Done.
                    .onChange(of: title.value) { _, typed in
                        guard typed.contains("\n") else { return }
                        title.value = typed.replacingOccurrences(of: "\n", with: "")
                        focus = nil
                    }
                    .accessibilityIdentifier("detail.title")
            }
            .padding(.top, 12)
            if let parent = TaskDetailContext.parent(of: task, in: env.store) {
                let siblings = library.subtasks(of: parent)
                let completed = siblings.count { $0.isCompleted || actions.isClosing($0.id) }
                Button { TaskDetailContext.openParent(of: task, in: env) } label: {
                    Label("Subtask of \(parent.displayTitle) · \(completed)/\(siblings.count)", systemImage: "arrow.turn.up.left")
                        .font(OLFont.meta)
                        .foregroundStyle(OL.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .background(OL.sunken, in: .capsule)
                }
                .buttonStyle(OLPressStyle(scale: 0.98))
                .accessibilityLabel("Subtask of \(parent.displayTitle), \(completed) of \(siblings.count) subtasks complete")
                .accessibilityHint("Opens the parent task.")
                .accessibilityIdentifier("detail.parent")
                .padding(.top, 10)
            }
            TextField("Add a note", text: $note.value, axis: .vertical)
                .font(OLFont.note)
                .foregroundStyle(OL.muted)
                .focused($focus, equals: .note)
                .padding(.leading, 42)
                .padding(.top, 10)
                .accessibilityIdentifier("detail.note")
            fields(now: now)
                .padding(.top, 24)
            plan
                .padding(.top, OLMetrics.cardGap)
            subtasks
            // History goes to Activity, as the design links it; this task's
            // own history is in the ⋯ menu.
            OLLinkRow("History", topSpacing: 16) { env.navigator.open(.activity) }
                .accessibilityIdentifier("detail.history")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Out of the way while typing, as the tab dock goes behind the
            // keyboard: the field being edited keeps the room above it.
            if focus == nil { dock(done: done).transition(.opacity) }
        }
        .animation(.snappy(duration: 0.2), value: focus == nil)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .due:
                DuePickerSheet(date: task.dueDate, includesTime: task.includesTime, now: env.now) { date, timed in
                    actions.schedule([task], on: date, includesTime: timed)
                }
            case .labels: LabelPickerSheet(task: task)
            case .history: TaskHistorySheet(task: task)
            }
        }
        .onAppear {
            title.reset(to: task.text)
            note.reset(to: task.note)
        }
        .onChange(of: task.text) { _, text in title.receive(text) }
        .onChange(of: task.note) { _, text in note.receive(text) }
        .onChange(of: focus) { old, new in
            if old == .title { commitTitle() }
            if old == .note { commitNote() }
            // Leaving the subtask field adds what's typed there, and ends adding.
            if old == .subtask, new != .subtask {
                addSubtask()
                addsSubtask = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commitPendingEditorDrafts)) { _ in commitDrafts() }
        .onDisappear { commitDrafts() }
    }

    // MARK: Fields

    private func fields(now: Date) -> some View {
        let calendar = env.settings.calendar
        let list = library.list(task.listID)
        let labels = env.store.labels(for: task)
        return VStack(spacing: 0) {
            Menu {
                Button("Due date…", systemImage: "calendar") { sheet = .due }
                ForEach([PhoneDay.today, .tomorrow, .nextWeek]) { day in
                    Button(day.title) { env.actions.schedule([task], on: day.date(now: now, calendar: calendar)) }
                }
                let placed = !env.store.placements(taskID: task.id).filter { $0.occurrenceID == task.occurrenceID }.isEmpty
                if !task.isCompleted {
                    Button(placed ? "Move to another slot" : "Find a slot", systemImage: "calendar.badge.plus") {
                        env.actions.fit([task])
                    }
                }
                if placed {
                    Button("Take off the calendar", systemImage: "calendar.badge.minus") { env.actions.unplace(task) }
                }
                if task.dueDate != nil {
                    Button("Clear due date", systemImage: "xmark", role: .destructive) { env.actions.schedule([task], on: nil) }
                }
            } label: {
                OLFieldRow("When") { when(now: now) }.contentShape(.rect)
            }
            .buttonStyle(OLRowPressStyle())
            .accessibilityIdentifier("detail.when")
            Menu {
                Picker("Priority", selection: Binding(get: { task.priority }, set: { priority in
                    env.actions.edit([task], "Priority \(priority.title.lowercased()) · “\(task.displayTitle)”",
                                     icon: "exclamationmark") { env.store.setPriority(priority, for: $0) }
                })) {
                    ForEach(TaskPriority.allCases.reversed(), id: \.self) { Text($0 == .none ? "None" : $0.title).tag($0) }
                }
            } label: {
                OLFieldRow("Priority", separator: .inset(16)) {
                    Text(task.priority == .none ? "None" : task.priority.title)
                        .foregroundStyle(task.priority == .none ? OL.muted : OL.ink)
                }
                .contentShape(.rect)
            }
            .buttonStyle(OLRowPressStyle())
            .accessibilityIdentifier("detail.priority")
            Menu {
                ForEach(library.lists) { destination in
                    Button("\(destination.isSystemInbox ? "📥" : destination.icon) \(destination.displayTitle)") {
                        env.actions.move([task], to: destination)
                    }
                    .disabled(destination.id == task.listID)
                }
            } label: {
                OLFieldRow("List", separator: .inset(16)) {
                    HStack(spacing: 6) {
                        if let list { OLListGlyph(icon: list.isSystemInbox ? "📥" : list.icon, accent: list.accent.color, size: 16) }
                        Text(list?.displayTitle ?? "Inbox").lineLimit(1)
                    }
                    .foregroundStyle(OL.ink)
                }
                .contentShape(.rect)
            }
            .buttonStyle(OLRowPressStyle())
            .accessibilityIdentifier("detail.list")
            Button { sheet = .labels } label: {
                OLFieldRow("Labels", separator: .inset(16)) {
                    Text(labels.isEmpty ? "None" : labels.map { "#\($0.name)" }.joined(separator: " "))
                        .foregroundStyle(labels.isEmpty ? OL.muted : OL.ink)
                        .lineLimit(1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(OLRowPressStyle())
            .accessibilityIdentifier("detail.labels")
        }
        .olCard()
    }

    /// The calendar slot when it has one, "Today, 10:00–11:30"; else when
    /// it's due, toned as a row's date is; else None.
    @ViewBuilder private func when(now: Date) -> some View {
        let calendar = env.settings.calendar
        if let slot = slot(now: now) {
            let day = CompactText.dayOffset(from: now, to: slot.start, calendar: calendar) == 0 ? "Today"
                : CompactText.day(slot.start, now: now, calendar: calendar)
            Text("\(day), \(OLFormat.range(slot.start, slot.end, calendar: calendar))").foregroundStyle(OL.accentText)
        } else if let date = task.dueDate {
            let due = CompactText.due(date, includesTime: task.includesTime, now: now, calendar: calendar)
            Text(CompactText.captureWhen(date, includesTime: task.includesTime, now: now, calendar: calendar))
                .foregroundStyle(due?.tone == .late ? OL.danger : due?.tone == .today ? OL.accentText : OL.ink)
        } else {
            Text("None").foregroundStyle(OL.muted)
        }
    }

    private func slot(now: Date) -> PlannedBlock? {
        CalendarWeek.shownSlot(of: task.id, occurrenceID: task.occurrenceID, in: env.calendar.visibleBlocks, now: now,
                               calendar: env.settings.calendar)
            .flatMap { $0.isCompleted ? nil : $0 }
    }

    // MARK: Plan

    private var plan: some View {
        let now = env.now
        let planned = task.isPlanned(on: now, calendar: env.settings.calendar)
        let defaultEstimate = max(5, Int(env.calendar.preferences.defaultEstimateMinutes))
        return VStack(spacing: 0) {
            OLSettingsRow("Plan for today") {
                Toggle("Plan for today", isOn: Binding(get: { planned }, set: { plan in
                    TaskDetailContext.setPlanned(plan, for: task, in: env)
                }))
                .labelsHidden()
                .olToggle()
                .disabled(!planned && !env.actions.canAddToToday(task, hierarchy: library.hierarchy))
                .accessibilityIdentifier("detail.plan")
            }
            // Five minutes to eight hours, or where a longer one made on the Mac is.
            let estimate = task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : defaultEstimate
            OLEstimateSlider(value: estimate, identifier: "detail.estimate") { env.actions.setEstimate($0, for: task) }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .overlay(alignment: .top) { OLSeparatorLine(separator: .inset(16)) }
                .disabled(task.isCompleted)
        }
        .olCard()
    }

    // MARK: Subtasks

    /// The task's subtasks, how many are done, and a row to add more that
    /// stays open for the next: Return adds one, an empty Return or leaving
    /// the field ends, and text left in it is added rather than lost. A task
    /// with none has "Add subtask" in their place.
    @ViewBuilder private var subtasks: some View {
        let children = library.subtasks(of: task).sorted { $0.sortIndex < $1.sortIndex }
        if !children.isEmpty || addsSubtask {
            OLGroup("Subtasks") {
                if !children.isEmpty {
                    Text("\(children.count { $0.isCompleted }) of \(children.count)")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("detail.subtaskCount")
                }
            } content: {
                VStack(spacing: 0) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                        PhoneTaskRow(task: child, context: .list, separator: index == 0 ? .none : .task(nested: false),
                                     showsCompletion: false)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if !task.isCompleted {
                        addSubtaskRow(separator: children.isEmpty ? .none : .task(nested: false))
                    }
                }
                .olCard()
            }
        } else if !task.isCompleted {
            Button(action: startSubtask) {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    Text("Add subtask")
                    Spacer(minLength: 0)
                }
                .font(OLFont.groupHeader)
                .foregroundStyle(OL.accentText)
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(OLPressStyle(scale: 0.98))
            .padding(.top, 12)
            .accessibilityIdentifier("detail.addSubtaskStart")
        }
    }

    private func addSubtaskRow(separator: OLSeparator) -> some View {
        let text = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: 14) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(focus == .subtask ? OL.accentText : OL.muted)
                .frame(width: 22, height: 22)
            TextField("Add a subtask", text: $newSubtask)
                .font(OLFont.rowTitle)
                .focused($focus, equals: .subtask)
                .submitLabel(.next)
                .onSubmit(submitSubtask)
                .accessibilityIdentifier("detail.addSubtask")
            if !text.isEmpty {
                Button(action: submitSubtask) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(OL.accent)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(OLPressStyle(scale: 0.9))
                .accessibilityLabel("Add subtask")
                .accessibilityIdentifier("detail.addSubtaskButton")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
        .contentShape(.rect)
        .onTapGesture { focus = .subtask }
        .overlay(alignment: .top) { OLSeparatorLine(separator: separator) }
        .animation(.snappy(duration: 0.2), value: text.isEmpty)
    }

    /// Opens the field and gives it the keyboard once it's there; from the
    /// ⋯ menu, once the menu has closed, which would otherwise drop it.
    private func startSubtask() {
        addsSubtask = true
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            if addsSubtask { focus = .subtask }
        }
    }

    /// Return: adds the subtask typed and keeps the field for the next; an
    /// empty one ends adding.
    private func submitSubtask() {
        if addSubtask() {
            focus = .subtask
        } else {
            newSubtask = ""
            focus = nil
            addsSubtask = false
        }
    }

    @discardableResult
    private func addSubtask() -> Bool {
        let text = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        withAnimation(.snappy(duration: 0.25)) {
            let child = env.store.insertChild(kind: .task, text: "", of: task, at: .last)
            env.store.setPlainText(child, text)
            env.store.save()
            newSubtask = ""
        }
        env.haptics.play(.soft)
        return true
    }

    // MARK: Bottom

    private func dock(done: Bool) -> some View {
        let working = env.calendar.activeSession?.taskID == task.id
        return OLActionDock(dropsLikeTheDock: true) {
            OLIconButton("trash", label: "Move to Trash", kind: .raised, size: .large) {
                if env.actions.trash([task]) { env.navigator.pop() }
            }
            .accessibilityIdentifier("detail.trash")
            if done {
                Button { env.actions.toggle(task) } label: {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(env.actions.isClosing(task.id) ? "Undo" : "Reopen")
                    } else {
                        Label(env.actions.isClosing(task.id) ? "Undo" : "Reopen", systemImage: "arrow.uturn.backward")
                    }
                }
                .buttonStyle(.ol(.neutral, size: .large, block: true))
            } else {
                Button {
                    if working || env.actions.startWork(task) { env.navigator.open(.working) }
                } label: {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(working ? "Working…" : "Start working")
                    } else {
                        Label(working ? "Working…" : "Start working", systemImage: working ? "timer" : "play.fill")
                    }
                }
                .buttonStyle(.ol(.primary, size: .large, block: true, glows: true))
                .accessibilityIdentifier("detail.start")
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            if !task.isCompleted {
                Button("Add subtask", systemImage: "text.badge.plus", action: startSubtask)
            }
            Button("Task history", systemImage: "clock.arrow.circlepath") { sheet = .history }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                let copy = env.store.duplicateBlock(task)
                env.store.save()
                env.tray.show("Duplicated “\(task.displayTitle)”", icon: "plus.square.on.square", tone: .accent, seconds: 4)
                env.navigator.open(.taskDetail(copy.id))
            }
            if let libraryID = env.libraryID {
                Button("Copy link", systemImage: "link") {
                    UIPasteboard.general.url = LocalLink(libraryID: libraryID, target: .task(task.id)).url()
                    env.tray.show("Copied a link to “\(task.displayTitle)”", icon: "link", tone: .neutral, seconds: 3)
                }
            }
            Divider()
            Button("Move to Trash", systemImage: "trash", role: .destructive) {
                if env.actions.trash([task]) { env.navigator.pop() }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(OL.ink)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("detail.more")
    }

    // MARK: Drafts

    /// Everything typed and not yet saved, as the page goes: the title, the
    /// note, and a subtask left in its field.
    private func commitDrafts() {
        commitTitle()
        commitNote()
        addSubtask()
    }

    private func commitTitle() {
        guard let text = title.editedValue(normalize: { $0.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces) }), !text.isEmpty else { return }
        env.store.setText(text, for: task)
        title.reset(to: text)
    }

    private func commitNote() {
        guard let text = note.editedValue(normalize: { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) })
        else { return }
        env.store.setNote(text, for: task)
        note.reset(to: text)
    }
}

/// Contextual task actions revalidate live data before changing navigation or
/// Today membership, including after a parent or list changes through sync.
@MainActor
enum TaskDetailContext {
    static func parent(of task: Block, in store: Store) -> Block? {
        guard let parentID = task.parentID, let parent = store.block(id: parentID),
              parent.isTask, !parent.isDeleted, parent.trashID == nil else { return nil }
        var visited: Set<UUID> = [task.id]
        var ancestor: Block? = parent
        while let current = ancestor {
            guard visited.insert(current.id).inserted else { return nil }
            ancestor = current.parentID.flatMap { store.block(id: $0) }
        }
        return parent
    }

    static func openParent(of task: Block, in env: PhoneEnvironment) {
        guard let parent = parent(of: task, in: env.store) else { return }
        let route = PhoneRoute.taskDetail(parent.id)
        func parentPath(from original: [PhoneRoute]) -> [PhoneRoute] {
            if let index = original.firstIndex(of: route) { return Array(original.prefix(index + 1)) }
            var path = original
            // Going up from a directly opened child replaces that child. If
            // the parent was already below it, return to the existing page.
            if path.last == .taskDetail(task.id) { path.removeLast() }
            return path + [route]
        }
        let navigator = env.navigator
        if case .settings = navigator.sheet {
            navigator.settingsPath = parentPath(from: navigator.settingsPath)
        } else {
            navigator.setPath(parentPath(from: navigator.path(for: navigator.tab)), for: navigator.tab)
        }
    }

    static func setPlanned(_ planned: Bool, for task: Block, in env: PhoneEnvironment) {
        if planned {
            env.actions.addToToday(task)
        } else {
            env.actions.edit([task], "Unplanned: “\(task.displayTitle)”", icon: "sun.max") {
                env.store.deselectForToday($0)
            }
        }
    }
}
