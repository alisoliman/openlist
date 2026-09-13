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
/// full list, with compact metadata and optional calendar planning.
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
        .background(Theme.inspector)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.separator.opacity(0.65)).frame(width: 1)
        }
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
    @State private var isCapturingTitle = false
    @State private var showsScheduling = false
    @State private var isNoteVisible = false
    @State private var captureCancellationArmed = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isNoteFocused: Bool
    @State private var noteSelection: TextSelection?
    @State private var titleSelection: TextSelection?

    private var reveal: ContentReveal? {
        guard let request = env.navigator.contentReveal, request.taskID == taskID else { return nil }
        return request
    }
    private var readyRevealID: UUID? { env.navigator.isSearchOpen ? nil : reveal?.id }

    var body: some View {
        if block.modelContext != nil, !block.isDeleted {
            content(for: block)
        }
    }

    private func content(for block: Block) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let reveal {
                    ContentRevealNotice(request: reveal, finish: env.navigator.finishReveal)
                }
                titleSection(block)
                    .id(ContentReveal.Anchor.taskTitle(taskID))
                    .overlay {
                        if reveal != nil, reveal?.field != .note {
                            RoundedRectangle(cornerRadius: 8).stroke(Theme.accent, lineWidth: 2).allowsHitTesting(false)
                        }
                    }
                TaskInspectorMetadata(block: block)
                    .simultaneousGesture(TapGesture().onEnded { claimParentCommands() })
                TaskReminderStatus(block: block)
                Divider()
                if isNoteVisible || !block.note.isEmpty {
                    noteSection(block)
                        .id(ContentReveal.Anchor.taskNote(taskID))
                } else {
                    Button("Add note", systemImage: "note.text") {
                        isNoteVisible = true
                        isNoteFocused = true
                    }
                    .buttonStyle(.borderless)
                }
                subtaskSection(block)
                attachmentSection(block)
                TaskActivitySection(taskID: taskID)
                DisclosureGroup(isExpanded: $showsScheduling) {
                    TaskSchedulingSection(block: block)
                        .padding(.top, 10)
                } label: {
                    Label("Calendar planning", systemImage: "calendar.badge.clock")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.secondaryText)
                }
                .transaction { if reduceMotion { $0.disablesAnimations = true } }
                footer(block)
            }
            .padding(20)
        }
        .onAppear {
            focusTitleIfNew(block)
        }
        .task(id: readyRevealID) {
            guard readyRevealID != nil, let reveal else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            claimParentCommands()
            if reveal.field == .note {
                isNoteVisible = true
                isNoteFocused = true
                noteSelection = SearchProjection.range(of: reveal.query, in: block.note).map { TextSelection(range: $0) }
                proxy.scrollTo(ContentReveal.Anchor.taskNote(taskID), anchor: .center)
            } else {
                isTitleFocused = true
                titleSelection = SearchProjection.range(of: reveal.query, in: block.text).map { TextSelection(range: $0) }
                proxy.scrollTo(ContentReveal.Anchor.taskTitle(taskID), anchor: .top)
            }
        }
        .onDisappear {
            commitTitle()
            env.finishTaskTitleCapture(taskID, discardEmpty: true)
        }
        }
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
            .padding(.top, 7)

            VStack(alignment: .leading, spacing: 6) {
                TextField(
                    "Task name",
                    text: Binding(
                        get: { block.text },
                        // Splices the edit into the existing content, so renaming a
                        // task here keeps any bold, code or link it already had.
                        set: { env.store.setText($0, for: block) }
                    ),
                    selection: $titleSelection,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(Theme.Font.inspectorTitle)
                .foregroundStyle(block.isCompleted ? Theme.tertiaryText : Color.primary)
                .strikethrough(block.isCompleted, color: Theme.tertiaryText)
                .lineLimit(1...)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Note

    private func noteSection(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel("Note")

            TextEditor(text: Binding(
                get: { block.note },
                set: { env.store.setNote($0, for: block) }
            ), selection: $noteSelection)
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
                .overlay {
                    if reveal?.field == .note {
                        RoundedRectangle(cornerRadius: 8).stroke(Theme.accent, lineWidth: 2).allowsHitTesting(false)
                    }
                }
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
