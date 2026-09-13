//
//  TaskDetailPanel.swift
//  openlist
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The right-hand inspector for one task.
///
/// A task's detail page behaves like a miniature list: it holds its own blocks
/// (subtasks, text, images) rendered by the same `DocumentView` that draws a
/// full list, plus the scheduling controls along the top.
struct TaskDetailPanel: View {
    @Environment(AppEnvironment.self) private var env

    private var block: Block? {
        env.store.block(id: env.navigator.openTaskID)
    }

    var body: some View {
        Group {
            if let block, block.isTask {
                TaskDetailContent(block: block)
                    .id(block.id)
            } else if block != nil {
                MissingContentView(message: "Only tasks have a detail page.")
            } else {
                MissingContentView(message: "Select a task to see its details.")
            }
        }
        .background(Theme.chrome)
    }
}

/// Each inspected task owns its focus and pending capture. Note text binds to
/// the model so an open inspector reflects both iCloud and MCP changes.
private struct TaskDetailContent: View {
    let block: Block
    private let taskID: UUID

    init(block: Block) {
        self.block = block
        taskID = block.id
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openPicker: DetailPicker?
    @State private var isCapturingTitle = false
    @State private var showsMoreDetails = false
    @State private var isNoteVisible = false
    @State private var captureCancellationArmed = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNoteFocused: Bool

    var body: some View {
        if block.modelContext != nil, !block.isDeleted {
            content(for: block)
        }
    }

    private func content(for block: Block) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                titleSection(block)
                metadataSection(block)
                if isNoteVisible || !block.note.isEmpty {
                    noteSection(block)
                } else {
                    Button("Add note", systemImage: "note.text") {
                        isNoteVisible = true
                        isNoteFocused = true
                    }
                    .buttonStyle(.borderless)
                }
                subtaskSection(block)
                attachmentSection(block)
                footer(block)
            }
            .padding(20)
        }
        .onAppear {
            adoptRequestedPicker()
            focusTitleIfNew(block)
        }
        .onDisappear {
            commitTitle()
            env.finishTaskTitleCapture(taskID, discardEmpty: true)
        }
        .onChange(of: env.requestedPicker) { _, _ in adoptRequestedPicker() }
    }

    // MARK: - Title

    private func titleSection(_ block: Block) -> some View {
        HStack(alignment: .top, spacing: 9) {
            TaskCheckbox(
                isCompleted: block.isCompleted,
                accent: env.store.list(id: block.listID)?.accent.color ?? Theme.accent,
                priority: block.priority,
                action: {
                    claimParentCommands()
                    env.store.toggleCompletion(block)
                }
            )
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    "Task name",
                    text: Binding(
                        get: { block.text },
                        // Splices the edit into the existing content, so renaming a
                        // task here keeps any bold, code or link it already had.
                        set: { env.store.setText($0, for: block) }
                    ),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .foregroundStyle(block.isCompleted ? Theme.tertiaryText : Color.primary)
                .strikethrough(block.isCompleted, color: Theme.tertiaryText)
                .lineLimit(1...6)
                .focused($isTitleFocused)
                .onSubmit(commitTitle)
                .onChange(of: isTitleFocused) { _, focused in
                    if focused { claimParentCommands() } else { commitTitle() }
                }
                .onKeyPress(.escape) {
                    cancelAndClose()
                    return .handled
                }
                .accessibilityLabel("Task name")

                capturePreview
            }

            Button {
                // The button's keyboard equivalent can run before the field's
                // key handler. Both Escape paths must cancel the same way.
                if NSApp.currentEvent?.type == .keyDown,
                   NSApp.currentEvent?.charactersIgnoringModifiers == "\u{1b}" {
                    cancelAndClose()
                } else {
                    commitTitle()
                    env.finishTaskTitleCapture(taskID, discardEmpty: true)
                    env.navigator.closeTask()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Close (Esc)")
            .accessibilityLabel("Close task details")
        }
    }

    // MARK: - Scheduling and tags

    private func metadataSection(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailRow(icon: "folder", title: "List") {
                Menu {
                    ForEach(env.store.allLists()) { list in
                        Button("\(list.icon)  \(list.displayTitle)") {
                            env.store.moveToList(block, list: list)
                        }
                    }
                } label: {
                    let list = env.store.list(id: block.listID)
                    Text("\(list?.icon ?? "") \(list?.displayTitle ?? "None")")
                        .chipStyle(accent: list?.accent.color)
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            DetailRow(icon: "calendar", title: "Due") {
                Button {
                    openPicker = .due
                } label: {
                    if block.dueDate != nil {
                        DueDateChip(block: block)
                    } else {
                        Text("Add date")
                            .chipStyle()
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: pickerBinding(.due), arrowEdge: .bottom) {
                    DueDatePicker(block: block).environment(env)
                }

                if block.dueDate != nil {
                    ClearButton(label: "Clear due date") { env.store.setDueDate(nil, for: block) }
                }
            }

            if !showsMoreDetails {
                optionalMetadata(block, includeInactive: false)
            }

            DisclosureGroup("More details", isExpanded: $showsMoreDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    optionalMetadata(block, includeInactive: true)
                }
                .padding(.top, 8)
            }
            .font(Theme.Font.metadata)
            .transaction { transaction in
                if reduceMotion { transaction.disablesAnimations = true }
            }
        }
        .simultaneousGesture(TapGesture().onEnded { claimParentCommands() })
    }

    @ViewBuilder
    private func optionalMetadata(_ block: Block, includeInactive: Bool) -> some View {
        if includeInactive || block.recurrence != nil {
            DetailRow(icon: "repeat", title: "Repeat") {
                Button {
                    openPicker = .repeatRule
                } label: {
                    Text(block.recurrence?.displayText ?? "Never")
                        .chipStyle(accent: block.recurrence != nil ? Theme.accent : nil)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .popover(isPresented: pickerBinding(.repeatRule), arrowEdge: .bottom) {
                    RecurrencePicker(block: block).environment(env)
                }

                if block.recurrence != nil {
                    ClearButton(label: "Clear repeat rule") { env.store.setRecurrence(nil, for: block) }
                }
            }
        }

        if includeInactive || block.reminderAt != nil {
            DetailRow(icon: "bell", title: "Remind") {
                Button {
                    openPicker = .reminder
                } label: {
                    Text(reminderText(block))
                        .chipStyle(accent: block.reminderAt != nil ? Theme.accent : nil)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .popover(isPresented: pickerBinding(.reminder), arrowEdge: .bottom) {
                    ReminderPicker(block: block).environment(env)
                }

                if block.reminderAt != nil {
                    ClearButton(label: "Clear reminder") { env.store.setReminder(nil, for: block) }
                }
            }
        }

        if includeInactive || !block.labelIDs.isEmpty {
            DetailRow(icon: "tag", title: "Labels") {
                let labels = env.store.labels(for: block)
                Button {
                    openPicker = .labels
                } label: {
                    if labels.isEmpty {
                        Text("Add label")
                            .chipStyle()
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(labels) { label in
                                Text(label.name)
                                    .chipStyle(accent: label.accent.color)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: pickerBinding(.labels), arrowEdge: .bottom) {
                    LabelPicker(block: block).environment(env)
                }
            }
        }

        if includeInactive || block.priority != .none {
            DetailRow(icon: "flag", title: "Priority") {
                Menu {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        CheckmarkMenuItem(priority.title, isSelected: block.priority == priority) {
                            env.store.setPriority(priority, for: block)
                        }
                    }
                } label: {
                    Text(block.priority.title)
                        .chipStyle(accent: block.priority.accent?.color)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }

        if includeInactive || block.isStarred {
            DetailRow(icon: "star", title: "Star") {
                Toggle(
                    "Star task",
                    isOn: Binding(
                        get: { block.isStarred },
                        set: { _ in env.store.toggleStar(block) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel("Star task")
            }
        }
    }

    /// Consumes a picker requested by ⌃D / ⌃L.
    private func adoptRequestedPicker() {
        guard let requested = env.requestedPicker else { return }
        if requested != .due { showsMoreDetails = true }
        openPicker = requested
        env.requestedPicker = nil
    }

    /// A task created by ⌘N arrives empty, so put the caret in its title.
    private func focusTitleIfNew(_ block: Block) {
        guard block.text.isEmpty else { return }
        isCapturingTitle = true
        DispatchQueue.main.async { isTitleFocused = true }
    }

    private func claimParentCommands() {
        env.activeDocument = nil
        env.navigator.selection = [block.id]
    }

    /// Newly created titles use the same metadata parser as outline capture.
    /// Existing names remain literal when the inspector is used to rename them.
    private func commitTitle() {
        guard !captureCancellationArmed else { return }
        // Deleting an inspected task also dismisses its content. Never touch
        // the invalidated model as that view disappears.
        guard let block = env.store.block(id: taskID) else { return }
        if isCapturingTitle, !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isCapturingTitle = false
            env.store.applyInlineMetadata(
                to: block,
                parsesNaturalLanguage: env.settings.parsesNaturalLanguageDates
            )
            env.finishTaskTitleCapture(taskID)
        }
        env.store.save()
    }

    private func cancelAndClose() {
        isCapturingTitle = false
        env.finishTaskTitleCapture(taskID, discardEmpty: true)
        env.store.save()
        env.navigator.closeTask()
    }

    private func keepTitleAsText() {
        isCapturingTitle = false
        env.finishTaskTitleCapture(taskID)
        env.store.save()
        isTitleFocused = true
    }

    @ViewBuilder
    private var capturePreview: some View {
        if isCapturingTitle, env.settings.parsesNaturalLanguageDates {
            let parsed = DateParser.parse(block.text)
            if !parsed.cleanedText.isEmpty, !parsed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if let date = parsed.date {
                        Label(
                            date.formatted(date: .abbreviated, time: parsed.includesTime ? .shortened : .omitted),
                            systemImage: "calendar"
                        )
                    }
                    if let recurrence = parsed.recurrence {
                        Label(recurrence.displayText, systemImage: "repeat")
                    }
                    CaptureLiteralButton(
                        onPressBegan: { captureCancellationArmed = true },
                        onPressEnded: {
                            captureCancellationArmed = false
                            if !isTitleFocused { commitTitle() }
                        },
                        action: keepTitleAsText
                    )
                    .fixedSize()
                    .help("Keep the typed date phrase without scheduling the task")
                }
                .font(Theme.Font.metadata)
                .foregroundStyle(Theme.accent)
            }
        }
    }

    /// Presents `kind` while it is the open picker.
    private func pickerBinding(_ kind: DetailPicker) -> Binding<Bool> {
        Binding(
            get: { openPicker == kind },
            set: { openPicker = $0 ? kind : nil }
        )
    }

    private func reminderText(_ block: Block) -> String {
        guard let reminder = block.reminderAt else { return "None" }
        return Store.absoluteDateText(reminder, includesTime: true)
    }

    // MARK: - Note

    private func noteSection(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel("Note")

            TextEditor(text: Binding(
                get: { block.note },
                set: { env.store.setNote($0, for: block) }
            ))
                .focused($isNoteFocused)
                .accessibilityLabel("Task note")
                .onChange(of: isNoteFocused) { _, focused in
                    if focused { claimParentCommands() }
                }
                .font(Theme.Font.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 54, maxHeight: 160)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.chipFill.opacity(0.6))
                )
                .overlay(alignment: .topLeading) {
                    if block.note.isEmpty {
                        Text("Add extra context…")
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Subtasks

    private func subtaskSection(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionLabel("Subtasks & notes")
                Spacer()
                if let progress = env.store.subtaskProgress(for: block) {
                    SubtaskProgressChip(done: progress.done, total: progress.total)
                }
            }

            // The same outliner the list view uses, rooted at this task.
            DocumentView(
                document: DocumentContext(listID: block.listID ?? UUID(), rootBlockID: block.id),
                emptyPlaceholder: "Add a subtask, or press / for blocks",
                showsCompleted: true,
                seedsEmptyBlock: false,
                trailingSpace: 12
            )
            .id(block.id)

            Button {
                env.store.insertChild(kind: .task, of: block, at: .last)
                env.store.save()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("Add subtask")
                        .font(Theme.Font.metadata)
                }
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Attachments

    private func attachmentSection(_ block: Block) -> some View {
        let attachments = env.store.attachments(for: block.id)

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionLabel("Files")
                Spacer()
                Button("Attach file", systemImage: "paperclip") {
                    presentFilePicker(for: block)
                }
                .buttonStyle(.plain)
                .help("Attach files")
                .accessibilityLabel("Attach files to task")
            }

            if !attachments.isEmpty {
                ForEach(attachments) { attachment in
                    AttachmentRow(attachment: attachment) {
                        MediaStore.shared.delete(filename: attachment.filename)
                        env.store.context.delete(attachment)
                        env.store.save()
                    }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            // The provider calls back off the main actor, so carry the id
            // rather than the model object itself.
            let blockID = block.id
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        guard let target = env.store.block(id: blockID) else { return }
                        attach(url: url, to: target)
                    }
                }
            }
            return true
        }
    }

    private func presentFilePicker(for block: Block) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            attach(url: url, to: block)
        }
    }

    private func attach(url: URL, to block: Block) {
        do {
            let media = try MediaStore.shared.importFile(at: url)
            let existing = env.store.attachments(for: block.id)
            let attachment = Attachment(
                blockID: block.id,
                filename: media.filename,
                displayName: media.displayName,
                contentType: media.contentType,
                byteCount: media.byteCount,
                sortIndex: (existing.last?.sortIndex ?? 0) + BlockTree.indexStep,
                contentData: media.data
            )
            env.store.context.insert(attachment)
            env.store.save()
        } catch {
            MarkdownExporter.presentError(error, operation: "Import attachment")
        }
    }

    // MARK: - Footer

    private func footer(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack(spacing: 8) {
                Button {
                    env.store.moveToInbox(block)
                } label: {
                    Text("Move to Inbox")
                        .font(Theme.Font.metadata)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondaryText)

                Spacer()

                Button(role: .destructive) {
                    env.navigator.closeTask()
                    env.store.deleteBlock(block)
                    env.store.save()
                } label: {
                    Text("Delete")
                        .font(Theme.Font.metadata)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ListAccent.red.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Created \(Store.absoluteDateText(block.createdAt, includesTime: true))")
                if let completedAt = block.completedAt {
                    Text("Completed \(Store.absoluteDateText(completedAt, includesTime: true))")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.tertiaryText)
        }
    }
}

// MARK: - Small pieces

/// Label-and-control row used throughout the inspector.
struct DetailRow<Content: View>: View {
    let icon: String
    let title: String
    let content: Content

    init(icon: String, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        // Resolve model reads while the parent renders. A deferred closure can
        // otherwise read an invalidated SwiftData task during inspector removal.
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 15)

            Text(title)
                .font(Theme.Font.metadata)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 54, alignment: .leading)

            content

            Spacer(minLength: 0)
        }
        .frame(minHeight: 22)
    }
}

struct ClearButton: View {
    var label: String = "Clear"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct AttachmentRow: View {
    let attachment: Attachment
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            if attachment.isImage, let image = MediaStore.shared.image(named: attachment.filename, data: attachment.contentData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.chipFill)
                    )
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.displayName)
                    .font(Theme.Font.metadata)
                    .lineLimit(1)
                Text(attachment.formattedSize)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
            }

            Spacer(minLength: 4)

            Button("Open attachment", systemImage: "arrow.up.forward.square", action: openAttachment)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Open \(attachment.displayName)")

            Button("Remove attachment", systemImage: "trash", action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove attachment \(attachment.displayName)")
                .help("Remove \(attachment.displayName)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? Theme.rowHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: openAttachment)
    }

    private func openAttachment() {
        do {
            guard NSWorkspace.shared.open(try attachment.fileURL()) else {
                throw CocoaError(.fileReadUnknown)
            }
        } catch {
            MarkdownExporter.presentError(error, operation: "Open attachment \(attachment.displayName)")
        }
    }
}


/// Arms the literal-text choice before AppKit changes first responder on mouse
/// down. A queued blur commit could otherwise run before a held click releases.
private struct CaptureLiteralButton: NSViewRepresentable {
    let onPressBegan: () -> Void
    let onPressEnded: () -> Void
    let action: () -> Void

    func makeNSView(context: Context) -> LiteralButton {
        let button = LiteralButton(title: "Keep as text", target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 11)
        button.contentTintColor = .controlAccentColor
        button.setAccessibilityLabel("Keep task title as text")
        button.target = button
        button.action = #selector(LiteralButton.activate(_:))
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: LiteralButton, context: Context) {
        button.onPressBegan = onPressBegan
        button.onPressEnded = onPressEnded
        button.onActivate = action
    }

    final class LiteralButton: NSButton {
        var onPressBegan: (() -> Void)?
        var onPressEnded: (() -> Void)?
        var onActivate: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            onPressBegan?()
            defer { onPressEnded?() }
            super.mouseDown(with: event)
        }

        @objc func activate(_ sender: Any?) {
            onActivate?()
        }
    }
}
