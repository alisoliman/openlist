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
    /// "/query" the user typed, and keeps what follows it.
    var range: NSRange
    var caretRect: CGRect
    var viewport: CGRect
    var selectedIndex: Int = 0
}

/// Callbacks a row hands back to the document that owns it.
struct BlockRowActions {
    var onChange: (NSAttributedString) -> Void = { _ in }
    var onReturn: (Int, NSAttributedString) -> Bool = { _, _ in false }
    var onTab: (Bool, Int) -> Bool = { _, _ in false }
    var onBackspaceAtStart: (NSAttributedString) -> Bool = { _ in false }
    var onArrowOut: (EditorArrow, Int) -> Bool = { _, _ in false }
    var onFocus: () -> Void = {}
    var onFocusApplied: (Int) -> Void = { _ in }
    var onEscape: () -> Void = {}
    var onSlashQuery: (String?, NSRange, CGRect, CGRect) -> Void = { _, _, _, _ in }
    var onMarkdownPrefix: (BlockKind) -> Void = { _ in }
    var onPasteMultiline: (String) -> Bool = { _ in false }
    var onPasteFragment: () -> Bool = { false }
    var onEndEditing: (NSTextStorage) -> Void = { _ in }
    var onLineBreak: () -> Bool = { false }
    var onToggleCollapse: () -> Void = {}
}

extension BlockRowActions {
    /// The part of a row's actions its ``BlockTextView`` reports to.
    var editorCallbacks: BlockEditorCallbacks {
        BlockEditorCallbacks(
            onChange: onChange,
            onReturn: onReturn,
            onTab: onTab,
            onBackspaceAtStart: onBackspaceAtStart,
            onArrowOut: onArrowOut,
            onFocus: onFocus,
            onFocusApplied: onFocusApplied,
            onEscape: onEscape,
            onSlashQuery: onSlashQuery,
            onMarkdownPrefix: onMarkdownPrefix,
            onPasteMultiline: onPasteMultiline,
            onPasteFragment: onPasteFragment,
            onEndEditing: onEndEditing,
            onLineBreak: onLineBreak
        )
    }
}

/// The editing rules an outline follows, the list document's from the
/// design. Only tasks and list items nest, two levels deep at most, and never
/// under a heading or text; Return and Backspace step a line out or convert
/// it instead of merging; `> ` makes text; done top-level tasks leave the
/// document; and a line's whole edit, from the caret arriving to it leaving,
/// is one undo step. A line left empty is removed.
enum OutlinePolicy {
    /// Kinds that nest under a line of their own family.
    static func nests(_ kind: BlockKind) -> Bool {
        kind == .task || kind == .bullet || kind == .numbered
    }

    /// The deepest a line can be indented.
    static let maximumDepth = 2

    /// Whether a line takes lines dropped into it.
    static func holdsDrops(_ row: BlockRow) -> Bool {
        nests(row.block.kind) && row.depth < maximumDepth
    }
}

/// An outline change a host can name and log.
enum OutlineEdit: Equatable {
    /// A line added and written, from the caret arriving to it leaving.
    case added(UUID)
    /// A line's text, kind or place changed while it held the caret.
    case edited(UUID)
    /// A line left empty was taken out.
    case removedEmptyLine(UUID)
    /// A line deleted from its menu.
    case deleted(UUID)
    case indented([UUID])
    case outdented([UUID])
    case moved(UUID, up: Bool)
    /// Lines dragged to another place.
    case dragged([UUID])

    /// The name the outline gives the change when its host has none.
    var defaultName: String {
        switch self {
        case .added: "Added a line"
        case .edited: "Edited a line"
        case .removedEmptyLine: "Removed an empty line"
        case .deleted: "Delete"
        case .indented: "Indent"
        case .outdented: "Outdent"
        case let .moved(_, up): up ? "Move Up" : "Move Down"
        case .dragged: "Move"
        }
    }
}

/// One `/` menu entry: the design's five kinds, then the editor's other
/// kinds, which only a query for them brings up.
struct OutlineSlashOption: Identifiable, Equatable {
    let kind: BlockKind
    let label: String
    let symbol: String
    /// The markdown shorthand that makes the same kind.
    let hint: String
    /// One of the kinds past the design's five.
    let isExtra: Bool
    var id: BlockKind { kind }

    static let all: [OutlineSlashOption] = [
        OutlineSlashOption(kind: .task, label: "Task", symbol: "square", hint: "[ ]", isExtra: false),
        OutlineSlashOption(kind: .heading1, label: "Heading", symbol: "textformat.size.larger", hint: "#", isExtra: false),
        OutlineSlashOption(kind: .heading2, label: "Subheading", symbol: "textformat.size", hint: "##", isExtra: false),
        OutlineSlashOption(kind: .bullet, label: "Bullet", symbol: "list.bullet", hint: "-", isExtra: false),
        OutlineSlashOption(kind: .paragraph, label: "Text", symbol: "text.alignleft", hint: ">", isExtra: false),
        OutlineSlashOption(kind: .heading3, label: "Heading 3", symbol: "textformat.size.smaller", hint: "###", isExtra: true),
        OutlineSlashOption(kind: .numbered, label: "Numbered", symbol: "list.number", hint: "1.", isExtra: true),
        OutlineSlashOption(kind: .quote, label: "Quote", symbol: "text.quote", hint: "", isExtra: true),
        OutlineSlashOption(kind: .code, label: "Code", symbol: "chevron.left.forwardslash.chevron.right", hint: "```", isExtra: true),
        OutlineSlashOption(kind: .divider, label: "Divider", symbol: "minus", hint: "---", isExtra: true),
        OutlineSlashOption(kind: .image, label: "Image", symbol: "photo", hint: "", isExtra: true),
    ]

    /// With no query, the design's five, and for one letter just what the
    /// design's filter by label brings up. From the second letter the
    /// editor's own search words find a kind too, so "h1" and "todo" still
    /// work, and the other kinds come up for their name or search words as
    /// typed from the start.
    static func matching(_ query: String) -> [OutlineSlashOption] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return all.filter { !$0.isExtra } }
        let words = needle.count > 1
        return all.filter { option in
            let label = option.label.lowercased()
            if words, option.kind.searchTerms.contains(where: { $0.hasPrefix(needle) }) { return true }
            return option.isExtra ? words && label.hasPrefix(needle) : label.contains(needle)
        }
    }
}

/// Host policy an outline defers to. Each default leaves the outline, the
/// store or the navigator to act, so a host sets only what it does itself.
struct OutlineHooks {
    /// Shows a task's details, once any date or label typed into its title
    /// has been committed. `nil` opens it in the navigator's inspector.
    var openDetails: ((UUID) -> Void)?
    /// A block took the caret. It can fire more than once for one click.
    var didFocus: (UUID) -> Void = { _ in }
    /// Escape left a block. The text view has already resigned first
    /// responder and the outline has let go of the caret, which the host's
    /// keys can put back with ``OutlineEditor/resumeEditing()``.
    var didEscape: (UUID) -> Void = { _ in }
    /// Offered each menu command and its targets before the store's shared
    /// task commands and the outline's own. Return `true` to claim it.
    var taskCommand: (EditorCommand, [UUID]) -> Bool = { _, _ in false }
    /// What a menu command acts on when no row holds the caret and the
    /// navigator has no selection, such as the host's focused row.
    var commandTargets: () -> [UUID] = { [] }
    /// Names a change's undo step. `nil` keeps ``OutlineEdit/defaultName``.
    var nameEdit: (OutlineEdit) -> String? = { _ in nil }
    /// A change was put on the undo stack under `name`, for a host that logs
    /// changes. Anything it registers on the window's undo manager now lands
    /// in the same step.
    var didRecordEdit: (OutlineEdit, _ name: String) -> Void = { _, _ in }
    /// A new line took the caret.
    var didAddLine: (UUID) -> Void = { _ in }
    /// Shift-Return on a task, for a host that edits notes in place. `nil`
    /// leaves the key doing nothing there, as on the other lines.
    var editNote: ((UUID) -> Void)?
}

/// The editing half of the list document, under ``OutlinePolicy``'s rules.
///
/// It owns the caret, the `/` menu, the row projection and every key, paste,
/// drop and menu command, and knows nothing about how rows look. The
/// renderer, `NXDocumentOutline`, fetches with ``blocksQuery(for:)``, calls
/// ``configure(document:sorting:hooks:)`` and draws ``rowsToDraw(in:)`` in
/// `body`, gives each row ``actions(for:)``, and attaches
/// ``OutlineEditorLifecycle``.
///
/// One editor serves one document. Key the view that owns it on the document,
/// as `NXDocumentOutline` does with `.id(...)`, so another list gets a fresh
/// editor; ``documentDidChange()`` only resets the caret, menu, drafts and
/// kept-visible tasks if a document changes in place. A document rooted at a
/// task, ``DocumentContext/rootBlockID``, is the subtree under it.
@MainActor
@Observable
final class OutlineEditor {
    let env: AppEnvironment
    @ObservationIgnored var hooks: OutlineHooks
    /// The document being edited.
    @ObservationIgnored private(set) var document: DocumentContext { didSet { drawnRows = nil } }
    /// Done top-level tasks the host keeps on screen, which the document
    /// otherwise leaves for the host to list apart.
    @ObservationIgnored var completedTasksKeptVisible: Set<UUID> = [] { didSet { drawnRows = nil } }
    /// Order applied to top-level task runs. `.manual` keeps the stored order
    /// and is the only mode that allows rearranging.
    @ObservationIgnored var sorting: ListSorting { didSet { drawnRows = nil } }
    /// Draws only the document's tasks, each indented under the tasks above
    /// it, as the list's Tasks presentation.
    @ObservationIgnored var tasksOnly = false { didSet { if tasksOnly != oldValue { drawnRows = nil } } }
    /// The rows last drawn, for handlers that run before the next render.
    /// Cleared by any edit made here, or a change to what the rows depend on.
    @ObservationIgnored private var drawnRows: [BlockRow]?

    private(set) var focus = EditorFocus()
    private(set) var slash: SlashState?
    /// This document's scope in the navigator's row selection.
    let selectionScopeID = UUID()
    @ObservationIgnored private var inlineMetadataEdits = InlineMetadataEdits()

    init(env: AppEnvironment, document: DocumentContext, sorting: ListSorting = .manual,
         hooks: OutlineHooks = OutlineHooks()) {
        self.env = env
        self.document = document
        self.sorting = sorting
        self.hooks = hooks
    }

    isolated deinit {
        for observer in undoObservers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Adopts a renderer's current inputs. Call it from `body`: it writes only
    /// untracked state, so the rows drawn in the same pass see the new values
    /// without invalidating the view. A new document's caret and menu reset in
    /// ``documentDidChange()``.
    func configure(document: DocumentContext, sorting: ListSorting, hooks: OutlineHooks) {
        self.document = document
        self.sorting = sorting
        self.hooks = hooks
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

    /// Every row in display order, done tasks included.
    func allRows(in blocks: [Block]) -> [BlockRow] {
        projectedRows(of: blocks.filter { $0.modelContext != nil && !$0.isDeleted })
    }

    /// ``allRows(in:)`` of live blocks, showing what `expanding` folds away
    /// too. Done subtasks stay where they were ticked, as in the design.
    private func projectedRows(of live: [Block], expanding: Set<UUID> = []) -> [BlockRow] {
        BlockTree.sortingTaskRuns(in: BlockTree.flatten(live,
            root: document.rootBlockID, expanding: expanding.union(reveal?.ancestorIDs ?? [])), by: sorting)
    }

    /// The rows to draw: ``allRows(in:)`` without the done top-level tasks,
    /// which the host lists apart, unless a task under one is still open, and
    /// without the sections of collapsed headings. Done subtasks stay in place.
    func visibleRows(in blocks: [Block]) -> [BlockRow] {
        let live = blocks.filter { $0.modelContext != nil && !$0.isDeleted }
        let kept = (reveal?.visiblePath ?? []).union(completedTasksKeptVisible)
            .union(BlockTree.completedTasksHoldingOpenTasks(in: live, root: document.rootBlockID))
        if tasksOnly {
            // Only tasks fold here: what a heading, list item or text line
            // folds away still shows, as tasks under the tasks above.
            let folding = Set(live.lazy.filter { !$0.isTask && $0.isCollapsed }.map(\.id))
            let rows = projectedRows(of: live, expanding: folding)
            return Self.taskOutline(BlockTree.hidingCompletedTasks(in: rows, revealing: kept, topLevelOnly: true))
        }
        let rows = projectedRows(of: live)
        // A revealed line shows through the headings folding it away.
        let unfolded = reveal?.blockID.map { Set(BlockTree.enclosingSections(of: $0, in: rows)) } ?? []
        return BlockTree.hidingCompletedTasks(in: BlockTree.hidingCollapsedSections(in: rows, revealing: unfolded),
                                              revealing: kept, topLevelOnly: true)
    }

    /// Only the tasks among `rows`, each as deep as the tasks above it.
    private static func taskOutline(_ rows: [BlockRow]) -> [BlockRow] {
        var result: [BlockRow] = []
        // The document depth and task depth of each task on the current path.
        var path: [(depth: Int, taskDepth: Int)] = []
        for var row in rows {
            while let last = path.last, last.depth >= row.depth { path.removeLast() }
            guard row.block.isTask else { continue }
            let taskDepth = path.last.map { $0.taskDepth + 1 } ?? 0
            path.append((row.depth, taskDepth))
            row.depth = taskDepth
            result.append(row)
        }
        return result
    }

    /// ``visibleRows(in:)``, for the renderer to draw this pass. The outline
    /// keeps them for the key, focus and command handlers that run before the
    /// next render, so a click or keystroke costs no fetch or projection.
    func rowsToDraw(in blocks: [Block]) -> [BlockRow] {
        let rows = visibleRows(in: blocks)
        drawnRows = rows
        return rows
    }

    /// Handlers run outside `body`, where a renderer's query is out of reach,
    /// so anything beyond the drawn rows is read from the store as it is.
    private var blocks: [Block] {
        let descriptor = FetchDescriptor<Block>(predicate: Self.blocksPredicate(listID: document.listID),
                                                sortBy: [SortDescriptor(\.sortIndex)])
        return ((try? env.store.context.fetch(descriptor)) ?? []).filter { $0.modelContext != nil && !$0.isDeleted }
    }

    /// The rows last drawn while none has been deleted and nothing here has
    /// edited since, otherwise a fresh projection of the store.
    private var rows: [BlockRow] {
        if let drawnRows, drawnRows.allSatisfy({ $0.block.modelContext != nil && !$0.block.isDeleted }) {
            return drawnRows
        }
        return visibleRows(in: blocks)
    }

    // MARK: - Row state

    func isFocused(_ id: UUID) -> Bool { focus.blockID == id }

    /// Caret offset for the row's next programmatic focus pass.
    func pendingCaret(for id: UUID) -> Int? { focus.blockID == id ? focus.caret : nil }

    /// Moves the caret programmatically. `caret == -1` means end of text.
    func requestFocus(_ id: UUID?, caret: Int? = nil) {
        focus.request(id, caret: caret)
    }

    // MARK: - Slash menu

    /// Keyboard driving of the slash menu, forwarded from the focused text view.
    func handleSlashCommand(_ command: SlashMenuCommand) {
        guard var state = slash else { return }
        let results = slashKinds(matching: state.query)

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

    /// The kinds the `/` menu offers for `query`, in its order.
    func slashKinds(matching query: String) -> [BlockKind] {
        OutlineSlashOption.matching(query).map(\.kind)
    }

    func highlightSlashResult(_ index: Int) {
        slash?.selectedIndex = index
    }

    func dismissSlashMenu() {
        slash = nil
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
            convert(block, to: kind)
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
                // Before the model changes, so a line edit starting here
                // begins from the text as it was.
                noteTyping(in: blockID)
                inlineMetadataEdits.recordTextChange(for: current, to: attributed.string)
                writeInLine(current) { env.store.setContent(current, attributed: attributed) }
                // A sorted document can reorder on a title change.
                if sorting != .manual { drawnRows = nil }
                // Typing only mutates the model; without this the save that
                // fires `onDidSave` never happens, so the widget snapshot
                // would stay stale until some other action saved.
                env.store.scheduleSave(after: .seconds(1))
            },
            onReturn: { [self] _, content in
                handleReturn(block: block, content: content)
            },
            onTab: { [self] isBacktab, caret in
                handleTab(block: block, isBacktab: isBacktab, caret: caret)
            },
            onBackspaceAtStart: { [self] content in
                handleBackspace(block: block, content: content)
            },
            onArrowOut: { [self] direction, _ in
                handleArrow(from: block, direction: direction)
            },
            onFocus: { [self] in
                guard block.modelContext != nil, !block.isDeleted else { return }
                if slash?.blockID != blockID { slash = nil }
                escapedBlockID = nil
                // A click into another line ends any caret move on its way.
                if focus.blockID != blockID { appliedFocusToken = focus.token }
                focus.adopt(blockID)
                if redrawnLineID == blockID { redrawnLineID = nil }
                openLine(for: blockID)
                env.navigator.selectForEditing(blockID, scope: selectionScopeID, visible: rows.map(\.id))
                // Typing inside a document makes it the target for menu commands.
                env.activeDocument = document
                hooks.didFocus(blockID)
            },
            onFocusApplied: { [self] token in
                appliedFocusToken = token
            },
            onEscape: { [self] in
                commitInlineMetadata(block)
                if line?.blockID == blockID { commitLine() }
                slash = nil
                focus.request(nil)
                env.navigator.clearSelection()
                escapedBlockID = blockID
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
            onEndEditing: { [self] storage in
                // The text view a kind change replaced, not the line being left.
                guard redrawnLineID != blockID else { return }
                if line?.blockID == blockID { commitLine(undoTarget: storage) }
                // Clicking away lets the caret go, so the host's keys and
                // targets work again. A caret moving to another row has
                // already let go.
                if focus.blockID == blockID {
                    focus.request(nil)
                    if env.navigator.rowSelection.scopeID == selectionScopeID || env.navigator.rowSelection.scopeID == nil {
                        env.navigator.clearSelection()
                    }
                }
            },
            onLineBreak: { [self] in
                // The design's Turn into card takes ⇧↩ as it takes Return.
                if slash?.blockID == blockID {
                    handleSlashCommand(.confirm)
                    return true
                }
                // The design's lines hold one line each: ⇧↩ writes a task's
                // note and does nothing elsewhere. Code, one of the editor's
                // own kinds, keeps its soft break for a snippet of more lines.
                guard block.kind != .code else { return false }
                guard block.isTask, let editNote = hooks.editNote else { return true }
                commitLine()
                focus.request(nil)
                // A new line left empty went as its title was committed.
                if env.store.block(id: blockID) != nil { editNote(blockID) }
                return true
            },
            onToggleCollapse: { [self] in
                if reveal?.ancestorIDs.contains(block.id) == true, block.isCollapsed {
                    env.navigator.finishReveal()
                } else { env.store.toggleCollapse(block) }
                drawnRows = nil
            }
        )
    }

    private func openDetails(_ block: Block) {
        commitInlineMetadata(block)
        if let open = hooks.openDetails { open(block.id) } else { env.navigator.openTask(block.id) }
    }

    // MARK: - Key handling

    /// The document's root is its floor: a line at its top level can't step
    /// out of it, nor one under the task a document is rooted at.
    private func canOutdent(_ block: Block) -> Bool {
        block.parentID != document.rootBlockID
    }

    /// ↑ off a line's first visual line, or ↓ off its last, takes the caret
    /// to the line above or below. ← and → never leave a line, as the
    /// design's lines are single inputs.
    private func handleArrow(from block: Block, direction: EditorArrow) -> Bool {
        let backward = direction == .up
        let currentRows = rows
        guard let index = currentRows.firstIndex(where: { $0.id == block.id }) else { return false }

        // Dividers and images host no text view, so stepping onto one would
        // consume the key and strand the caret. Skip past them, and decline the
        // key entirely when there is nothing focusable left in that direction.
        let candidates = backward
            ? currentRows[..<index].reversed().map { $0 }
            : Array(currentRows[(index + 1)...])
        guard let target = candidates.first(where: { !$0.block.kind.isVoid }) else { return false }

        commitInlineMetadata(block)
        commitLine()
        // The design's startEdit puts the caret at the end of the line either way.
        focus.request(target.id, caret: -1)
        return true
    }

    private func applyMarkdownPrefix(_ kind: BlockKind, to block: Block) {
        // `> ` makes text, as it does in the design.
        let kind = kind == .quote ? .paragraph : kind
        if kind == .divider {
            env.store.changeKind(block, to: .divider)
            let paragraph = env.store.insertBlock(kind: .paragraph, after: block)
            env.store.save()
            focus.request(paragraph.id, caret: 0)
            return
        }
        convert(block, to: kind)
        env.store.save()
        // The document draws a task, or code, in a text view of its own, so a
        // line turning into one or from one needs the keyboard handed over.
        // The request carries no caret: the text view has just put it at 0
        // after deleting the prefix, and a caret resolved a runloop later
        // would drag it back from whatever the user typed next. A text view
        // that stayed alone keeps it where it is.
        focus.request(block.id)
    }

    /// Changes a line's kind. A kind that doesn't nest comes out to the top
    /// level where it stands, as the design's convert resets its depth, and
    /// the lines under it follow it there, since nothing goes under a heading
    /// or text.
    private func convert(_ block: Block, to kind: BlockKind) {
        env.store.changeKind(block, to: kind)
        // The renderer may draw the new kind in a new text view. The one it
        // replaces gives up the keyboard, which isn't the line being left.
        let id = block.id
        redrawnLineID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            if self?.redrawnLineID == id { self?.redrawnLineID = nil }
        }
        guard !OutlinePolicy.nests(kind) else { return }
        while canOutdent(block), env.store.outdent(block) {}
        liftChildren(of: block)
        drawnRows = nil
    }

    /// Moves the lines under `block` out beside it, right after it and in
    /// their order, keeping what's under each of them.
    private func liftChildren(of block: Block) {
        guard let listID = block.listID else { return }
        let children = env.store.children(of: block.id, listID: listID)
        guard !children.isEmpty else { return }
        let siblings = env.store.orderedSiblings(of: block)
        let next = siblings.firstIndex { $0.id == block.id }.flatMap { siblings.dropFirst($0 + 1).first }
        for child in children {
            env.store.move(child, toParent: block.parentID, above: next, in: listID)
        }
    }

    /// A line whose text view a kind change may be replacing.
    @ObservationIgnored private var redrawnLineID: UUID?

    // MARK: - The design's keys

    private func depth(of block: Block) -> Int {
        rows.first { $0.id == block.id }?.depth ?? 0
    }

    /// The design's Return. An empty line steps out a level, or at the top
    /// turns into a task. Otherwise the line is finished, all of it wherever
    /// the caret is, and a new empty one opens below: a heading is followed
    /// by a task, text by text, anything else by its own kind, and a task
    /// whose subtree shows takes it as its first child.
    private func handleReturn(block: Block, content: NSAttributedString) -> Bool {
        if content.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let changed = editorEdit("Edit line") { () -> Bool in
                if depth(of: block) > 0, canOutdent(block) { return env.store.outdent(block) }
                guard block.kind != .task else { return false }
                convert(block, to: .task)
                return true
            }
            if changed {
                env.store.save()
                focus.request(block.id, caret: 0)
            }
            return true
        }

        let row = rows.first { $0.id == block.id }
        commitInlineMetadata(block)
        commitLine()
        guard block.modelContext != nil, !block.isDeleted else { return true }
        addLine(covering: [block.id]) { line(after: block, row: row) }
        return true
    }

    private func line(after block: Block, row: BlockRow?) -> Block {
        let kind: BlockKind = switch block.kind {
        case .heading1, .heading2, .heading3: .task
        case .quote, .divider, .image: .paragraph
        default: block.kind
        }
        return block.isTask && !block.isCollapsed && row?.hasChildren == true
            ? env.store.insertChild(kind: kind, of: block)
            : env.store.insertBlock(kind: kind, after: block)
    }

    private func handleTab(block: Block, isBacktab: Bool, caret: Int) -> Bool {
        let moved = editorEdit(isBacktab ? "Outdent" : "Indent",
                               edit: isBacktab ? .outdented([block.id]) : .indented([block.id])) {
            isBacktab ? outdentLine(block) : indentLine(block)
        }
        if moved {
            env.store.save()
            focus.request(block.id, caret: caret)
        }
        // Consume Tab either way so it never inserts a literal tab character.
        return true
    }

    /// The design's indent. A task or list item goes one level deeper, under
    /// the nearest line above at its own depth, when that line and the one
    /// right above are tasks or list items too, and never past two levels.
    /// Headings and text stay at the top.
    private func indentLine(_ block: Block) -> Bool {
        guard OutlinePolicy.nests(block.kind) else { return false }
        let current = rows
        guard let index = current.firstIndex(where: { $0.id == block.id }), index > 0 else { return false }
        let depth = current[index].depth
        let previous = current[index - 1]
        guard depth < OutlinePolicy.maximumDepth, OutlinePolicy.nests(previous.block.kind), previous.depth >= depth,
              let parent = current[..<index].last(where: { $0.depth <= depth }), parent.depth == depth,
              parent.block.parentID == block.parentID, OutlinePolicy.nests(parent.block.kind),
              env.store.move(block, toParent: parent.id, above: nil, in: document.listID)
        else { return false }
        parent.block.isCollapsed = false
        drawnRows = nil
        return true
    }

    private func outdentLine(_ block: Block) -> Bool {
        guard canOutdent(block), env.store.outdent(block) else { return false }
        drawnRows = nil
        return true
    }

    /// The design's Backspace at the start of a line. An empty line goes and
    /// the caret ends the line above, or starts the one below at the top;
    /// a heading or list item turns into text; a nested line steps out.
    /// Lines never merge.
    private func handleBackspace(block: Block, content: NSAttributedString) -> Bool {
        if content.length == 0 {
            let current = rows
            let index = current.firstIndex { $0.id == block.id } ?? current.endIndex
            // The line above, or with none, the one below, so the caret stays in the document.
            let previous = current[..<index].last { !$0.block.kind.isVoid }
            let next = previous == nil ? current.dropFirst(index + 1).first { !$0.block.kind.isVoid } : nil
            openLine(for: block.id)
            commitLine(removingEmpty: true)
            // A line holding more than its text stays, with the caret.
            guard env.store.block(id: block.id) == nil else { return true }
            if let target = previous ?? next { focus.request(target.id, caret: previous != nil ? -1 : 0) }
            return true
        }
        let changed = editorEdit("Edit line") { () -> Bool in
            if block.kind != .task, block.kind != .paragraph {
                convert(block, to: .paragraph)
                return true
            }
            return depth(of: block) > 0 && outdentLine(block)
        }
        if changed {
            env.store.save()
            focus.request(block.id, caret: 0)
        }
        // Nothing to do still takes the key, so AppKit doesn't beep.
        return true
    }

    /// Selected rows without a selected ancestor, which moves them too.
    private func topmost(_ targets: [Block]) -> [Block] {
        let ids = Set(targets.map(\.id))
        return targets.filter { block in
            var parentID = block.parentID
            var seen: Set<UUID> = [block.id]
            while let id = parentID, seen.insert(id).inserted {
                if ids.contains(id) { return false }
                parentID = env.store.block(id: id)?.parentID
            }
            return true
        }
    }

    /// Indents or outdents rows the host has focused or selected, as Tab
    /// does for the line holding the caret.
    func indent(_ ids: [UUID], outdent: Bool) {
        let targets = topmost(ids.compactMap { env.store.block(id: $0) }.filter { $0.listID == document.listID })
        guard !targets.isEmpty else { return }
        editorEdit(outdent ? "Outdent" : "Indent", edit: outdent ? .outdented(ids) : .indented(ids)) {
            env.store.batch {
                for block in outdent ? targets.reversed() : targets {
                    _ = outdent ? outdentLine(block) : indentLine(block)
                }
            }
        }
    }

    /// Puts the caret in `id`, at the end unless `caret` says otherwise.
    func edit(_ id: UUID, caret: Int? = -1) {
        escapedBlockID = nil
        env.activeDocument = document
        focus.request(id, caret: caret)
    }

    /// Whether `id` is one of the rows on show.
    func shows(_ id: UUID) -> Bool { rows.contains { $0.id == id } }

    /// The nearest task on show after `id`, or before it, for keys that step
    /// through tasks from a line that isn't one.
    func task(beside id: UUID, forward: Bool) -> UUID? {
        let current = rows
        guard let index = current.firstIndex(where: { $0.id == id }) else { return nil }
        let candidates = forward ? Array(current[(index + 1)...]) : current[..<index].reversed()
        return candidates.first { $0.block.isTask }?.id
    }

    /// Turns a line that isn't being written into `kind`, as the `/` menu
    /// turns the line holding the caret, in a step of its own.
    func turn(_ id: UUID, into kind: BlockKind) {
        guard let block = env.store.block(id: id), block.listID == document.listID,
              !block.kind.isVoid, !kind.isVoid, block.kind != kind else { return }
        commitLine()
        editorEdit("Change block type", edit: .edited(id), joiningLine: false) {
            convert(block, to: kind)
            env.store.save()
        }
    }

    /// Deletes a line, keeping what's under it where it shows, in a step of its own.
    func deleteLine(_ id: UUID) {
        guard let block = env.store.block(id: id), block.listID == document.listID else { return }
        commitLine()
        if focus.blockID == id { focus.request(nil) }
        editorEdit("Delete", edit: .deleted(id), joiningLine: false) {
            removeLine(block)
            env.store.save()
        }
    }

    /// The inspector's Add subtask: a task line at the end of `taskID`'s
    /// subtasks, which takes the caret. The task, and whatever folds it
    /// away, open first so the new line shows. A task two levels deep
    /// takes none, as the design's indent allows no deeper.
    ///
    /// As the design's, the line follows the last line under the task, at
    /// that line's depth, as Return there would add it: a task whose last
    /// subtask has one of its own gets another beside that one. It stays
    /// within two levels, and under a task or list item.
    func appendSubtask(to taskID: UUID) {
        let current = blocks
        guard let task = current.first(where: { $0.id == taskID }), task.isTask else { return }
        let depth = BlockTree.ancestors(of: task, in: current).count
        guard depth < OutlinePolicy.maximumDepth else { return }
        unfold(toShow: taskID)
        env.store.setCollapsed(false, for: task)
        let lines = BlockTree.flatten(current, root: taskID, respectCollapse: false)
        let lineByID = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var last = lines.last
        while let line = last, let parentID = line.block.parentID, parentID != taskID,
              depth + 1 + line.depth > OutlinePolicy.maximumDepth
                || lineByID[parentID].map({ !OutlinePolicy.nests($0.block.kind) }) ?? true {
            last = lineByID[parentID]
        }
        addLine(covering: [taskID]) {
            if let last { env.store.insertBlock(kind: .task, after: last.block) }
            else { env.store.insertChild(kind: .task, of: task, at: .last) }
        }
    }

    /// Opens the tasks, list items and headings that fold `id` away, and
    /// keeps the done top-level task it sits under on show.
    func unfold(toShow id: UUID) {
        let current = blocks
        guard let block = current.first(where: { $0.id == id }) else { return }
        let ancestors = BlockTree.ancestors(of: block, in: current)
        let rows = BlockTree.flatten(current, root: document.rootBlockID, respectCollapse: false)
        let headings = Set(BlockTree.enclosingSections(of: id, in: rows))
        env.store.batch {
            for ancestor in ancestors { env.store.setCollapsed(false, for: ancestor) }
            for heading in current where headings.contains(heading.id) { env.store.setCollapsed(false, for: heading) }
        }
        let root = ancestors.last ?? block
        if root.isTask, root.isCompleted { completedTasksKeptVisible.insert(root.id) }
        drawnRows = nil
    }

    /// Whether the caret has been sent to a row that hasn't taken it yet, as
    /// after Return or Backspace, or that hasn't put it where it was sent, as
    /// after Tab, or a kind change that draws the line in a new text view
    /// while the one it replaces still holds the keyboard. Keys pressed
    /// meanwhile belong to that row, once it has.
    var isMovingCaret: Bool {
        guard let id = focus.blockID else { return false }
        return appliedFocusToken != focus.token || textStorage(editing: id) == nil
    }

    /// The last caret move a row's text view carried out, or a click ended.
    @ObservationIgnored private(set) var appliedFocusToken = 0

    // MARK: - Line edits

    /// The edit of one line, from the caret arriving to it leaving, undone
    /// as one step.
    private final class LineEdit {
        let blockID: UUID
        /// Added by this edit, so taking it out again leaves nothing to undo.
        var isNew: Bool
        /// Changed more than the line's text.
        var isStructural: Bool
        /// Its text was already empty when the caret arrived, as an untitled
        /// task or a spacer in an older list is, so passing through leaves it.
        let arrivedEmpty: Bool
        let session: EditorEditSession
        /// Where the line's typing Undo is registered, folded into this step.
        /// A line whose kind changes can be drawn by a new text view. Held
        /// until the step ends, by identity: the undo manager doesn't keep
        /// them, and a text view gone with its storage would leave its typing.
        let undoTargets = NSHashTable<NSTextStorage>(options: [.strongMemory, .objectPointerPersonality])

        init(blockID: UUID, isNew: Bool, arrivedEmpty: Bool, session: EditorEditSession) {
            self.blockID = blockID
            self.isNew = isNew
            isStructural = isNew
            self.arrivedEmpty = arrivedEmpty
            self.session = session
        }
    }

    @ObservationIgnored private var line: LineEdit?
    @ObservationIgnored private var undoObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var isUndoing = false
    @ObservationIgnored private var undoTypedInLine = false

    /// The edit of `id`, finishing any other line's first.
    @discardableResult
    private func openLine(for id: UUID?) -> LineEdit? {
        guard let id else { return nil }
        if let line, line.blockID == id { return line }
        commitLine()
        guard let block = env.store.block(id: id) else { return nil }
        let edit = LineEdit(blockID: id, isNew: false, arrivedEmpty: Self.isBlank(block.text),
                            session: env.store.beginEditorSession(in: document.listID, covering: [id]))
        line = edit
        observeUndo()
        return edit
    }

    /// Adds a line in an edit of its own, which ends as "Added" or, left
    /// empty, leaves nothing to undo. A heading or task folding the new line
    /// away opens, so the caret has a line to land in.
    private func addLine(covering ids: Set<UUID>, _ create: () -> Block) {
        commitLine()
        let session = env.store.beginEditorSession(in: document.listID, covering: ids)
        let created = env.store.recordInEditorSession(session, create)
        env.store.save()
        line = LineEdit(blockID: created.id, isNew: true, arrivedEmpty: true, session: session)
        observeUndo()
        unfold(toShow: created.id)
        env.activeDocument = document
        focus.request(created.id, caret: 0)
        hooks.didAddLine(created.id)
    }

    /// Typing reached the model. Opens the line's edit if nothing has yet,
    /// and learns where the text view registers its typing.
    private func noteTyping(in id: UUID) {
        guard let edit = openLine(for: id) else { return }
        if isUndoing { undoTypedInLine = true }
        if let storage = textStorage(editing: id) { edit.undoTargets.add(storage) }
    }

    /// A change the line being edited makes to its own block, which its
    /// step tells apart from what anything else changes there meanwhile.
    private func writeInLine(_ block: Block, _ body: () -> Void) {
        if let edit = line, edit.blockID == block.id {
            env.store.writeInEditorSession(edit.session, to: block, body)
        } else {
            body()
        }
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Finishes the line being edited. A line left empty is removed, as the
    /// design's commit does, and whatever changed becomes one undo step,
    /// named for what it was, in place of the line's typing. Only a line
    /// emptied in this edit goes, and only while it holds nothing but its
    /// text; `removingEmpty`, as Backspace in an empty line asks, also takes
    /// one that was empty already, and what's under it stays.
    func commitLine(undoTarget: NSTextStorage? = nil, removingEmpty: Bool = false) {
        guard let edit = line else { return }
        line = nil
        defer { drawnRows = nil }
        for storage in [undoTarget, textStorage(editing: edit.blockID)].compactMap({ $0 }) { edit.undoTargets.add(storage) }
        let targets = edit.undoTargets.allObjects
        guard let block = env.store.block(id: edit.blockID) else {
            targets.forEach(discardTyping)
            return
        }
        // Empty as typed: a title of only a label or a date keeps its line.
        let typed = block.text
        env.store.writeInEditorSession(edit.session, to: block) { commitInlineMetadata(block) }
        var change: OutlineEdit = edit.isNew ? .added(block.id) : .edited(block.id)
        if !block.kind.isVoid, Self.isBlank(typed), removes(block, in: edit, explicitly: removingEmpty) {
            env.store.recordInEditorSession(edit.session) { removeLine(block) }
            env.store.save()
            if focus.blockID == edit.blockID { focus.request(nil) }
            change = .removedEmptyLine(edit.blockID)
        }
        targets.forEach(discardTyping)
        let name = hooks.nameEdit(change) ?? change.defaultName
        if env.store.commitEditorSession(edit.session, name: name, undoManager: undoManager) {
            hooks.didRecordEdit(change, name)
        }
    }

    /// Whether an empty line goes as its edit ends. A new one always does.
    /// Any other holds nothing but its text: no note, date, reminder, repeat,
    /// label, file, calendar placement or work, some of which no Undo could
    /// bring back. Left by the caret, it also has no lines under it and was
    /// emptied in this edit.
    private func removes(_ block: Block, in edit: LineEdit, explicitly: Bool) -> Bool {
        if edit.isNew { return true }
        guard explicitly || !edit.arrivedEmpty else { return false }
        guard block.note.isEmpty, block.dueDate == nil, block.reminderAt == nil, block.recurrence == nil,
              block.labelIDs.isEmpty, block.mediaFilename == nil,
              env.store.attachments(for: block.id).isEmpty,
              env.store.placements(taskID: block.id).isEmpty,
              env.store.workSessions(taskID: block.id).isEmpty else { return false }
        guard !explicitly, let listID = block.listID else { return true }
        return env.store.children(of: block.id, listID: listID).isEmpty
    }

    /// Takes a line out of the document. What was nested under it stays
    /// where it shows, as in the design's flat document: under the line
    /// above, when that line can hold it and shows its lines, or else a
    /// level up, in the line's place.
    private func removeLine(_ block: Block) {
        let siblings = env.store.orderedSiblings(of: block)
        if let index = siblings.firstIndex(where: { $0.id == block.id }), index > 0, let listID = block.listID {
            // A done task the document lists apart, or one folded, would hide them.
            let above = siblings[index - 1]
            if OutlinePolicy.nests(above.kind), !above.isCollapsed, rows.contains(where: { $0.id == above.id }) {
                for child in env.store.children(of: block.id, listID: listID) {
                    env.store.move(child, toParent: above.id, above: nil, in: listID)
                }
            }
        }
        env.store.deleteBlock(block, liftChildren: true)
    }

    /// Before Undo while a line holds the caret. The line's typing undoes
    /// natively, but once its edit has changed more than text, Undo takes
    /// the whole edit back: the edit is committed first.
    func prepareForUndo() {
        guard let edit = line else { return }
        let text = env.store.block(id: edit.blockID)?.text ?? ""
        if edit.isNew ? text.isEmpty : edit.isStructural { commitLine() }
    }

    /// The typing a line edit folds into its own step leaves the stack.
    private func discardTyping(_ storage: NSTextStorage) {
        let view = storage.layoutManagers.first?.firstTextView
        view?.breakUndoCoalescing()
        (view?.undoManager ?? undoManager)?.removeAllActions(withTarget: storage)
    }

    /// The storage of the text view editing `id`, while it has the keyboard.
    private func textStorage(editing id: UUID) -> NSTextStorage? {
        guard let view = NSApp?.keyWindow?.firstResponder as? BlockNSTextView,
              view.coordinator?.parent.blockID == id else { return nil }
        return view.textStorage
    }

    /// An Undo or Redo while a line is open has recorded its own change. The
    /// line's edit restarts from what it left, unless it only took back the
    /// line's own typing.
    private func observeUndo() {
        guard undoObservers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.NSUndoManagerWillUndoChange, .NSUndoManagerWillRedoChange] {
            undoObservers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
                let sender = (note.object as? UndoManager).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, sender == self.undoManager.map(ObjectIdentifier.init) else { return }
                    self.isUndoing = true
                    self.undoTypedInLine = false
                }
            })
        }
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            undoObservers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
                let sender = (note.object as? UndoManager).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, self.isUndoing, sender == self.undoManager.map(ObjectIdentifier.init) else { return }
                    self.isUndoing = false
                    guard let edit = self.line, !self.undoTypedInLine else { return }
                    self.env.store.rebaseEditorSession(edit.session)
                    edit.isNew = false
                }
            })
        }
    }

    // MARK: - Inline metadata

    /// Commits anything the user typed inline — a date phrase, a `#label` —
    /// once the line is finished.
    ///
    /// The rule itself lives in `Store`; what belongs here is only the timing.
    private func commitInlineMetadata(_ block: Block) {
        guard block.modelContext != nil, !block.isDeleted else { return }
        guard inlineMetadataEdits.consume(for: block) else { return }
        writeInLine(block) {
            env.store.applyInlineMetadata(
                to: block,
                parsesNaturalLanguage: env.settings.parsesNaturalLanguageDates
            )
        }
    }

    // MARK: - Structure changes

    /// The design's docAdd: a task line at the end of the document, which
    /// takes the caret.
    func appendTask() {
        addLine(covering: []) { env.store.appendBlock(kind: .task, to: document) }
    }

    func dropText(_ text: String, after block: Block) {
        editorEdit("Drop text") { insertPastedText(text, after: block) }
    }

    /// Runs a structural change as one undo step. The change joins the edit
    /// of the line holding the caret, when one does and `joiningLine`, and
    /// otherwise is named for `edit` and reported to the host.
    @discardableResult
    private func editorEdit<T>(_ name: String, edit: OutlineEdit? = nil, joiningLine: Bool = true, _ body: () -> T) -> T {
        defer { drawnRows = nil }
        if joiningLine, let line = openLine(for: focus.blockID) {
            line.isStructural = true
            return env.store.recordInEditorSession(line.session, body)
        }
        let name = edit.flatMap(hooks.nameEdit) ?? name
        let didRegister = edit.map { edit in { [self] in hooks.didRecordEdit(edit, name) } }
        return env.store.undoableEditorEdit(in: document.listID, name: name, undoManager: undoManager,
                                            didRegister: didRegister, body)
    }

    private var undoManager: UndoManager? { NSApp?.keyWindow?.undoManager }

    func move(_ draggedIDs: [UUID], relativeTo target: BlockRow, position: DropPosition) {
        guard sorting == .manual else { return }
        guard target.block.modelContext != nil, !target.block.isDeleted, !target.block.isTrashed,
              target.block.listID == document.listID,
              env.store.block(id: target.id) != nil,
              env.store.list(id: document.listID) != nil else {
            env.store.refuse("The drop target is no longer available. No rows were changed.")
            return
        }
        defer { drawnRows = nil }
        // The move is a step of its own, after the line being written.
        commitLine()
        guard let position = dropPosition(for: draggedIDs, relativeTo: target.block, position: position) else {
            env.store.refuse("Only tasks and list items go under another line, two levels deep at most.")
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
        let shape = outlineShape()
        do {
            let moved = try env.store.moveSelection(draggedIDs, to: document.listID,
                parentID: parentID, above: aboveID, expandsParent: position == .inside,
                undoManager: NSApp?.keyWindow?.undoManager)
            // Named and logged, when anything moved.
            guard !moved.isEmpty, outlineShape() != shape else { return }
            let edit = OutlineEdit.dragged(moved)
            let name = hooks.nameEdit(edit) ?? edit.defaultName
            undoManager?.setActionName(name)
            hooks.didRecordEdit(edit, name)
        } catch { env.store.editorNotice = error.localizedDescription }
    }

    /// Where a drag lands under the design's rules: only tasks and list
    /// items go under a line, and only under a task or list item, two levels
    /// deep at most. A drop into a line that can't hold it lands after it;
    /// `nil` when the lines can't go beside it either.
    private func dropPosition(for ids: [UUID], relativeTo target: Block, position: DropPosition) -> DropPosition? {
        let current = blocks
        let index = BlockTree.childIndex(of: current)
        let dragged = topmost(ids.compactMap { id in current.first { $0.id == id } })
        guard !dragged.isEmpty else { return nil }
        func height(_ block: Block) -> Int {
            (index[block.id] ?? []).map { 1 + height($0) }.max() ?? 0
        }
        func fit(at depth: Int) -> Bool {
            dragged.allSatisfy { (depth == 0 || OutlinePolicy.nests($0.kind)) && depth + height($0) <= OutlinePolicy.maximumDepth }
        }
        let depth = BlockTree.ancestors(of: target, in: current).count
        if position == .inside, OutlinePolicy.nests(target.kind), fit(at: depth + 1) { return .inside }
        return fit(at: depth) ? (position == .inside ? .after : position) : nil
    }

    /// Every line's place in the outline, to tell whether a move changed any.
    private func outlineShape() -> [String] {
        BlockTree.flatten(blocks, root: document.rootBlockID, respectCollapse: false).map { "\($0.id)/\($0.depth)" }
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
        defer { drawnRows = nil }
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
        defer { drawnRows = nil }
        let structural: [EditorCommand] = [.indent, .outdent, .moveUp, .moveDown]
        if let command = env.pendingCommand, structural.contains(command) {
            editorEdit("Edit outline", edit: outlineEdit(for: command, on: commandTargets.map(\.id))) { handleCommand() }
        } else {
            // A task command comes after the line being written, as it would
            // after a click away from it, so neither step takes in the other.
            if env.pendingCommand != nil { commitLine() }
            handleCommand()
        }
    }

    private func outlineEdit(for command: EditorCommand, on ids: [UUID]) -> OutlineEdit? {
        guard let first = ids.first else { return nil }
        switch command {
        case .indent: return .indented(ids)
        case .outdent: return .outdented(ids)
        case .moveUp: return .moved(first, up: true)
        case .moveDown: return .moved(first, up: false)
        default: return nil
        }
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
        return hooks.commandTargets().compactMap { env.store.block(id: $0) }.filter { $0.listID == document.listID }
    }

    /// The tasks a menu command sent now would reach, so the Task menu's
    /// titles, enabled state and Workbench items read the same targets.
    var commandTaskIDs: [UUID] { commandTargets.filter(\.isTask).map(\.id) }

    private func handleCommand() {
        guard let command = env.consumeCommand() else { return }
        let targets = commandTargets
        guard !SelectionCommandPolicy.reject(command, selectedCount: env.navigator.selection.count, store: env.store) else { return }
        if sorting != .manual, [.moveUp, .moveDown, .indent, .outdent].contains(command) {
            env.store.refuse("Switch to manual order before rearranging rows.")
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
            env.store.batch { for block in topmost(targets) { _ = indentLine(block) } }

        case .outdent:
            env.store.batch { for block in topmost(targets).reversed() { _ = outdentLine(block) } }

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

        case .expandAll, .collapseAll:
            let all = allRows(in: blocks)
            // Headings fold their sections too.
            let sections = BlockTree.sections(in: all)
            env.store.batch {
                for row in all where row.hasChildren || sections[row.id]?.isEmpty == false {
                    env.store.setCollapsed(command == .collapseAll, for: row.block)
                }
            }

        default:
            break
        }
    }

    // MARK: - Resuming after Escape

    /// The block Escape left, until a row takes the caret again or the
    /// host's keys move on.
    @ObservationIgnored private(set) var escapedBlockID: UUID?

    /// Forgets the block Escape left, once the host's keys have moved on.
    func forgetEscape() {
        escapedBlockID = nil
    }

    /// Puts the caret back in the block Escape left, wherever the text view
    /// last had it. `false` when that block has gone or is hidden.
    @discardableResult
    func resumeEditing() -> Bool {
        guard let id = escapedBlockID else { return false }
        escapedBlockID = nil
        guard rows.contains(where: { $0.id == id && !$0.block.kind.isVoid }) else { return false }
        env.activeDocument = document
        focus.request(id)
        return true
    }

    // MARK: - Lifecycle

    /// A list's document claims menu commands on appear; one rooted at a
    /// task waits until the user edits inside it.
    func didAppear() {
        if document.rootBlockID == nil { env.activeDocument = document }
    }

    func didDisappear() {
        commitLine()
        escapedBlockID = nil
        if env.navigator.rowSelection.scopeID == selectionScopeID { env.navigator.clearSelection() }
    }

    func documentDidChange() {
        commitLine()
        inlineMetadataEdits = InlineMetadataEdits()
        focus = EditorFocus()
        slash = nil
        completedTasksKeptVisible = []
        escapedBlockID = nil
        drawnRows = nil
        if document.rootBlockID == nil { env.activeDocument = document }
    }

    func activeDocumentDidChange(_ active: DocumentContext?) {
        if active != document { slash = nil }
    }

    func openTaskDidChange(_ openTaskID: UUID?) {
        // Closing the inspector hands control back to the list.
        if openTaskID == nil, document.rootBlockID == nil {
            env.activeDocument = document
        }
    }

    /// The rows on show changed from `old` to `ids`.
    func visibleRowsDidChange(_ ids: [UUID], from old: [UUID] = []) {
        env.navigator.reconcileSelection(scope: selectionScopeID, visible: ids)
        // A line that stops showing while it holds the caret, folded away or
        // settled into Completed, is left, as a click away leaves it. Nothing
        // could take the caret there. A line just added, not drawn yet,
        // keeps it.
        guard let id = focus.blockID, old.contains(id), !ids.contains(id) else { return }
        if line?.blockID == id { commitLine() }
        focus.request(nil)
    }

    /// Forgets drafts of removed blocks, and moves a caret whose block went away.
    func blocksDidChange(_ ids: [UUID]) {
        inlineMetadataEdits.retain(blockIDs: Set(ids))
        // Undo or Trash took the line being edited: nothing is left to commit.
        if let edit = line, !ids.contains(edit.blockID) {
            line = nil
            edit.undoTargets.allObjects.forEach(discardTyping)
        }
        if let focused = focus.blockID, !ids.contains(focused) {
            // The caret goes; the host keeps the focus.
            focus.request(nil)
        }
    }

    /// Lifecycle persistence is about to save: finish every row's draft first.
    func commitPendingInlineMetadata() {
        // Every open document hears this, and most have nothing typed.
        guard !inlineMetadataEdits.isEmpty else { return }
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

/// The part of an outline's lifecycle its renderer attaches: menu commands,
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
            .onChange(of: visibleIDs, initial: true) { old, ids in editor.visibleRowsDidChange(ids, from: old) }
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
