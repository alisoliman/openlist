//
//  BlockRowView.swift
//  openlist
//

import SwiftUI
import UniformTypeIdentifiers

/// Callbacks a row hands back to the document that owns it.
struct BlockRowActions {
    var onChange: (NSAttributedString) -> Void = { _ in }
    var onReturn: (Int, NSAttributedString) -> Bool = { _, _ in false }
    var onTab: (Bool, Int) -> Bool = { _, _ in false }
    var onBackspaceAtStart: (NSAttributedString) -> Bool = { _ in false }
    var onDeleteAtEnd: () -> Bool = { false }
    var onArrowOut: (EditorArrow, Int) -> Bool = { _, _ in false }
    var onFocus: () -> Void = {}
    var onEscape: () -> Void = {}
    var onSlashQuery: (String?, NSRange, CGRect, CGRect) -> Void = { _, _, _, _ in }
    var onMarkdownPrefix: (BlockKind) -> Void = { _ in }
    var onPasteMultiline: (String) -> Bool = { _ in false }
    var onSetCaption: (String) -> Void = { _ in }
    var onCommitCaption: () -> Void = {}
    var onToggleCollapse: () -> Void = {}
    var onToggleCompletion: () -> Void = {}
    var onOpenDetails: () -> Void = {}
    var onSelect: () -> Void = {}
}

/// One line of a document: gutter marker, editable text, trailing metadata.
struct BlockRowView: View {
    let row: BlockRow
    let listAccent: ListAccent
    let labels: [TaskLabel]
    let progress: (done: Int, total: Int)?
    let isFocused: Bool
    let isSelected: Bool
    let pendingCaret: Int?
    let focusToken: Int
    let isSlashMenuOpen: Bool
    let onSlashCommand: (SlashMenuCommand) -> Void
    let attributedText: NSAttributedString
    let placeholder: String
    /// `true` when this row is the only empty task in an otherwise blank
    /// document, which is when the hint text is worth showing.
    let showsPlaceholder: Bool
    let actions: BlockRowActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var block: Block { row.block }

    private var captionBinding: Binding<String> {
        Binding(
            get: { block.mediaCaption },
            set: { actions.onSetCaption($0) }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            indentSpacer
            collapseAffordance
            gutter
            content
        }
        .padding(.vertical, Theme.Spacing.rowVertical)
        .padding(.horizontal, 6)
        .rowBackground(isSelected: isSelected, isHovering: isHovering)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu { BlockContextMenu(block: block, actions: actions) }
        .padding(.top, Theme.Editor.topPadding(for: block.kind))
        .padding(.bottom, Theme.Editor.bottomPadding(for: block.kind))
    }

    // MARK: - Pieces

    private var indentSpacer: some View {
        Color.clear
            .frame(width: CGFloat(row.depth) * Theme.Spacing.indentStep, height: 1)
    }

    @ViewBuilder
    private var collapseAffordance: some View {
        Group {
            if row.hasChildren {
                Button(action: actions.onToggleCollapse) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                        .rotationEffect(.degrees(row.isCollapsed ? 0 : 90))
                        .frame(width: 14, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovering || row.isCollapsed ? 1 : 0)
                .help(row.isCollapsed ? "Expand" : "Collapse")
                .accessibilityLabel("\(row.isCollapsed ? "Expand" : "Collapse") \(block.displayTitle)")
            } else {
                Color.clear.frame(width: 14, height: 1)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: row.isCollapsed)
    }

    @ViewBuilder
    private var gutter: some View {
        switch block.kind {
        case .task:
            TaskCheckbox(
                isCompleted: block.isCompleted,
                accent: listAccent.color,
                priority: block.priority,
                action: actions.onToggleCompletion
            )
            .accessibilityLabel("\(block.isCompleted ? "Reopen" : "Complete") \(block.displayTitle)")
            .padding(.trailing, 6)
            .padding(.top, 1)

        case .bullet:
            Circle()
                .fill(Theme.secondaryText.opacity(0.65))
                .frame(width: 5, height: 5)
                .frame(width: 18, height: 18)
                .padding(.trailing, 6)
                .padding(.top, 1)

        case .numbered:
            Text("\(max(1, row.ordinal)).")
                .font(.system(size: Theme.Editor.bodyPointSize, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: 18, alignment: .trailing)
                .padding(.trailing, 6)

        case .quote:
            RoundedRectangle(cornerRadius: 1.5)
                .fill(listAccent.color.opacity(0.5))
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .padding(.trailing, 10)
                .padding(.leading, 2)

        default:
            Color.clear.frame(width: 0, height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .divider:
            dividerContent
        case .image:
            imageContent
        default:
            textContent
        }
    }

    private var textContent: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                BlockTextView(
                    blockID: block.id,
                    kind: block.kind,
                    isCompleted: block.isCompleted,
                    attributedText: attributedText,
                    placeholder: showsPlaceholder ? placeholder : "",
                    isFocused: isFocused,
                    pendingCaret: pendingCaret,
                    focusToken: focusToken,
                    isSlashMenuOpen: isSlashMenuOpen,
                    onSlashCommand: onSlashCommand,
                    callbacks: editorCallbacks
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .anchorPreference(key: EditorTextBoundsKey.self, value: .bounds) { [block.id: $0] }

                if block.isTask, !labels.isEmpty || progress != nil || block.dueDate != nil || block.recurrence != nil || block.reminderAt != nil || block.isStarred {
                    TaskMetadataChips(
                        block: block,
                        labels: labels,
                        progress: progress,
                        onTapDue: actions.onOpenDetails,
                        onTapLabel: { _ in actions.onOpenDetails() }
                    )
                }
            }

            hoverActions
                .frame(width: block.isTask ? 44 : 20, height: 20, alignment: .topTrailing)
        }
    }

    private var dividerContent: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture { actions.onSelect() }
    }

    @ViewBuilder
    private var imageContent: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if let filename = block.mediaFilename,
                   let image = MediaStore.shared.image(named: filename, data: block.mediaData) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 520, maxHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .strokeBorder(Theme.separator, lineWidth: 0.5)
                        )
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "photo")
                        Text("Missing image")
                    }
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(12)
                    .frame(maxWidth: 320)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Theme.chipFill)
                    )
                }

                // Editable, and shown whenever the row is hovered so an empty
                // caption is discoverable rather than invisible forever.
                if !block.mediaCaption.isEmpty || isHovering {
                    TextField("Add a caption…", text: captionBinding)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.tertiaryText)
                        .onSubmit { actions.onCommitCaption() }
                }
            }
            .onTapGesture { actions.onSelect() }

            Spacer(minLength: 0)
            hoverActions
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 0) {
            if block.isTask {
                TaskDetailButton(
                    title: block.displayTitle,
                    isRevealed: isHovering || isFocused || isSelected,
                    action: actions.onOpenDetails
                )
            }
            // Avoid an AppKit-backed menu on every idle row. The context menu
            // remains available, and keyboard selection reveals this control.
            if isHovering || isFocused || isSelected {
                Menu {
                    BlockContextMenu(block: block, actions: actions)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Actions for \(block.displayTitle)")
                .menuIndicator(.hidden)
                .frame(width: 20)
            } else {
                Color.clear.frame(width: 20, height: 20)
            }
        }
    }

    private var editorCallbacks: BlockEditorCallbacks {
        BlockEditorCallbacks(
            onChange: actions.onChange,
            onReturn: actions.onReturn,
            onTab: actions.onTab,
            onBackspaceAtStart: actions.onBackspaceAtStart,
            onDeleteAtEnd: actions.onDeleteAtEnd,
            onArrowOut: actions.onArrowOut,
            onFocus: actions.onFocus,
            onEscape: actions.onEscape,
            onSlashQuery: actions.onSlashQuery,
            onMarkdownPrefix: actions.onMarkdownPrefix,
            onPasteMultiline: actions.onPasteMultiline
        )
    }
}

/// Right-click menu shared by the row body and its "⋯" button.
struct BlockContextMenu: View {
    let block: Block
    let actions: BlockRowActions

    @Environment(AppEnvironment.self) private var env
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if block.isTask {
            Button(block.isCompleted ? "Mark as Not Done" : "Mark as Done") {
                actions.onToggleCompletion()
            }
            Button("Open Details") { actions.onOpenDetails() }
            Divider()

            Menu("Due") {
                Button("Today") { env.store.setDueToday(block) }
                Button("Tomorrow") { env.store.setDueTomorrow(block) }
                Button("Next Week") { env.store.setDueNextWeek(block) }
                if block.dueDate != nil {
                    Divider()
                    Button("Clear Due Date") { env.store.setDueDate(nil, for: block) }
                }
            }

            Menu("Priority") {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    Button(priority.title) { env.store.setPriority(priority, for: block) }
                }
            }

            Menu("Labels") {
                let labels = env.store.allLabels()
                if labels.isEmpty {
                    Text("No labels yet")
                } else {
                    ForEach(labels) { label in
                        CheckmarkMenuItem(label.name, isSelected: block.labelIDs.contains(label.id)) {
                            env.store.toggleLabel(label, on: block)
                        }
                    }
                }
            }

            Button(block.isStarred ? "Remove Star" : "Star") { env.store.toggleStar(block) }
            Divider()

            Menu("Move to List") {
                ForEach(env.store.allLists()) { list in
                    Button("\(list.icon)  \(list.displayTitle)") {
                        edit("Move block", including: list.id) { current in
                            env.store.moveToList(current, list: list)
                        }
                    }
                    .disabled(list.id == block.listID && block.parentID == nil)
                }
            }
            Button("Add to Inbox") {
                guard let inbox = env.store.inboxList() else { return }
                edit("Move to Inbox", including: inbox.id) { current in
                    env.store.moveToInbox(current)
                }
            }
            Divider()
        }

        Menu("Turn Into") {
            ForEach(BlockKind.allCases.filter { $0 != .image }, id: \.self) { kind in
                Button(kind.title) {
                    edit("Change block type") { current in
                        env.store.changeKind(current, to: kind)
                        env.store.save()
                    }
                }
                .disabled(kind == block.kind)
            }
        }

        Button("Duplicate") { duplicate() }
        Button("Copy Text") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(block.text, forType: .string)
        }

        Divider()
        Button("Delete", role: .destructive) {
            edit("Delete block") { current in
                env.store.deleteBlock(current)
                env.store.save()
            }
        }
    }

    private func duplicate() {
        edit("Duplicate block") { current in
            env.store.duplicateBlock(current)
        }
    }

    /// Menu actions share the outline's structural undo history. A move needs
    /// both lists in the snapshot so Undo returns its whole subtree home.
    private func edit(_ name: String, including destinationID: UUID? = nil, _ mutation: (Block) -> Void) {
        guard let current = env.store.block(id: block.id) else { return }
        let listIDs = Set([current.listID, destinationID].compactMap { $0 })
        env.store.undoableEditorEdit(
            in: listIDs,
            name: name,
            undoManager: undoManager ?? NSApp.keyWindow?.undoManager
        ) {
            mutation(current)
        }
    }
}
