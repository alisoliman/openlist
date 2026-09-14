//
//  DocumentView.swift
//  openlist
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Which block holds the caret, and where the caret should go next.
struct EditorFocus: Equatable {
    var blockID: UUID?
    var caret: Int?
    /// Bumped only for programmatic focus moves, so ordinary typing never
    /// resets the caret.
    private(set) var token: Int = 0

    /// Requests focus and caret placement. `caret == -1` means end of text.
    mutating func request(_ id: UUID?, caret: Int? = nil) {
        blockID = id
        self.caret = caret
        token &+= 1
    }

    /// Records focus the user established by clicking, without moving the caret.
    mutating func adopt(_ id: UUID) {
        guard blockID != id else { return }
        blockID = id
        caret = nil
    }
}

/// The `/` menu's live state.
struct SlashState: Equatable {
    var blockID: UUID
    var query: String
    /// The span the trigger occupies, so choosing a block removes exactly the
    /// "/query" the user typed — even mid-line.
    var range: NSRange
    var caretRect: CGRect
    var viewport: CGRect
    var selectedIndex: Int = 0
    var contentHeight: CGFloat = 264
}

/// Renders and edits one document: a list, or a task's detail page.
struct DocumentView: View {
    let document: DocumentContext
    /// Placeholder shown on the sole empty block of an empty document.
    var emptyPlaceholder: String = "Add a task…"
    /// Hides done tasks when the view or list says so.
    var showsCompleted: Bool = true
    /// Order applied to top-level blocks. `.manual` keeps the stored order and
    /// is the only mode where drag-to-reorder makes sense.
    var sorting: ListSorting = .manual
    /// Shows the empty-document capture affordance. It never persists a task
    /// until the user clicks it or asks to create a task.
    var seedsEmptyBlock: Bool = true
    /// Height of the click-to-append area below the last block. A full page
    /// wants a generous target; an inspector panel would just show a gap.
    var trailingSpace: CGFloat = 120

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var fetchedBlocks: [Block]
    @Query(sort: [SortDescriptor(\TaskLabel.name)]) private var allLabels: [TaskLabel]

    @State private var focus = EditorFocus()
    @State private var slash: SlashState?
    @State private var inlineMetadataEdits = InlineMetadataEdits()
    @State private var completionMotionIDs: Set<UUID> = []
    @State private var selectionScopeID = UUID()

    private var completedTaskIDs: Set<UUID> {
        Set(blocks.filter { $0.isTask && $0.isCompleted }.map(\.id))
    }

    init(
        document: DocumentContext,
        emptyPlaceholder: String = "Add a task…",
        showsCompleted: Bool = true,
        sorting: ListSorting = .manual,
        seedsEmptyBlock: Bool = true,
        trailingSpace: CGFloat = 120
    ) {
        self.document = document
        self.emptyPlaceholder = emptyPlaceholder
        self.showsCompleted = showsCompleted
        self.sorting = sorting
        self.seedsEmptyBlock = seedsEmptyBlock
        self.trailingSpace = trailingSpace

        let listID = document.listID
        _fetchedBlocks = Query(
            filter: #Predicate<Block> { $0.trashID == nil && $0.listID == listID },
            sort: [SortDescriptor(\Block.sortIndex)]
        )
    }

    // MARK: - Derived state

    private var blocks: [Block] {
        fetchedBlocks.filter { $0.modelContext != nil && !$0.isDeleted }
    }

    private var reveal: ContentReveal? {
        guard let request = env.navigator.contentReveal,
              request.taskID == nil, request.listID == document.listID,
              document.rootBlockID == nil else { return nil }
        return request
    }

    private var readyRevealID: UUID? { env.navigator.isSearchOpen ? nil : reveal?.id }

    private var allRows: [BlockRow] {
        BlockTree.prioritizingPendingTasks(in: BlockTree.sortingTaskRuns(in: BlockTree.flatten(blocks, root: document.rootBlockID,
            expanding: reveal?.ancestorIDs ?? []), by: sorting))
    }

    /// Rows after hiding completed tasks (and everything nested under them).
    private var rows: [BlockRow] {
        let source = allRows
        guard !showsCompleted else { return source }

        return BlockTree.hidingCompletedTasks(in: source, revealing: reveal?.visiblePath ?? [])
    }

    private var listAccent: ListAccent {
        env.store.list(id: document.listID)?.accent ?? .graphite
    }

    /// Label lookup built once per render rather than per row.
    private var labelsByID: [UUID: TaskLabel] {
        Dictionary(allLabels.filter { $0.modelContext != nil && !$0.isDeleted }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        // Computed once per render and shared by every row, so drawing a
        // document costs one pass over the block list rather than one fetch
        // per row.
        let visibleRows = rows
        let visibleIDs = visibleRows.map(\.id)
        let labelLookup = labelsByID
        let progress = BlockTree.subtaskCounts(in: blocks)

        return LazyVStack(alignment: .leading, spacing: 0) {
            if let reveal {
                ContentRevealNotice(request: reveal, finish: env.navigator.finishReveal)
                    .padding(.bottom, 12)
            }
            ForEach(visibleRows) { row in
                if row.block.modelContext != nil, !row.block.isDeleted {
                    VStack(alignment: .leading, spacing: 0) {
                        // Animate the branch's position as a whole, rather than
                        // interpolating each chip's internal layout during the move.
                        rowView(for: row, labelLookup: labelLookup, progress: progress[row.id])
                        .background {
                            if completionMotionIDs.contains(row.id) {
                                RoundedRectangle(cornerRadius: Theme.Radius.row)
                                    .fill(Theme.canvas)
                            }
                        }
                        .geometryGroup()
                        .overlay {
                            if reveal?.blockID == row.id {
                                RoundedRectangle(cornerRadius: Theme.Radius.row)
                                    .stroke(Theme.accent, lineWidth: 2)
                                    .allowsHitTesting(false)
                            }
                        }
                        if reveal?.blockID == row.id, reveal?.field == .note, !row.block.note.isEmpty {
                            ContentRevealNote(text: row.block.note, query: reveal?.query ?? "", requestID: readyRevealID)
                                .id(ContentReveal.Anchor.blockNote(row.id))
                        }
                    }
                    .id(row.id)
                    .zIndex(completionMotionIDs.contains(row.id) ? 1 : 0)
                }
            }

            trailingTapTarget
        }
        .environment(\.rowSelectionContext, RowSelectionContext(scopeID: selectionScopeID, visibleIDs: visibleIDs) {
            env.activeDocument = document
            focus.request(nil)
            slash = nil
        })
        .onChange(of: visibleIDs, initial: true) { _, ids in
            env.navigator.reconcileSelection(scope: selectionScopeID, visible: ids)
        }
        .onReceive(NotificationCenter.default.publisher(for: .commitPendingTaskTitles)) { _ in
            for block in blocks { commitInlineMetadata(block) }
        }
        .onDisappear {
            if env.navigator.rowSelection.scopeID == selectionScopeID { env.navigator.clearSelection() }
        }
        .scrollTargetLayout()
        .animation(reduceMotion ? nil : .spring(duration: 0.44, bounce: 0.12).delay(0.1),
                   value: completedTaskIDs)
        .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: showsCompleted)
        .onChange(of: completedTaskIDs) { previous, current in
            guard !reduceMotion else { return }
            let changed = previous.symmetricDifference(current)
            let children = BlockTree.childIndex(of: blocks, root: document.rootBlockID)
            var moving = changed
            var queue = Array(changed)
            while let id = queue.popLast() {
                for child in children[id] ?? [] where moving.insert(child.id).inserted {
                    queue.append(child.id)
                }
            }
            completionMotionIDs.formUnion(moving)
        }
        .task(id: completionMotionIDs) {
            guard !completionMotionIDs.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(650)) }
            catch { return }
            completionMotionIDs.removeAll()
        }
        .overlayPreferenceValue(EditorTextBoundsKey.self) { anchors in
            slashMenuOverlay(anchors: anchors)
        }
        .onChange(of: env.commandToken) { _, _ in
            // Only the document the user is actually working in should respond,
            // otherwise ⌘N would fire in both the list and the open task panel.
            guard env.activeDocument == document else { return }
            let structural: [EditorCommand] = [.newTask, .indent, .outdent, .moveUp, .moveDown]
            if let command = env.pendingCommand, structural.contains(command) {
                editorEdit("Edit outline") { handleCommand() }
            } else { handleCommand() }
        }
        .onAppear {
            // A list document claims focus on appear; a task's detail page
            // waits until the user actually edits inside it.
            if document.rootBlockID == nil { env.activeDocument = document }
        }
        .task(id: readyRevealID) {
            guard readyRevealID != nil, let id = reveal?.blockID,
                  let block = blocks.first(where: { $0.id == id }) else { return }
            await Task.yield()
            guard !Task.isCancelled, block.modelContext != nil, !block.isDeleted else { return }
            // A note claims focus only after its lazy card actually appears.
            if reveal?.field == .note { return }
            guard !block.kind.isVoid else { return }
            let caret = SearchProjection.range(of: reveal?.query ?? "", in: block.text)
                .map { NSRange($0, in: block.text).location } ?? 0
            env.activeDocument = document
            focus.request(id, caret: caret)
        }
        .onChange(of: env.activeDocument) { _, active in
            if active != document { slash = nil }
        }
        .onChange(of: document) { _, _ in
            inlineMetadataEdits = InlineMetadataEdits()
            focus = EditorFocus()
            slash = nil
            if document.rootBlockID == nil { env.activeDocument = document }
        }
        .onChange(of: env.navigator.openTaskID) { _, newValue in
            // Closing the detail panel hands control back to the list.
            if newValue == nil, document.rootBlockID == nil {
                env.activeDocument = document
            }
        }
        .onChange(of: blocks.map(\.id)) { _, ids in
            inlineMetadataEdits.retain(blockIDs: Set(ids))
            if !env.navigator.isSelectingRows, let focused = focus.blockID, !ids.contains(focused) {
                focus.request(rows.first(where: { !$0.block.kind.isVoid })?.id, caret: -1)
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowView(
        for row: BlockRow,
        labelLookup: [UUID: TaskLabel],
        progress: (done: Int, total: Int)?
    ) -> some View {
        if row.block.modelContext != nil, !row.block.isDeleted {
            HStack(alignment: .top, spacing: 0) {
                RowSelectionGutter(id: row.id, title: row.block.displayTitle)
                BlockRowView(
                    row: row,
                    listAccent: listAccent,
                    labels: row.block.labelIDs.compactMap { labelLookup[$0] },
                    progress: (progress?.total ?? 0) > 0 ? progress : nil,
                    isFocused: focus.blockID == row.id,
                    isSelected: env.navigator.selection.contains(row.id)
                        && (env.navigator.rowSelection.scopeID == nil || env.navigator.rowSelection.scopeID == selectionScopeID),
                    pendingCaret: focus.blockID == row.id ? focus.caret : nil,
                    focusToken: focus.token,
                    isSlashMenuOpen: slash?.blockID == row.id,
                    onSlashCommand: { command in handleSlashCommand(command) },
                    attributedText: env.store.attributedContent(of: row.block),
                    placeholder: emptyPlaceholder,
                    showsPlaceholder: shouldShowPlaceholder(for: row),
                    actions: actions(for: row)
                )
            }
            .modifier(
                BlockDragAndDrop(
                    row: row,
                    isEnabled: sorting == .manual,
                    onMove: { draggedIDs, position in move(draggedIDs, relativeTo: row, position: position) },
                    onDropText: { text in editorEdit("Drop text") { insertPastedText(text, after: row.block) } }
                )
            )
        }
    }

    /// Blank space under the document: clicking it appends a new task, the way
    /// clicking below a note's last line starts a new line.
    private var trailingTapTarget: some View {
        Color.clear
            .frame(height: trailingSpace)
            .overlay(alignment: .topLeading) {
                if rows.isEmpty, seedsEmptyBlock {
                    Label(emptyPlaceholder, systemImage: "plus.circle")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rows.isEmpty ? emptyPlaceholder : "Add a task")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { appendTask() }
            .onTapGesture {
                if let last = rows.last?.block, last.text.isEmpty, last.kind == .task {
                    focus.request(last.id, caret: -1)
                } else {
                    appendTask()
                }
            }
            .contextMenu {
                FragmentPasteMenu(document: document) { ids in
                    env.activeDocument = document
                    focus.request(ids.first, caret: 0)
                }
            }
    }

    private func shouldShowPlaceholder(for row: BlockRow) -> Bool {
        guard row.block.text.isEmpty else { return false }
        return focus.blockID == row.id || rows.count == 1
    }

    // MARK: - Slash menu

    @ViewBuilder
    private func slashMenuOverlay(anchors: [UUID: Anchor<CGRect>]) -> some View {
        if let slash, let anchor = anchors[slash.blockID] {
            GeometryReader { proxy in
                let frame = proxy[anchor]
                let count = SlashMenuView.matches(query: slash.query).count
                if let menuFrame = SlashMenuLayout.frame(
                    caret: slash.caretRect,
                    viewport: slash.viewport.intersection(CGRect(
                        x: -frame.minX, y: slash.viewport.minY,
                        width: proxy.size.width, height: slash.viewport.height
                    )),
                    preferredHeight: count == 0 ? 44 : min(264, slash.contentHeight)
                ) {
                    SlashMenuView(
                        query: slash.query,
                        selectedIndex: slash.selectedIndex,
                        menuSize: menuFrame.size,
                        onSelect: { kind in applySlashSelection(kind) },
                        onHover: { index in self.slash?.selectedIndex = index },
                        onDismiss: { self.slash = nil },
                        onContentHeight: { height in
                            if self.slash?.blockID == slash.blockID { self.slash?.contentHeight = height }
                        }
                    )
                    .offset(x: frame.minX + menuFrame.minX, y: frame.minY + menuFrame.minY)
                }
            }
        }
    }

    /// Keyboard driving of the slash menu, forwarded from the focused text view.
    private func handleSlashCommand(_ command: SlashMenuCommand) {
        guard var state = slash else { return }
        let results = SlashMenuView.matches(query: state.query)

        switch command {
        case .next:
            guard !results.isEmpty else { return }
            state.selectedIndex = (state.selectedIndex + 1) % results.count
            slash = state
        case .previous:
            guard !results.isEmpty else { return }
            state.selectedIndex = (state.selectedIndex - 1 + results.count) % results.count
            slash = state
        case .confirm:
            guard results.indices.contains(state.selectedIndex) else {
                slash = nil
                return
            }
            applySlashSelection(results[state.selectedIndex])
        case .dismiss:
            slash = nil
        }
    }

    private func applySlashSelection(_ kind: BlockKind) {
        editorEdit("Change block type") { applySlashSelectionContents(kind) }
    }

    private func applySlashSelectionContents(_ kind: BlockKind) {
        guard let state = slash, let block = env.store.block(id: state.blockID) else { return }
        slash = nil

        // Remove exactly the "/query" that summoned the menu. Truncating from
        // the trigger to the end of the line would discard anything typed
        // after it, and the trigger need not be at the end.
        let content = NSMutableAttributedString(attributedString: env.store.attributedContent(of: block))
        guard state.range.location >= 0, NSMaxRange(state.range) <= content.length,
              (content.string as NSString).substring(with: state.range) == "/" + state.query
        else { return }
        content.deleteCharacters(in: state.range)
        env.store.setContent(block, attributed: content)

        switch kind {
        case .divider:
            env.store.changeKind(block, to: .divider)
            let paragraph = env.store.insertBlock(kind: .paragraph, after: block)
            env.store.save()
            focus.request(paragraph.id, caret: 0)

        case .image:
            env.store.changeKind(block, to: .image)
            env.store.save()
            presentImagePicker(for: block)

        default:
            env.store.changeKind(block, to: kind)
            env.store.save()
            focus.request(block.id, caret: state.range.location)
        }
    }

    private func presentImagePicker(for block: Block) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            env.store.changeKind(block, to: .paragraph)
            env.store.save()
            focus.request(block.id, caret: 0)
            return
        }

        do {
            let media = try MediaStore.shared.importFile(at: url)
            block.mediaFilename = media.filename
            block.mediaData = media.data
            block.mediaWidth = media.pixelSize.width
            block.mediaHeight = media.pixelSize.height
            block.mediaCaption = ""
            let paragraph = env.store.insertBlock(kind: .paragraph, after: block)
            env.store.save()
            focus.request(paragraph.id, caret: 0)
        } catch {
            env.store.changeKind(block, to: .paragraph)
            env.store.save()
            MarkdownExporter.presentError(error, operation: "Import image")
        }
    }

    // MARK: - Row actions

    private func actions(for row: BlockRow) -> BlockRowActions {
        let block = row.block
        let blockID = row.id

        return BlockRowActions(
            onChange: { attributed in
                // A native text undo can outlive a structural delete/recreate.
                // Resolve by identity instead of writing a deleted model.
                guard let current = env.store.block(id: blockID) else { return }
                inlineMetadataEdits.recordTextChange(for: current, to: attributed.string)
                env.store.setContent(current, attributed: attributed)
                // Typing only mutates the model; without this the save that
                // fires `onDidSave` never happens, so the widget snapshot
                // would stay stale until some other action saved.
                env.store.scheduleSave(after: .seconds(1))
            },
            onReturn: { caret, content in
                editorEdit("Split block") { handleReturn(block: block, caret: caret, content: content) }
            },
            onTab: { isBacktab, caret in
                editorEdit(isBacktab ? "Outdent block" : "Indent block") { handleTab(block: block, isBacktab: isBacktab, caret: caret) }
            },
            onBackspaceAtStart: { content in
                editorEdit("Merge blocks") { handleBackspace(block: block, content: content) }
            },
            onDeleteAtEnd: {
                editorEdit("Merge blocks") { handleForwardDelete(block: block) }
            },
            onArrowOut: { direction, caret in
                handleArrow(from: block, direction: direction, caret: caret)
            },
            onFocus: {
                guard block.modelContext != nil, !block.isDeleted else { return }
                guard !(NSApp.keyWindow?.firstResponder is RowSelectionNSControl) else { return }
                if slash?.blockID != blockID { slash = nil }
                focus.adopt(blockID)
                env.navigator.selectForEditing(blockID, scope: selectionScopeID, visible: rows.map(\.id))
                // Typing inside a document makes it the target for menu commands.
                env.activeDocument = document
            },
            onEscape: {
                commitInlineMetadata(block)
                slash = nil
                focus.request(nil)
                env.navigator.clearSelection()
            },
            onSlashQuery: { query, range, caretRect, viewport in
                guard let query else {
                    if slash?.blockID == blockID { slash = nil }
                    return
                }
                guard block.modelContext != nil, !block.isDeleted else { return }
                if var existing = slash, existing.blockID == blockID {
                    // Reset the highlight whenever the filter changes, so the
                    // top result is always the one Return picks.
                    if existing.query != query {
                        existing.query = query
                        existing.selectedIndex = 0
                    }
                    existing.range = range
                    existing.caretRect = caretRect
                    existing.viewport = viewport
                    slash = existing
                } else {
                    slash = SlashState(blockID: blockID, query: query, range: range, caretRect: caretRect, viewport: viewport)
                }
            },
            onMarkdownPrefix: { kind in
                editorEdit("Change block type") { applyMarkdownPrefix(kind, to: block) }
            },
            onPasteMultiline: { text in
                editorEdit("Paste blocks") { insertPastedText(text, after: block) }
                return true
            },
            onPasteFragment: {
                editorEditFragment(after: blockID)
                return true
            },
            onSetCaption: { caption in
                block.mediaCaption = caption
                block.touch()
                env.store.scheduleSave()
            },
            onCommitCaption: {
                env.store.save()
            },
            onToggleCollapse: {
                if reveal?.ancestorIDs.contains(block.id) == true, block.isCollapsed {
                    env.navigator.finishReveal()
                } else { env.store.toggleCollapse(block) }
            },
            onToggleCompletion: {
                env.store.toggleCompletion(block)
            },
            onOpenDetails: {
                commitInlineMetadata(block)
                env.navigator.openTask(block.id)
            },
            onSelect: {
                env.navigator.selectRow(block.id, gesture: .replace, scope: selectionScopeID, visible: rows.map(\.id))
                env.activeDocument = document
                focus.request(nil)
            }
        )
    }

    // MARK: - Key handling

    private func handleReturn(block: Block, caret: Int, content: NSAttributedString) -> Bool {
        // An empty continuation block ends the run: outdent, or fall back to text.
        if content.length == 0, block.kind.continuesOnReturn {
            if block.parentID != document.rootBlockID, env.store.outdent(block) {
                env.store.save()
                focus.request(block.id, caret: 0)
                return true
            }
            if block.kind != .paragraph {
                env.store.changeKind(block, to: .paragraph)
                env.store.save()
                focus.request(block.id, caret: 0)
                return true
            }
        }

        // Return at the end of a line commits any date or label the user typed.
        if caret >= content.length {
            commitInlineMetadata(block)

            let newKind: BlockKind = block.kind.continuesOnReturn ? block.kind : .paragraph
            let created: Block
            let hasVisibleChildren = !env.store.children(of: block.id, listID: document.listID).isEmpty
                && !block.isCollapsed
            if hasVisibleChildren {
                created = env.store.insertChild(kind: newKind, of: block)
            } else {
                created = env.store.insertBlock(kind: newKind, after: block)
            }
            env.store.save()
            focus.request(created.id, caret: 0)
            return true
        }

        let created = env.store.splitBlock(block, at: caret, content: content)
        env.store.save()
        focus.request(created.id, caret: 0)
        return true
    }

    private func handleTab(block: Block, isBacktab: Bool, caret: Int) -> Bool {
        let moved = isBacktab ? env.store.outdent(block) : env.store.indent(block)
        if moved {
            env.store.save()
            focus.request(block.id, caret: caret)
        }
        // Consume Tab either way so it never inserts a literal tab character.
        return true
    }

    private func handleBackspace(block: Block, content: NSAttributedString) -> Bool {
        // A styled block first reverts to plain text, matching editors where
        // Backspace peels off the formatting before deleting anything.
        if content.length == 0, block.kind != .paragraph, block.kind != .task {
            env.store.changeKind(block, to: .paragraph)
            env.store.save()
            focus.request(block.id, caret: 0)
            return true
        }

        let outcome = env.store.backspaceAtStart(
            block,
            content: content,
            in: document,
            visibleIDs: showsCompleted ? nil : Set(rows.map(\.id))
        )
        env.store.save()

        switch outcome {
        case .outdented:
            focus.request(block.id, caret: 0)
            return true
        case let .merged(target, caret):
            focus.request(target.id, caret: caret)
            return true
        case let .removed(target):
            focus.request(target?.id, caret: -1)
            return true
        case .noop:
            return false
        }
    }

    private func handleForwardDelete(block: Block) -> Bool {
        // `rows`, not `allRows`: pulling up a row the user cannot see would
        // make text appear from nowhere.
        let currentRows = rows
        guard
            let index = currentRows.firstIndex(where: { $0.id == block.id }),
            index + 1 < currentRows.count
        else { return false }

        // Pulling the next block up is the same operation as it backspacing
        // into this one, so reuse that path.
        let next = currentRows[index + 1].block
        let outcome = env.store.backspaceAtStart(
            next,
            content: env.store.attributedContent(of: next),
            in: document,
            visibleIDs: showsCompleted ? nil : Set(rows.map(\.id))
        )
        env.store.save()

        if case let .merged(target, caret) = outcome {
            focus.request(target.id, caret: caret)
            return true
        }
        return true
    }

    private func handleArrow(from block: Block, direction: EditorArrow, caret: Int) -> Bool {
        let currentRows = rows
        guard let index = currentRows.firstIndex(where: { $0.id == block.id }) else { return false }

        // Dividers and images host no text view, so stepping onto one would
        // consume the key and strand the caret. Skip past them, and decline the
        // key entirely when there is nothing focusable left in that direction.
        let candidates = direction == .up
            ? currentRows[..<index].reversed().map { $0 }
            : Array(currentRows[(index + 1)...])
        guard let target = candidates.first(where: { !$0.block.kind.isVoid }) else { return false }

        commitInlineMetadata(block)
        focus.request(target.id, caret: direction == .up ? -1 : 0)
        return true
    }

    private func applyMarkdownPrefix(_ kind: BlockKind, to block: Block) {
        if kind == .divider {
            env.store.changeKind(block, to: .divider)
            let paragraph = env.store.insertBlock(kind: .paragraph, after: block)
            env.store.save()
            focus.request(paragraph.id, caret: 0)
            return
        }
        // Deliberately no focus request: the block already holds the caret, and
        // the text view has just placed it at 0 after deleting the prefix. A
        // programmatic request resolves a runloop later and would drag the
        // caret back to the start of whatever the user typed next.
        env.store.changeKind(block, to: kind)
        env.store.save()
    }

    // MARK: - Inline metadata

    /// Commits anything the user typed inline — a date phrase, a `#label` —
    /// once the line is finished.
    ///
    /// The rule itself lives in `Store`; what belongs here is only the timing.
    private func commitInlineMetadata(_ block: Block) {
        guard block.modelContext != nil, !block.isDeleted else { return }
        guard inlineMetadataEdits.consume(for: block) else { return }
        env.store.applyInlineMetadata(
            to: block,
            parsesNaturalLanguage: env.settings.parsesNaturalLanguageDates
        )
    }


    // MARK: - Structure changes

    private func appendTask() {
        editorEdit("New task") {
            let created = env.store.appendBlock(kind: .task, to: document)
            env.store.save()
            focus.request(created.id, caret: 0)
        }
    }

    @discardableResult
    private func editorEdit<T>(_ name: String, _ body: () -> T) -> T {
        env.store.undoableEditorEdit(in: document.listID, name: name, undoManager: NSApp.keyWindow?.undoManager, body)
    }

    private func move(_ draggedIDs: [UUID], relativeTo target: BlockRow, position: DropPosition) {
        guard sorting == .manual else { return }
        guard target.block.modelContext != nil, !target.block.isDeleted, !target.block.isTrashed,
              target.block.listID == document.listID,
              env.store.block(id: target.id) != nil,
              env.store.list(id: document.listID) != nil else {
            env.store.editorNotice = "The drop target is no longer available. No rows were changed."
            return
        }
        NotificationCenter.default.post(name: .commitPendingTaskTitles, object: nil)
        let parentID: UUID?
        let aboveID: UUID?
        switch position {
        case .before:
            parentID = target.block.parentID
            aboveID = target.id
        case .after:
            parentID = target.block.parentID
            // The next selected sibling will move too, so it cannot be the
            // insertion anchor for this transaction.
            let selected = Set(draggedIDs)
            let siblings = env.store.children(of: parentID, listID: document.listID)
            let index = siblings.firstIndex { $0.id == target.id }
            aboveID = index.flatMap { position in
                siblings.dropFirst(position + 1).first { !selected.contains($0.id) }?.id
            }
        case .inside:
            parentID = target.id
            aboveID = env.store.children(of: target.id, listID: document.listID)
                .first { !draggedIDs.contains($0.id) }?.id
        }
        do {
            _ = try env.store.moveSelection(draggedIDs, to: document.listID,
                parentID: parentID, above: aboveID, expandsParent: position == .inside,
                undoManager: NSApp.keyWindow?.undoManager)
        } catch { env.store.editorNotice = error.localizedDescription }
    }

    private func insertPastedText(_ text: String, after block: Block) {
        var lines = MarkdownInputRules.parseClipboard(text)
        guard !lines.isEmpty else { return }

        var previous = block
        // Tracks the last block created at each depth so nesting can be rebuilt.
        var parentAtDepth: [Int: Block] = [:]

        // Pasting into an empty block fills it, rather than leaving a blank
        // line above the pasted content.
        if block.text.isEmpty, !block.kind.isVoid {
            let first = lines.removeFirst()
            env.store.changeKind(block, to: first.kind)
            env.store.setPlainText(block, first.text)
            block.isCompleted = first.isCompleted
            block.completedAt = first.isCompleted ? .now : nil
            parentAtDepth[first.depth] = block
        }

        for line in lines {
            let created: Block
            if line.depth > 0, let parent = parentAtDepth[line.depth - 1] {
                created = env.store.insertChild(kind: line.kind, text: line.text, of: parent, at: .last)
            } else {
                created = env.store.insertBlock(kind: line.kind, text: line.text, after: previous)
            }
            created.isCompleted = line.isCompleted
            if line.isCompleted { created.completedAt = .now }
            parentAtDepth[line.depth] = created
            previous = created
        }

        env.store.save()
        focus.request(previous.id, caret: -1)
    }

    private func editorEditFragment(after blockID: UUID) {
        env.store.undoableEditorEdit(in: document.listID, name: "Paste content",
            undoManager: NSApp.keyWindow?.undoManager, includingNewLabels: true) {
            do {
                let ids = try env.store.pasteFragment(FragmentClipboard.read(), in: document, after: blockID)
                env.navigator.selection = Set(ids)
                focus.request(ids.first, caret: 0)
            } catch { env.store.editorNotice = error.localizedDescription }
        }
    }

    // MARK: - Menu commands

    /// The blocks a menu command should act on: the multi-selection when there
    /// is one, otherwise whatever holds the caret.
    private var commandTargets: [Block] {
        let selection = env.navigator.selection
        if !selection.isEmpty {
            return rows.map(\.block).filter { selection.contains($0.id) }
        }
        if let id = focus.blockID, let block = env.store.block(id: id) {
            return [block]
        }
        return []
    }

    private func handleCommand() {
        guard let command = env.consumeCommand() else { return }
        let targets = commandTargets
        guard !SelectionCommandPolicy.reject(command, selectedCount: env.navigator.selection.count, store: env.store) else { return }
        if sorting != .manual, [.moveUp, .moveDown, .indent, .outdent].contains(command) {
            env.store.editorNotice = "Switch to manual order before rearranging rows."
            return
        }

        // Anything that is just "act on these blocks" is defined once on the
        // store; only the cases that need the outline or the caret stay here.
        if env.store.perform(command, on: targets, undoManager: NSApp.keyWindow?.undoManager) {
            if command == .deleteSelection {
                focus.request(nil)
                env.navigator.selection.removeAll()
            }
            return
        }

        switch command {
        case .newTask:
            let created = env.store.prependTask(to: document)
            env.store.save()
            focus.request(created.id, caret: 0)

        case .openDetails:
            if let first = targets.first(where: \.isTask) {
                commitInlineMetadata(first)
                env.navigator.openTask(first.id)
            }

        case .pickDueDate:
            if let first = targets.first(where: \.isTask) {
                env.openTask(first.id, showing: .due)
            }

        case .pickLabel:
            if let first = targets.first(where: \.isTask) {
                env.openTask(first.id, showing: .labels)
            }

        case .indent:
            env.store.batch { for block in targets { _ = env.store.indent(block) } }

        case .outdent:
            env.store.batch { for block in targets.reversed() { _ = env.store.outdent(block) } }

        case .moveUp:
            if let first = targets.first {
                _ = env.store.moveUp(first)
                env.store.save()
            }

        case .moveDown:
            if let first = targets.first {
                _ = env.store.moveDown(first)
                env.store.save()
            }

        case .expandAll:
            env.store.batch {
                for row in allRows where row.hasChildren {
                    env.store.setCollapsed(false, for: row.block)
                }
            }

        case .collapseAll:
            env.store.batch {
                for row in allRows where row.hasChildren {
                    env.store.setCollapsed(true, for: row.block)
                }
            }

        default:
            break
        }
    }
}
