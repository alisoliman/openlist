//
//  SmartTaskRow.swift
//  openlist
//

import AppKit
import SwiftData
import SwiftUI

/// Per-screen lookups shared by every row.
///
/// Cross-list screens render tasks from many lists at once. Resolving the
/// owning list, the labels and the subtask counts per row means one database
/// fetch per row per render; building the tables once and passing them down
/// makes drawing a screen linear in the number of tasks.
struct TaskRowContext {
    var listsByID: [UUID: TaskList] = [:]
    var labelsByID: [UUID: TaskLabel] = [:]
    var progress: [UUID: (done: Int, total: Int)] = [:]
    var titlesByID: [UUID: String] = [:]

    /// Builds every table in a single pass over the supplied models.
    init(tasks: [Block], lists: [TaskList], labels: [TaskLabel]) {
        listsByID = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        labelsByID = Dictionary(labels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        progress = BlockTree.subtaskCounts(in: tasks)
        titlesByID = Dictionary(tasks.map { ($0.id, $0.displayTitle) }, uniquingKeysWith: { first, _ in first })
    }

    init() {}

    func list(for block: Block) -> TaskList? {
        guard let listID = block.listID else { return nil }
        return listsByID[listID]
    }

    func labels(for block: Block) -> [TaskLabel] {
        block.labelIDs.compactMap { labelsByID[$0] }
    }

    func subtaskProgress(for block: Block) -> (done: Int, total: Int)? {
        guard let entry = progress[block.id], entry.total > 0 else { return nil }
        return entry
    }

    /// "in Book the ryokan" for a nested subtask.
    func breadcrumb(for block: Block) -> String? {
        guard let parentID = block.parentID, let title = titlesByID[parentID] else { return nil }
        return "in \(title)"
    }
}

/// A task shown outside its own document — in Today, Tasks, a label view or
/// search results.
///
/// Unlike `BlockRowView` this row is not part of an outline, so it swaps the
/// full block editor for a plain text field and adds a badge naming the list
/// the task actually lives in.
struct SmartTaskRow: View {
    let block: Block
    var context: TaskRowContext
    var showsListBadge: Bool = true
    var showsBreadcrumb: Bool = true
    var selectionGroupID: UUID?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.rowSelectionContext) private var selectionScope
    @State private var isHovering = false
    @State private var titleDraft = SyncedTextDraft()
    @State private var editSessionID = UUID()
    @FocusState private var isEditing: Bool

    private var owningList: TaskList? { context.list(for: block) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RowSelectionGutter(id: block.id, title: block.displayTitle, isPrimaryAppearance: isPrimaryAppearance,
                isRevealed: isHovering)
            TaskCheckbox(
                isCompleted: block.isCompleted,
                accent: owningList?.accent.color ?? Theme.accent,
                priority: block.priority,
                action: { env.store.toggleCompletion(block) }
            )
            .frame(height: 24)
            .accessibilityLabel("\(block.isCompleted ? "Reopen" : "Complete") \(block.displayTitle)")

            VStack(alignment: .leading, spacing: 4) {
                title
                    // Match the detail control's line height for both Text and
                    // TextField, while allowing multiline titles to grow.
                    .frame(minHeight: 24, alignment: .leading)
                if showsBreadcrumb, let breadcrumb = context.breadcrumb(for: block) {
                    Text(breadcrumb)
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
                if hasMetadata { metadata }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            TaskDetailButton(title: block.displayTitle, isRevealed: isHovering || isSelected || isEditing, action: openDetails)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .rowBackground(isSelected: isSelected, isHovering: isHovering)
        .onHover { isHovering = $0 }
        .onAppear { titleDraft.reset(to: block.text) }
        .onReceive(NotificationCenter.default.publisher(for: .commitPendingTaskTitles)) { _ in
            if isEditing { commit() }
        }
        .onDisappear {
            if env.store.activeTitleDrafts[editSessionID] != nil { commit() }
            env.store.activeTitleDrafts.removeValue(forKey: editSessionID)
        }
        .onChange(of: block.text) { _, newValue in
            titleDraft.receive(newValue)
        }
        .contextMenu {
            BlockContextMenu(block: block, actions: contextActions)
            if !block.isCompleted {
                Divider()
                Button("Plan for today") {
                    env.store.selectForToday(block)
                    env.calendar.storeDidChange()
                }
                Button("Start working") { env.calendar.requestWork(WorkTaskReference(block)) }
                Button("Show calendar") { env.navigator.go(to: .calendar) }
            }
        }
    }

    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                metadataChips
                    .fixedSize()
                listBadge
            }
            VStack(alignment: .leading, spacing: 4) {
                metadataChips
                listBadge
            }
        }
    }

    private var hasMetadata: Bool {
        block.dueDate != nil || block.recurrence != nil || block.reminderAt != nil || block.isStarred
            || !block.labelIDs.isEmpty || context.subtaskProgress(for: block) != nil
            || (showsListBadge && owningList != nil && owningList?.isSystemInbox == false)
    }

    private var metadataChips: some View {
        TaskMetadataChips(
            block: block,
            labels: context.labels(for: block),
            progress: context.subtaskProgress(for: block),
            onTapDue: { env.openTask(block.id, showing: .due) },
            onTapLabel: { _ in env.openTask(block.id, showing: .labels) }
        )
    }

    @ViewBuilder
    private var listBadge: some View {
        if showsListBadge, let owningList, !owningList.isSystemInbox {
            Button {
                env.navigator.go(to: .list(owningList.id))
            } label: {
                Text("\(owningList.icon) \(owningList.displayTitle)")
                    .lineLimit(1)
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(QuietButtonStyle())
            .help("Open \(owningList.displayTitle)")
        }
    }

    private var isSelected: Bool {
        env.navigator.selection.contains(block.id)
            && (env.navigator.rowSelection.scopeID == nil || env.navigator.rowSelection.scopeID == selectionScope?.scopeID)
    }

    private var isPrimaryAppearance: Bool {
        selectionGroupID == nil || selectionScope?.firstGroupByBlock[block.id] == selectionGroupID
    }

    /// Open tasks are directly editable; completed ones are not.
    ///
    /// `TextField` silently ignores `.strikethrough`, so a done task has to be
    /// drawn as `Text` to show it. That is no loss: renaming something you have
    /// already ticked off is rare, and un-ticking it restores the field.
    @ViewBuilder
    private var title: some View {
        if block.isCompleted {
            Text(block.displayTitle)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.tertiaryText)
                .strikethrough(true, color: Theme.tertiaryText)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            TextField("Task", text: $titleDraft.value, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .focused($isEditing)
                .lineLimit(1...4)
                .onSubmit(commit)
                .onChange(of: isEditing) { _, editing in
                    if editing {
                        // SwiftUI can report the old title's focus after a
                        // gutter click. The actual responder decides ownership.
                        guard !(NSApp.keyWindow?.firstResponder is RowSelectionNSControl) else { return }
                        env.store.activeTitleDrafts[editSessionID] = block.id
                        titleDraft.reset(to: block.text)
                        if let selectionScope {
                            env.navigator.selectForEditing(block.id, scope: selectionScope.scopeID,
                                visible: selectionScope.visibleIDs)
                        } else { env.navigator.selection = [block.id] }
                        env.activeDocument = nil
                    } else {
                        commit()
                        env.store.activeTitleDrafts.removeValue(forKey: editSessionID)
                    }
                }
        }
    }


    private var contextActions: BlockRowActions {
        BlockRowActions(
            onToggleCompletion: { env.store.toggleCompletion(block) },
            onOpenDetails: openDetails
        )
    }

    private func openDetails() {
        env.navigator.openTask(block.id)
    }

    private func commit() {
        // Blurring happens after a ⌘⌫ delete too, and the block is gone by then.
        guard !block.isDeleted, block.modelContext != nil else { return }

        // Compare trimmed-to-trimmed: otherwise a title that merely ends in a
        // space looks "edited" on every blur and `setPlainText` would drop the
        // block's inline formatting without the user touching anything.
        guard let trimmed = titleDraft.editedValue(normalize: { $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
              trimmed != block.text.trimmingCharacters(in: .whitespacesAndNewlines) else {
            titleDraft.reset(to: block.text)
            return
        }
        env.store.setText(trimmed, for: block)
        env.store.applyInlineMetadata(
            to: block,
            parsesNaturalLanguage: env.settings.parsesNaturalLanguageDates
        )
        env.store.save()
        titleDraft.reset(to: block.text)
    }
}

/// A titled group of tasks with a collapsible header and count.
struct TaskGroupSection<Footer: View>: View {
    let title: String
    var symbol: String?
    var accent: ListAccent = .graphite
    let tasks: [Block]
    var context: TaskRowContext
    var showsListBadge: Bool = true
    var isInitiallyExpanded: Bool = true
    @ViewBuilder var footer: () -> Footer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded: Bool
    @State private var selectionGroupID = UUID()
    @Environment(\.rowSelectionContext) private var selectionScope

    init(
        title: String,
        symbol: String? = nil,
        accent: ListAccent = .graphite,
        tasks: [Block],
        context: TaskRowContext,
        showsListBadge: Bool = true,
        isInitiallyExpanded: Bool = true,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.symbol = symbol
        self.accent = accent
        self.tasks = tasks
        self.context = context
        self.showsListBadge = showsListBadge
        self.isInitiallyExpanded = isInitiallyExpanded
        self.footer = footer
        _isExpanded = State(initialValue: isInitiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                withAnimation(Theme.Motion.feedback(reduceMotion: reduceMotion)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent.color)
                    }

                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(accent == .graphite ? Color.primary : accent.color)

                    Text("\(tasks.count)")
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.tertiaryText)
                        .monospacedDigit()

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") \(title), \(tasks.count) tasks")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                // Lazy so a long group only realizes the rows on screen.
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(tasks) { task in
                        SmartTaskRow(block: task, context: context, showsListBadge: showsListBadge,
                            selectionGroupID: selectionGroupID)
                            .id(selectionScope?.firstGroupByBlock[task.id] == selectionGroupID
                                ? TaskSelectionScrollID.first(task.id)
                                : TaskSelectionScrollID.repeated(group: selectionGroupID, block: task.id))
                    }
                }
                footer()
            }
        }
        .padding(.bottom, 10)
        .preference(key: VisibleSelectionIDsKey.self,
            value: [VisibleSelectionGroup(id: selectionGroupID, blockIDs: isExpanded ? tasks.map(\.id) : [])])
        .animation(Theme.Motion.feedback(reduceMotion: reduceMotion, duration: Theme.Motion.rearrangementDuration),
                   value: tasks.map(\.id))
    }
}

extension TaskGroupSection where Footer == EmptyView {
    init(
        title: String,
        symbol: String? = nil,
        accent: ListAccent = .graphite,
        tasks: [Block],
        context: TaskRowContext,
        showsListBadge: Bool = true,
        isInitiallyExpanded: Bool = true
    ) {
        self.init(
            title: title,
            symbol: symbol,
            accent: accent,
            tasks: tasks,
            context: context,
            showsListBadge: showsListBadge,
            isInitiallyExpanded: isInitiallyExpanded
        ) { EmptyView() }
    }
}
