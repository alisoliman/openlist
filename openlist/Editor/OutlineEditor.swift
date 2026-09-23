//
//  OutlineEditor.swift
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
    var onPasteFragment: () -> Bool = { false }
    var onSetCaption: (String) -> Void = { _ in }
    var onCommitCaption: () -> Void = {}
    var onToggleCollapse: () -> Void = {}
    var onToggleCompletion: () -> Void = {}
    var onOpenDetails: () -> Void = {}
    var onSelect: () -> Void = {}
}

/// Host policy an outline defers to. Every default is the legacy document
/// editor's, so a renderer overrides only what it does differently.
struct OutlineHooks {
    /// Completes or reopens a task. `nil` writes the change straight to the store.
    var toggleCompletion: ((UUID) -> Void)?
    /// Shows a task's details, once any date or label typed into its title
    /// has been committed. `nil` opens the navigator's detail panel.
    var openDetails: ((UUID) -> Void)?
    /// A block took the caret. It can fire more than once for one click.
    var didFocus: (UUID) -> Void = { _ in }
    /// Escape left a block. The text view has already resigned first
    /// responder and the outline has let go of the caret.
    var didEscape: (UUID) -> Void = { _ in }
    /// Offered each menu command and its targets before the store's shared
    /// task commands and the outline's own. Return `true` to claim it.
    var taskCommand: (EditorCommand, [UUID]) -> Bool = { _, _ in false }
}

/// The editing half of a document — a list, or a task's page of subtasks.
///
/// It owns the caret, the `/` menu, the row projection and every key, paste,
/// drop and menu command, and knows nothing about how rows look, so the
/// legacy ``DocumentView`` and a Next-styled renderer can share it. A renderer
/// fetches with ``blocksQuery(for:)``, calls ``configure(document:showsCompleted:sorting:)``
/// and draws ``visibleRows(in:)`` in `body`, gives each row ``actions(for:)``,
/// and attaches ``OutlineEditorLifecycle`` and ``OutlineSlashMenu``.
@MainActor
@Observable
final class OutlineEditor {
    let env: AppEnvironment
    @ObservationIgnored var hooks: OutlineHooks
    /// The list or task page being edited.
    @ObservationIgnored private(set) var document: DocumentContext
    /// Hides done tasks, and everything nested under them, when `false`.
    @ObservationIgnored var showsCompleted: Bool
    /// Completed tasks the host keeps on screen while `showsCompleted` is off.
    @ObservationIgnored var completedTasksKeptVisible: Set<UUID> = []
    /// Order applied to top-level task runs. `.manual` keeps the stored order
    /// and is the only mode that allows rearranging.
    @ObservationIgnored var sorting: ListSorting

    private(set) var focus = EditorFocus()
    private(set) var slash: SlashState?
    /// This document's scope in the navigator's row selection.
    let selectionScopeID = UUID()
    @ObservationIgnored private var inlineMetadataEdits = InlineMetadataEdits()

    init(env: AppEnvironment, document: DocumentContext, showsCompleted: Bool = true,
         sorting: ListSorting = .manual, hooks: OutlineHooks = OutlineHooks()) {
        self.env = env
        self.document = document
        self.showsCompleted = showsCompleted
        self.sorting = sorting
        self.hooks = hooks
    }

    /// Adopts a renderer's current inputs. Call it from `body`: it writes only
    /// untracked state, so the rows drawn in the same pass see the new values
    /// without invalidating the view. A new document's caret and menu reset in
    /// ``documentDidChange()``.
    func configure(document: DocumentContext, showsCompleted: Bool, sorting: ListSorting) {
        self.document = document
        self.showsCompleted = showsCompleted
        self.sorting = sorting
    }

    // MARK: - Rows

    /// The fetch a renderer of `document` should draw from, matching what the
    /// outline's own handlers read.
    static func blocksQuery(for document: DocumentContext) -> Query<Block, [Block]> {
        Query(filter: blocksPredicate(listID: document.listID), sort: [SortDescriptor(\Block.sortIndex)])
    }

    private static func blocksPredicate(listID: UUID) -> Predicate<Block> {
        #Predicate<Block> { $0.trashID == nil && $0.listID == listID }
    }

    /// The reveal this document is showing, if a search or link opened it.
    var reveal: ContentReveal? {
        guard let request = env.navigator.contentReveal,
              request.taskID == nil, request.listID == document.listID,
              document.rootBlockID == nil else { return nil }
        return request
    }

    /// The reveal to act on, once search has stepped aside.
    var readyRevealID: UUID? { env.navigator.isSearchOpen ? nil : reveal?.id }

    /// Every row in display order, before completed tasks are hidden.
    func allRows(in blocks: [Block]) -> [BlockRow] {
        let live = blocks.filter { $0.modelContext != nil && !$0.isDeleted }
        return BlockTree.prioritizingPendingTasks(in: BlockTree.sortingTaskRuns(in: BlockTree.flatten(live,
            root: document.rootBlockID, expanding: reveal?.ancestorIDs ?? []), by: sorting))
    }

    /// The rows to draw: ``allRows(in:)`` after hiding completed tasks, and
    /// everything nested under them, unless the document shows them.
    func visibleRows(in blocks: [Block]) -> [BlockRow] {
        let rows = allRows(in: blocks)
        guard !showsCompleted else { return rows }
        return BlockTree.hidingCompletedTasks(in: rows,
            revealing: (reveal?.visiblePath ?? []).union(completedTasksKeptVisible))
    }

    /// Handlers run outside `body`, where a renderer's query is out of reach,
    /// so they read the same blocks from the store at the moment they act.
    private var blocks: [Block] {
        let descriptor = FetchDescriptor<Block>(predicate: Self.blocksPredicate(listID: document.listID),
                                                sortBy: [SortDescriptor(\.sortIndex)])
        return ((try? env.store.context.fetch(descriptor)) ?? []).filter { $0.modelContext != nil && !$0.isDeleted }
    }

    private var rows: [BlockRow] { visibleRows(in: blocks) }

    // MARK: - Row state

    func isFocused(_ id: UUID) -> Bool { focus.blockID == id }

    /// Caret offset for the row's next programmatic focus pass.
    func pendingCaret(for id: UUID) -> Int? { focus.blockID == id ? focus.caret : nil }

    func isSlashMenuOpen(on id: UUID) -> Bool { slash?.blockID == id }

    /// Whether the row is in the navigator's row selection for this document.
    func isSelected(_ id: UUID) -> Bool {
        env.navigator.selection.contains(id)
            && (env.navigator.rowSelection.scopeID == nil || env.navigator.rowSelection.scopeID == selectionScopeID)
    }

    /// The empty-row hint shows on the caret's row, or on a document's only row.
    func showsPlaceholder(for row: BlockRow, rowCount: Int) -> Bool {
        guard row.block.text.isEmpty else { return false }
        return focus.blockID == row.id || rowCount == 1
    }

    /// Moves the caret programmatically. `caret == -1` means end of text.
    func requestFocus(_ id: UUID?, caret: Int? = nil) {
        focus.request(id, caret: caret)
    }

    // MARK: - Slash menu

    /// Keyboard driving of the slash menu, forwarded from the focused text view.
    func handleSlashCommand(_ command: SlashMenuCommand) {
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

    func applySlashSelection(_ kind: BlockKind) {
        editorEdit("Change block type") { applySlashSelectionContents(kind) }
    }

    func highlightSlashResult(_ index: Int) {
        slash?.selectedIndex = index
    }

    func dismissSlashMenu() {
        slash = nil
    }

    /// The menu's measured height, for a menu still open on `blockID`.
    func setSlashContentHeight(_ height: CGFloat, for blockID: UUID) {
        if slash?.blockID == blockID { slash?.contentHeight = height }
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

    func actions(for row: BlockRow) -> BlockRowActions {
        let block = row.block
        let blockID = row.id

        return BlockRowActions(
            onChange: { [self] attributed in
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
            onReturn: { [self] caret, content in
                editorEdit("Split block") { handleReturn(block: block, caret: caret, content: content) }
            },
            onTab: { [self] isBacktab, caret in
                editorEdit(isBacktab ? "Outdent block" : "Indent block") { handleTab(block: block, isBacktab: isBacktab, caret: caret) }
            },
            onBackspaceAtStart: { [self] content in
                editorEdit("Merge blocks") { handleBackspace(block: block, content: content) }
            },
            onDeleteAtEnd: { [self] in
                editorEdit("Merge blocks") { handleForwardDelete(block: block) }
            },
            onArrowOut: { [self] direction, caret in
                handleArrow(from: block, direction: direction, caret: caret)
            },
            onFocus: { [self] in
                guard block.modelContext != nil, !block.isDeleted else { return }
                guard !(NSApp?.keyWindow?.firstResponder is RowSelectionNSControl) else { return }
                if slash?.blockID != blockID { slash = nil }
                focus.adopt(blockID)
                env.navigator.selectForEditing(blockID, scope: selectionScopeID, visible: rows.map(\.id))
                // Typing inside a document makes it the target for menu commands.
                env.activeDocument = document
                hooks.didFocus(blockID)
            },
            onEscape: { [self] in
                commitInlineMetadata(block)
                slash = nil
                focus.request(nil)
                env.navigator.clearSelection()
                hooks.didEscape(blockID)
            },
            onSlashQuery: { [self] query, range, caretRect, viewport in
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
            onMarkdownPrefix: { [self] kind in
                editorEdit("Change block type") { applyMarkdownPrefix(kind, to: block) }
            },
            onPasteMultiline: { [self] text in
                editorEdit("Paste blocks") { insertPastedText(text, after: block) }
                return true
            },
            onPasteFragment: { [self] in
                editorEditFragment(after: blockID)
                return true
            },
            onSetCaption: { [self] caption in
                block.mediaCaption = caption
                block.touch()
                env.store.scheduleSave()
            },
            onCommitCaption: { [self] in
                env.store.save()
            },
            onToggleCollapse: { [self] in
                if reveal?.ancestorIDs.contains(block.id) == true, block.isCollapsed {
                    env.navigator.finishReveal()
                } else { env.store.toggleCollapse(block) }
            },
            onToggleCompletion: { [self] in
                if let toggle = hooks.toggleCompletion { toggle(blockID) } else { env.store.toggleCompletion(block) }
            },
            onOpenDetails: { [self] in
                openDetails(block)
            },
            onSelect: { [self] in
                env.navigator.selectRow(block.id, gesture: .replace, scope: selectionScopeID, visible: rows.map(\.id))
                env.activeDocument = document
                focus.request(nil)
            }
        )
    }

    private func openDetails(_ block: Block) {
        commitInlineMetadata(block)
        if let open = hooks.openDetails { open(block.id) } else { env.navigator.openTask(block.id) }
    }

    // MARK: - Key handling

    /// A task page's own children are its floor. Outdenting one would move it
    /// out of the page, where the page could no longer show it.
    private func canOutdent(_ block: Block) -> Bool {
        block.parentID != document.rootBlockID
    }

    private func handleReturn(block: Block, caret: Int, content: NSAttributedString) -> Bool {
        // An empty continuation block ends the run: outdent, or fall back to text.
        if content.length == 0, block.kind.continuesOnReturn {
            if canOutdent(block), env.store.outdent(block) {
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
        let moved = isBacktab ? canOutdent(block) && env.store.outdent(block) : env.store.indent(block)
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
        // Visible rows, not all rows: pulling up a row the user cannot see
        // would make text appear from nowhere.
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
            visibleIDs: showsCompleted ? nil : Set(currentRows.map(\.id))
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

    func appendTask() {
        editorEdit("New task") {
            let created = env.store.appendBlock(kind: .task, to: document)
            env.store.save()
            focus.request(created.id, caret: 0)
        }
    }

    /// A click below the last row: back into a trailing empty task, the way
    /// clicking below a note's last line starts a new line, or a new one.
    func focusOrAppendTrailingTask() {
        if let last = rows.last?.block, last.text.isEmpty, last.kind == .task {
            focus.request(last.id, caret: -1)
        } else {
            appendTask()
        }
    }

    /// Takes the caret to the first of `ids`, just pasted from a menu.
    func didPasteFragment(_ ids: [UUID]) {
        env.activeDocument = document
        focus.request(ids.first, caret: 0)
    }

    /// The gutter started a row selection, so the caret steps aside.
    func beginRowSelection() {
        env.activeDocument = document
        focus.request(nil)
        slash = nil
    }

    func dropText(_ text: String, after block: Block) {
        editorEdit("Drop text") { insertPastedText(text, after: block) }
    }

    @discardableResult
    private func editorEdit<T>(_ name: String, _ body: () -> T) -> T {
        env.store.undoableEditorEdit(in: document.listID, name: name, undoManager: NSApp?.keyWindow?.undoManager, body)
    }

    func move(_ draggedIDs: [UUID], relativeTo target: BlockRow, position: DropPosition) {
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
                undoManager: NSApp?.keyWindow?.undoManager)
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
            undoManager: NSApp?.keyWindow?.undoManager, includingNewLabels: true) {
            do {
                let ids = try env.store.pasteFragment(FragmentClipboard.read(), in: document, after: blockID)
                env.navigator.selection = Set(ids)
                focus.request(ids.first, caret: 0)
            } catch { env.store.editorNotice = error.localizedDescription }
        }
    }

    // MARK: - Menu commands

    /// Runs the pending menu command, if this is the document the user is
    /// working in. Call it whenever `env.commandToken` changes.
    func receiveCommand() {
        // Only the document the user is actually working in should respond,
        // otherwise ⌘N would fire in both the list and the open task panel.
        guard env.activeDocument == document else { return }
        let structural: [EditorCommand] = [.newTask, .indent, .outdent, .moveUp, .moveDown]
        if let command = env.pendingCommand, structural.contains(command) {
            editorEdit("Edit outline") { handleCommand() }
        } else { handleCommand() }
    }

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
        // store, unless the host claims it; only the cases that need the
        // outline or the caret stay here.
        if hooks.taskCommand(command, targets.map(\.id))
            || env.store.perform(command, on: targets, undoManager: NSApp?.keyWindow?.undoManager) {
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
                openDetails(first)
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
            env.store.batch { for block in targets.reversed() where canOutdent(block) { _ = env.store.outdent(block) } }

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
                for row in allRows(in: blocks) where row.hasChildren {
                    env.store.setCollapsed(false, for: row.block)
                }
            }

        case .collapseAll:
            env.store.batch {
                for row in allRows(in: blocks) where row.hasChildren {
                    env.store.setCollapsed(true, for: row.block)
                }
            }

        default:
            break
        }
    }

    // MARK: - Lifecycle

    /// A list document claims menu commands on appear; a task's page waits
    /// until the user actually edits inside it.
    func didAppear() {
        if document.rootBlockID == nil { env.activeDocument = document }
    }

    func didDisappear() {
        if env.navigator.rowSelection.scopeID == selectionScopeID { env.navigator.clearSelection() }
    }

    func documentDidChange() {
        inlineMetadataEdits = InlineMetadataEdits()
        focus = EditorFocus()
        slash = nil
        if document.rootBlockID == nil { env.activeDocument = document }
    }

    func activeDocumentDidChange(_ active: DocumentContext?) {
        if active != document { slash = nil }
    }

    func openTaskDidChange(_ openTaskID: UUID?) {
        // Closing the detail panel hands control back to the list.
        if openTaskID == nil, document.rootBlockID == nil {
            env.activeDocument = document
        }
    }

    func visibleRowsDidChange(_ ids: [UUID]) {
        env.navigator.reconcileSelection(scope: selectionScopeID, visible: ids)
    }

    /// Forgets drafts of removed blocks, and moves a caret whose block went away.
    func blocksDidChange(_ ids: [UUID]) {
        inlineMetadataEdits.retain(blockIDs: Set(ids))
        if !env.navigator.isSelectingRows, let focused = focus.blockID, !ids.contains(focused) {
            focus.request(rows.first(where: { !$0.block.kind.isVoid })?.id, caret: -1)
        }
    }

    /// Lifecycle persistence is about to save: finish every row's draft first.
    func commitPendingInlineMetadata() {
        for block in blocks { commitInlineMetadata(block) }
    }

    /// Puts the caret on the revealed match once its row has had a chance to appear.
    func focusReveal() async {
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
}

/// The part of an outline's lifecycle every renderer shares: menu commands,
/// reveal focus, row-selection reconciliation and draft commits.
struct OutlineEditorLifecycle: ViewModifier {
    let editor: OutlineEditor
    /// The renderer's input, so a change reaches ``OutlineEditor/documentDidChange()``.
    let document: DocumentContext
    let visibleIDs: [UUID]
    let blockIDs: [UUID]

    func body(content: Content) -> some View {
        let env = editor.env
        content
            .onChange(of: visibleIDs, initial: true) { _, ids in editor.visibleRowsDidChange(ids) }
            .onReceive(NotificationCenter.default.publisher(for: .commitPendingTaskTitles)) { _ in
                editor.commitPendingInlineMetadata()
            }
            .onDisappear { editor.didDisappear() }
            .onChange(of: env.commandToken) { _, _ in editor.receiveCommand() }
            .onAppear { editor.didAppear() }
            .task(id: editor.readyRevealID) { await editor.focusReveal() }
            .onChange(of: env.activeDocument) { _, active in editor.activeDocumentDidChange(active) }
            .onChange(of: document) { _, _ in editor.documentDidChange() }
            .onChange(of: env.navigator.openTaskID) { _, id in editor.openTaskDidChange(id) }
            .onChange(of: blockIDs) { _, ids in editor.blocksDidChange(ids) }
    }
}

/// The `/` menu, placed at the caret of the row that summoned it. Attach with
/// `overlayPreferenceValue(EditorTextBoundsKey.self)`.
struct OutlineSlashMenu: View {
    let editor: OutlineEditor
    let anchors: [UUID: Anchor<CGRect>]

    var body: some View {
        if let slash = editor.slash, let anchor = anchors[slash.blockID] {
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
                        onSelect: { kind in editor.applySlashSelection(kind) },
                        onHover: { index in editor.highlightSlashResult(index) },
                        onDismiss: { editor.dismissSlashMenu() },
                        onContentHeight: { height in editor.setSlashContentHeight(height, for: slash.blockID) }
                    )
                    .offset(x: frame.minX + menuFrame.minX, y: frame.minY + menuFrame.minY)
                }
            }
        }
    }
}
