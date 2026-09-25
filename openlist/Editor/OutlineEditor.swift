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
    /// The span the "/" and its query occupy, the whole line as the design's,
    /// so choosing a kind removes exactly what was typed.
    var range: NSRange
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
    var onSlashQuery: (String?, NSRange, CGRect) -> Void = { _, _, _ in }
    var onMarkdownPrefix: (BlockKind) -> Void = { _ in }
    var onPasteMultiline: (String) -> Bool = { _ in false }
    var onPasteFragment: () -> Bool = { false }
    var onPasteLines: ([MarkdownInputRules.ParsedLine]) -> Bool = { _ in false }
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
            onPasteLines: onPasteLines,
            onEndEditing: onEndEditing,
            onLineBreak: onLineBreak
        )
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
    /// Lines moved up or down, the rows selected together as one.
    case moved([UUID], up: Bool)
    /// Lines dragged to another place.
    case dragged([UUID])
    /// Lines pasted, or dropped in from another app, as a step of their
    /// own: the ones at the paste's top level.
    case pasted([UUID])
    /// An image line's caption written, changed or cleared.
    case captioned(UUID)

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
        case .pasted: "Paste"
        case .captioned: "Edit caption"
        }
    }
}

/// One `/` menu entry: the design's five kinds, then the editor's other
/// kinds, which only a query for them brings up.
struct OutlineSlashOption: Identifiable, Equatable {
    let kind: BlockKind
    let label: String
    let symbol: String
    /// The prefix that makes the same kind as it's typed, as the design's
    /// card shows it. Only the design's five have one: no typed prefix
    /// makes the other kinds.
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
        OutlineSlashOption(kind: .heading3, label: "Heading 3", symbol: "textformat.size.smaller", hint: "", isExtra: true),
        OutlineSlashOption(kind: .numbered, label: "Numbered", symbol: "list.number", hint: "", isExtra: true),
        OutlineSlashOption(kind: .quote, label: "Quote", symbol: "text.quote", hint: "", isExtra: true),
        OutlineSlashOption(kind: .code, label: "Code", symbol: "chevron.left.forwardslash.chevron.right", hint: "", isExtra: true),
        OutlineSlashOption(kind: .divider, label: "Divider", symbol: "minus", hint: "", isExtra: true),
        OutlineSlashOption(kind: .image, label: "Image", symbol: "photo", hint: "", isExtra: true),
    ]

    /// With no query, the design's five, and for one letter just what the
    /// design's filter by label brings up. From the second letter the
    /// editor's own search words find a kind too, so "h1" and "todo" still
    /// work, and the other kinds come up for their name or search words as
    /// typed from the start. As the design's, the query is the whole line
    /// after its "/", spaces and all, so "task " matches nothing.
    static func matching(_ query: String) -> [OutlineSlashOption] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return all.filter { !$0.isExtra } }
        let words = needle.count > 1
        return all.filter { option in
            let label = option.label.lowercased()
            if words, option.kind.searchTerms.contains(where: { $0.hasPrefix(needle) }) { return true }
            return option.isExtra ? words && label.hasPrefix(needle) : label.contains(needle)
        }
    }
}

/// Host policy an outline defers to. Each default leaves the outline to act,
/// or does nothing, so a host sets only what it does itself.
struct OutlineHooks {
    /// A block took the caret. It can fire more than once for one click.
    var didFocus: (UUID) -> Void = { _ in }
    /// Escape left a block. The text view has already resigned first
    /// responder and the outline has let go of the caret, which the host's
    /// keys can put back with ``OutlineEditor/resumeEditing()``.
    var didEscape: (UUID) -> Void = { _ in }
    /// Offered each menu command and its targets before the outline's own.
    /// Return `true` to claim it. Task commands, which the outline doesn't
    /// run, are the host's: one it declines does nothing.
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
    /// A line's edit ended, recorded or not, as a new line left empty isn't,
    /// and its blocks' saved history has just taken the line's one entry, or
    /// none: the blocks it touched, for a host that tells that history apart
    /// from changes made elsewhere.
    var didEndLine: (_ ids: Set<UUID>) -> Void = { _ in }
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
/// kept-visible tasks if a document changes in place.
@MainActor
@Observable
final class OutlineEditor {
    let env: AppEnvironment
    @ObservationIgnored var hooks: OutlineHooks
    /// The document being edited: a whole list, with no root task.
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
              request.taskID == nil, request.listID == document.listID else { return nil }
        return request
    }

    /// The reveal to act on, once search has stepped aside.
    var readyRevealID: UUID? { env.navigator.isSearchOpen ? nil : reveal?.id }

    /// Every row of `live` in display order, done tasks included, showing
    /// what `expanding` folds away too. Done subtasks stay where they were
    /// ticked, as in the design.
    private func projectedRows(of live: [Block], expanding: Set<UUID> = []) -> [BlockRow] {
        BlockTree.sortingTaskRuns(in: BlockTree.flatten(live,
            expanding: expanding.union(reveal?.ancestorIDs ?? [])), by: sorting)
    }

    /// The rows to draw: every row without the done top-level tasks,
    /// which the host lists apart, unless a task under one is still open, and
    /// without the sections of collapsed headings. Done subtasks stay in place.
    func visibleRows(in blocks: [Block]) -> [BlockRow] {
        let live = blocks.filter { $0.modelContext != nil && !$0.isDeleted }
        let kept = (reveal?.visiblePath ?? []).union(completedTasksKeptVisible)
        // Only tasks fold what's under them: what a heading, list item or
        // text line has folded still shows. A heading folds its section
        // instead, further down.
        let unfolding = Set(live.lazy.filter { !OutlinePolicy.folds($0.kind) && $0.isCollapsed }.map(\.id))
        if tasksOnly {
            // A heading folds nothing here either: its section shows, as
            // tasks under the tasks above. Done tasks go by their depth
            // among the tasks, so one a heading, list item or text line
            // holds with no task above it leaves, as a top-level task.
            let rows = Self.taskOutline(projectedRows(of: live, expanding: unfolding))
            return BlockTree.hidingCompletedTasks(in: rows, revealing: kept
                .union(BlockTree.completedTasksHoldingOpenTasks(in: live, atTaskLevel: true)))
        }
        let rows = projectedRows(of: live, expanding: unfolding)
        // A revealed line shows through the headings folding it away.
        let unfolded = reveal?.blockID.map { Set(BlockTree.enclosingSections(of: $0, in: rows)) } ?? []
        return BlockTree.hidingCompletedTasks(in: BlockTree.hidingCollapsedSections(in: rows, revealing: unfolded),
                                              revealing: kept.union(BlockTree.completedTasksHoldingOpenTasks(in: live)))
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
            // With nothing matching, the design's Return does nothing: the
            // card stays up under its header, and the line keeps its "/".
            guard results.indices.contains(state.selectedIndex) else { return }
            applySlashSelection(results[state.selectedIndex])
        case .dismiss:
            slash = nil
        }
    }

    func applySlashSelection(_ kind: BlockKind) {
        editorEdit("Change line type") { applySlashSelectionContents(kind) }
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

        // Remove exactly the "/query" that summoned the menu, which the
        // design's pick clears the line of, and only while the line holds it.
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
            env.store.actionError = "“\(url.lastPathComponent)” could not be added as an image. \(error.localizedDescription)"
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
                if holdsEdit(blockID) { commitLine(leaving: true) }
                slash = nil
                focus.request(nil)
                env.navigator.clearSelection()
                escapedBlockID = blockID
                hooks.didEscape(blockID)
            },
            onSlashQuery: { [self] query, range, viewport in
                guard let query else {
                    if slash?.blockID == blockID { slash = nil }
                    return
                }
                // Showing only tasks, a line turns into no other kind, which
                // it wouldn't draw.
                guard block.modelContext != nil, !block.isDeleted, !tasksOnly else { return }
                if var existing = slash, existing.blockID == blockID {
                    // Reset the highlight whenever the filter changes, so the
                    // top result is always the one Return picks.
                    if existing.query != query {
                        existing.query = query
                        existing.selectedIndex = 0
                    }
                    existing.range = range
                    existing.viewport = viewport
                    slash = existing
                } else {
                    slash = SlashState(blockID: blockID, query: query, range: range, viewport: viewport)
                }
            },
            onMarkdownPrefix: { [self] kind in
                editorEdit("Change line type") { applyMarkdownPrefix(kind, to: block) }
            },
            onPasteMultiline: { [self] text in
                paste(MarkdownInputRules.pasteLines(text), in: block)
            },
            onPasteFragment: { [self] in
                // What was written in a line with text is a step of its own,
                // under the paste. An empty line stays open: a new one goes
                // as the caret moves on to what was pasted.
                if let current = env.store.block(id: blockID), !Self.isBlank(current.text) { commitLine() }
                editorEditFragment(after: blockID)
                leaveEmptyLine(blockID)
                return true
            },
            onPasteLines: { [self] lines in
                paste(lines, in: block)
            },
            onEndEditing: { [self] storage in
                // The text view a kind change replaced, not the line being left.
                guard redrawnLineID != blockID else { return }
                if holdsEdit(blockID) { commitLine(undoTarget: storage, leaving: true) }
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
                commitLine(leaving: true)
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

    // MARK: - Key handling

    /// The list is the document's floor: a line at its top level can't step
    /// out of it.
    private func canOutdent(_ block: Block) -> Bool {
        block.parentID != nil
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

        commitLine(leaving: true)
        // The design's startEdit puts the caret at the end of the line either way.
        focus.request(target.id, caret: -1)
        return true
    }

    private func applyMarkdownPrefix(_ kind: BlockKind, to block: Block) {
        // `> ` makes text, as it does in the design.
        let kind = kind == .quote ? .paragraph : kind
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
    /// level where it stands, as the design's convert sets only the line's
    /// own depth to 0. The lines under it keep their place under it, as the
    /// design's keep their depth: they still draw a level in, and turned back
    /// into a task or list item, the line holds them again. A line turning
    /// into a task or from one opens, as the design's convert makes it anew,
    /// and so does one turning into a heading or from one: a heading folds
    /// its section, and a fold an older list left on a list item, which draws
    /// no caret, mustn't hide the new heading's.
    private func convert(_ block: Block, to kind: BlockKind) {
        let isHeading = { (kind: BlockKind) in BlockTree.sectionLevel(of: kind) != nil }
        if OutlinePolicy.folds(block.kind) != OutlinePolicy.folds(kind) || isHeading(block.kind) != isHeading(kind) {
            block.isCollapsed = false
        }
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
        drawnRows = nil
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
    /// whose subtree shows takes it as its first child. What shows is what's
    /// drawn: showing only tasks, a task with only list items or text under
    /// it takes the new task beside it.
    private func handleReturn(block: Block, content: NSAttributedString) -> Bool {
        if content.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let changed = editorEdit("Edit line") { () -> Bool in
                if depth(of: block) > 0, canOutdent(block) { return outdentLine(block) }
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

        let current = rows
        let index = current.firstIndex { $0.id == block.id }
        let showsSubtree = index.map { $0 + 1 < current.count && current[$0 + 1].depth > current[$0].depth } ?? false
        commitLine(leaving: true)
        guard block.modelContext != nil, !block.isDeleted else { return true }
        addLine(covering: [block.id]) { line(after: block, showingSubtree: showsSubtree) }
        return true
    }

    private func line(after block: Block, showingSubtree: Bool) -> Block {
        let kind: BlockKind = switch block.kind {
        case .heading1, .heading2, .heading3: .task
        case .quote, .divider, .image: .paragraph
        default: block.kind
        }
        return block.isTask && showingSubtree
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
    /// Headings and text stay at the top. One holding the lines it kept as
    /// it was turned takes the line in after them, as the design's indent
    /// goes by the line right above.
    ///
    /// The two levels are the document's, the lines under the line counted,
    /// as a drag, paste or Add subtask counts them: a line whose subtree
    /// would go past them stays, and so does one the Tasks presentation
    /// draws shallower than it is, under a list item or text line.
    private func indentLine(_ block: Block) -> Bool {
        guard OutlinePolicy.nests(block.kind) else { return false }
        let current = rows
        guard let index = current.firstIndex(where: { $0.id == block.id }), index > 0 else { return false }
        let depth = current[index].depth
        let previous = current[index - 1]
        guard OutlinePolicy.nests(previous.block.kind), previous.depth >= depth,
              let parent = current[..<index].last(where: { $0.depth <= depth }), parent.depth == depth,
              parent.block.parentID == block.parentID,
              OutlinePolicy.nests(parent.block.kind) || previous.depth > depth,
              fitsOneLevelDeeper(block),
              env.store.move(block, toParent: parent.id, above: nil, in: document.listID)
        else { return false }
        // A heading's fold is its section's, which holds the line either way.
        if BlockTree.sectionLevel(of: parent.block.kind) == nil { parent.block.isCollapsed = false }
        drawnRows = nil
        return true
    }

    /// Whether `block` and every line under it stay within two levels in
    /// the document one level deeper than it is now.
    private func fitsOneLevelDeeper(_ block: Block) -> Bool {
        let current = blocks
        let depth = BlockTree.ancestors(of: block, in: current).count
        return depth + 1 + Self.height(of: block, in: BlockTree.childIndex(of: current)) <= OutlinePolicy.maximumDepth
    }

    /// How many levels of lines sit under `block`, folded or done ones too.
    private static func height(of block: Block, in index: [UUID?: [Block]]) -> Int {
        (index[block.id] ?? []).map { 1 + height(of: $0, in: index) }.max() ?? 0
    }

    /// Steps a line out a level. Showing only tasks, a level as the tasks
    /// draw it: the line steps out past the headings, list items and text
    /// lines holding it too, to beside the task it was under, so the step
    /// always shows. One no task holds is at the Tasks presentation's top
    /// level already, and stays.
    private func outdentLine(_ block: Block) -> Bool {
        guard canOutdent(block) else { return false }
        guard tasksOnly else {
            guard env.store.outdent(block) else { return false }
            drawnRows = nil
            return true
        }
        let current = blocks
        func taskDepth() -> Int { BlockTree.ancestors(of: block, in: current).filter(\.isTask).count }
        let depth = taskDepth()
        guard depth > 0 else { return false }
        while taskDepth() == depth, env.store.outdent(block) {}
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
        editorEdit("Change line type", edit: .edited(id), joiningLine: false) {
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

    /// Writes an image line's caption, the text its Markdown and copies give
    /// the image, in a step of its own. Kept to one line and trimmed, as a
    /// line's text is committed; an empty one clears it. Writing it began by
    /// leaving any line being written, so a line open now was opened since,
    /// as by the add row's click the caption commits on, and stays open,
    /// its typing yet to come over this step.
    func setCaption(_ id: UUID, to caption: String) {
        let caption = caption.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard let block = env.store.block(id: id), block.listID == document.listID,
              block.kind == .image, block.mediaCaption != caption else { return }
        editorEdit("Edit caption", edit: .captioned(id), joiningLine: false) {
            block.mediaCaption = caption
            block.touch()
            env.store.save()
        }
        line?.stepBelow = undoStepName
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

    /// Opens the tasks and headings that fold `id` away, and
    /// keeps the done top-level task it sits under on show.
    func unfold(toShow id: UUID) {
        let current = blocks
        guard let block = current.first(where: { $0.id == id }) else { return }
        let ancestors = BlockTree.ancestors(of: block, in: current)
        let rows = BlockTree.flatten(current, respectCollapse: false)
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

    /// The name of the step the line being written commits as, which an
    /// Undo that finishes the line first takes back, as `commitLine` would
    /// name it. nil with none open, or when finishing it registers nothing,
    /// as a new line left empty or one the caret only arrived at does, so
    /// Undo names the step it will take back instead.
    var lineStepName: String? {
        guard let edit = line, let block = env.store.block(id: edit.blockID) else { return nil }
        var change: OutlineEdit = edit.isNew ? .added(block.id) : .edited(block.id)
        if !block.kind.isVoid, Self.isBlank(block.text), removes(block, in: edit, explicitly: false) {
            // A new line goes with it, and leaves only what else its edit changed.
            guard !edit.isNew || env.store.editorSessionHasChanges(edit.session, excluding: [block.id]) else { return nil }
            change = .removedEmptyLine(block.id)
        } else if !env.store.editorSessionHasChanges(edit.session) {
            return nil
        }
        return hooks.nameEdit(change) ?? change.defaultName
    }

    /// Whether a line is being written, whose typing the stack holds on top.
    var isWritingLine: Bool { line != nil }

    /// The step the stack held under the line being written as the caret
    /// arrived, which Undo takes back when finishing the line registers none.
    var stepUnderLine: String? { line?.stepBelow }

    // MARK: - Line edits

    /// The edit of one line, from the caret arriving to it leaving, undone
    /// as one step.
    private final class LineEdit {
        let blockID: UUID
        /// The name of the stack's top step as the caret arrived, under the
        /// line's typing, if there was one.
        var stepBelow: String?
        /// Added by this edit, so taking it out again leaves nothing to undo.
        var isNew: Bool
        /// Changed more than the line's text.
        var isStructural: Bool
        /// Its text when the caret arrived.
        let arrivedText: String
        /// Its text before the caret wrote in it: what it arrived with, or
        /// what it had before a commit the caret stayed through.
        let unwrittenText: String
        /// Its text was already empty when the caret arrived, as an untitled
        /// task or a spacer in an older list is, so passing through leaves it.
        var arrivedEmpty: Bool { OutlineEditor.isBlank(arrivedText) }
        let session: EditorEditSession
        /// Where the line's typing Undo is registered, folded into this step.
        /// A line whose kind changes can be drawn by a new text view. Held
        /// until the step ends, by identity: the undo manager doesn't keep
        /// them, and a text view gone with its storage would leave its typing.
        let undoTargets = NSHashTable<NSTextStorage>(options: [.strongMemory, .objectPointerPersonality])

        init(blockID: UUID, isNew: Bool, arrivedText: String, unwrittenText: String? = nil, session: EditorEditSession) {
            self.blockID = blockID
            self.isNew = isNew
            isStructural = isNew
            self.arrivedText = arrivedText
            self.unwrittenText = unwrittenText ?? arrivedText
            self.session = session
        }
    }

    @ObservationIgnored private var line: LineEdit?
    /// A line written and committed while the caret stayed in it, as for a
    /// Task menu command, with its text before it was written. It's trimmed
    /// once the caret leaves, as ``commitLine(undoTarget:removingEmpty:leaving:)``
    /// trims a line left.
    @ObservationIgnored private var untrimmed: (blockID: UUID, unwrittenText: String)?
    @ObservationIgnored private var undoObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var isUndoing = false
    @ObservationIgnored private var undoTypedInLine = false

    /// The edit of `id`, finishing any other line's first.
    @discardableResult
    private func openLine(for id: UUID?) -> LineEdit? {
        guard let id else { return nil }
        if let line, line.blockID == id { return line }
        // Written before a commit the caret stayed through, the line takes
        // its trim into this edit.
        let written = untrimmed?.blockID == id ? untrimmed?.unwrittenText : nil
        if written != nil { untrimmed = nil }
        commitLine(leaving: true)
        guard let block = env.store.block(id: id) else { return nil }
        let edit = LineEdit(blockID: id, isNew: false, arrivedText: block.text, unwrittenText: written,
                            session: env.store.beginEditorSession(in: document.listID, covering: [id]))
        line = edit
        observeUndo()
        edit.stepBelow = undoStepName
        return edit
    }

    /// Adds a line in an edit of its own, which ends as "Added" or, left
    /// empty, leaves nothing to undo. A heading or task folding the new line
    /// away opens, so the caret has a line to land in.
    private func addLine(covering ids: Set<UUID>, _ create: () -> Block) {
        commitLine(leaving: true)
        let session = env.store.beginEditorSession(in: document.listID, covering: ids)
        let created = env.store.recordInEditorSession(session, create)
        env.store.save()
        line = LineEdit(blockID: created.id, isNew: true, arrivedText: "", session: session)
        observeUndo()
        line?.stepBelow = undoStepName
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

    /// Whether `id` is the line being written, or one written that a commit
    /// the caret stayed through left to trim.
    private func holdsEdit(_ id: UUID) -> Bool {
        line?.blockID == id || untrimmed?.blockID == id
    }

    /// Whether the caret is still in `id`'s text view: first responder in
    /// its window, the key one or one a panel or popover has come over.
    private func caretStays(in id: UUID) -> Bool {
        firstResponders().contains { ($0 as? BlockNSTextView)?.coordinator?.parent.blockID == id }
    }

    /// Each window's first responder. Checks, which have no key window,
    /// stand in text views of their own.
    @ObservationIgnored var firstResponders: () -> [NSResponder] = {
        NSApp?.windows.compactMap(\.firstResponder) ?? []
    }

    /// Takes the spaces and line breaks off both ends of a line's text, its
    /// styling kept. Code, one of the editor's own kinds, keeps its indent.
    private func trimEnds(of block: Block) {
        guard block.kind != .code, !block.kind.isVoid else { return }
        let content = env.store.attributedContent(of: block)
        let text = content.string as NSString
        let visible = CharacterSet.whitespacesAndNewlines.inverted
        let first = text.rangeOfCharacter(from: visible)
        let kept = first.location == NSNotFound ? NSRange(location: 0, length: 0)
            : NSRange(location: first.location,
                      length: NSMaxRange(text.rangeOfCharacter(from: visible, options: .backwards)) - first.location)
        guard kept.length != text.length else { return }
        env.store.setContent(block, attributed: content.attributedSubstring(from: kept))
    }

    /// Finishes the line being edited. A line left empty is removed, as the
    /// design's commit does, and whatever changed becomes one undo step,
    /// named for what it was, in place of the line's typing. Only a line
    /// emptied in this edit goes, and only while it holds nothing but its
    /// text; `removingEmpty`, as Backspace in an empty line asks, also takes
    /// one that was empty already, and what's under it stays.
    ///
    /// A line written in this edit keeps its text trimmed at both ends, as
    /// the design's commit stores it, once the caret is `leaving` it or has
    /// left. A caret staying, as for a Task menu command, keeps what's typed
    /// under it until it leaves.
    func commitLine(undoTarget: NSTextStorage? = nil, removingEmpty: Bool = false, leaving: Bool = false) {
        guard let edit = line else {
            trimUntrimmed(leaving: leaving)
            return
        }
        line = nil
        defer {
            drawnRows = nil
            endLine(edit)
        }
        for storage in [undoTarget, textStorage(editing: edit.blockID)].compactMap({ $0 }) { edit.undoTargets.add(storage) }
        let targets = edit.undoTargets.allObjects
        guard let block = env.store.block(id: edit.blockID) else {
            targets.forEach(discardTyping)
            return
        }
        if block.text != edit.unwrittenText {
            if leaving || !caretStays(in: edit.blockID) {
                // Written only before a commit the caret stayed through, the
                // line's writing is in that commit's step.
                if block.text == edit.arrivedText { trimWritten(block) }
                else { env.store.writeInEditorSession(edit.session, to: block) { trimEnds(of: block) } }
            } else {
                // A space taken from under the caret would join the next word typed.
                untrimmed = (block.id, edit.unwrittenText)
            }
        }
        var change: OutlineEdit = edit.isNew ? .added(block.id) : .edited(block.id)
        if !block.kind.isVoid, Self.isBlank(block.text), removes(block, in: edit, explicitly: removingEmpty) {
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

    /// Trims the line a commit the caret stayed through left written, once
    /// the caret is `leaving` it or has left.
    private func trimUntrimmed(leaving: Bool) {
        guard let pending = untrimmed, leaving || !caretStays(in: pending.blockID) else { return }
        untrimmed = nil
        guard let block = env.store.block(id: pending.blockID), block.text != pending.unwrittenText else { return }
        trimWritten(block)
        drawnRows = nil
    }

    /// Trims a line whose writing is in a commit's step already, one the
    /// caret stayed through, now under the step it stayed for. The trim, of
    /// spaces the design never stores, joins no step: Undo still brings back
    /// the text the line had before it was written.
    private func trimWritten(_ block: Block) {
        trimEnds(of: block)
        env.store.scheduleSave(after: .seconds(1))
    }

    /// A line's edit is over, committed or not: what it saved to its tasks
    /// as it was written reaches saved history as its one entry, and the
    /// host hears which blocks it touched.
    private func endLine(_ edit: LineEdit) {
        env.store.endEditorSession(edit.session)
        hooks.didEndLine(edit.session.touchedIDs)
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
            if OutlinePolicy.nests(above.kind), !(OutlinePolicy.folds(above.kind) && above.isCollapsed),
               rows.contains(where: { $0.id == above.id }) {
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
                    edit.stepBelow = self.undoStepName
                }
            })
        }
    }

    // MARK: - Structure changes

    /// The design's docAdd: a task line at the end of the document, which
    /// takes the caret.
    func appendTask() {
        addLine(covering: []) { env.store.appendBlock(kind: .task, to: document) }
    }

    /// Text dragged in from another app and dropped on a line's row, beside
    /// its text: its lines go in before, after or inside the line, as the
    /// drop's indicator shows, under the document's rules, as a step of its
    /// own named for them. Inside, they go under the line as its first lines
    /// where they can nest there, and otherwise after it, as a line dragged
    /// there does. Dropped on the line being written while it's still empty,
    /// they fill it, as a paste there does, in that line's step, or, when it
    /// can't take the first of them, go in beside it as a paste does.
    func dropText(_ text: String, on target: Block, position: DropPosition) {
        guard env.store.block(id: target.id) != nil, target.listID == document.listID else { return }
        let lines = MarkdownInputRules.pasteLines(text)
        guard !lines.isEmpty else { return }
        if line?.blockID == target.id, focus.blockID == target.id, Self.isBlank(target.text), !target.kind.isVoid {
            if fills(target, with: lines) {
                editorEdit("Edit line") { insertPastedLines(lines, at: target) }
            } else {
                // None go under it, as it goes once the caret moves on to them.
                insertBeside(emptyLine: target, lines, position: position == .inside ? .after : position)
            }
            return
        }
        // The drop is a step of its own, after the line being written.
        commitLine()
        guard env.store.block(id: target.id) != nil else { return }
        separateUndoStep()
        pasteEdit { topmost(insertPastedLines(lines, at: target, position: position, filling: false)).map(\.id) }
    }

    /// Lines pasted in `block`, the line being written: after it, or filling
    /// it while it's empty, in its step. An empty line that can't take the
    /// first of them, as one showing only tasks can't take a line that isn't
    /// a task, stays for them to go in after it, as a step of their own.
    /// `false`, pasting nothing, when there are no lines.
    private func paste(_ lines: [MarkdownInputRules.ParsedLine], in block: Block) -> Bool {
        guard !lines.isEmpty else { return false }
        if Self.isBlank(block.text), !block.kind.isVoid, !fills(block, with: lines) {
            insertBeside(emptyLine: block, lines, position: .after)
        } else {
            editorEdit("Paste lines") { insertPastedLines(lines, at: block) }
        }
        return true
    }

    /// Whether pasted `lines` fill `block`, an empty line, rather than going
    /// in beside it. Showing only tasks, only a task does, as the line would
    /// turn into a kind that isn't drawn.
    private func fills(_ block: Block, with lines: [MarkdownInputRules.ParsedLine]) -> Bool {
        Self.isBlank(block.text) && !block.kind.isVoid && (!tasksOnly || lines.first?.kind == .task)
    }

    /// Lines pasted or dropped beside `block`, the empty line being written,
    /// which doesn't take the first of them: a step of their own, named for
    /// them and logged, rather than part of that line's edit, which a new
    /// line left empty ends with nothing to undo.
    private func insertBeside(emptyLine block: Block, _ lines: [MarkdownInputRules.ParsedLine], position: DropPosition) {
        pasteEdit { topmost(insertPastedLines(lines, at: block, position: position, filling: false)).map(\.id) }
        leaveEmptyLine(block.id)
    }

    /// Leaves `id`, the empty line being written, once lines pasted beside it
    /// as a step of their own have taken the caret, as the caret moving on
    /// would: a new one goes with nothing to undo, and a step it does commit
    /// comes after theirs rather than taking them in. With none of them
    /// showing, it keeps the caret.
    private func leaveEmptyLine(_ id: UUID) {
        guard line?.blockID == id, focus.blockID != id else { return }
        if lineStepName != nil { separateUndoStep() }
        commitLine(leaving: true)
    }

    /// Runs a structural change as one undo step. The change joins the edit
    /// of the line holding the caret, when one does and `joiningLine`, and
    /// otherwise is named for `edit` and reported to the host.
    @discardableResult
    private func editorEdit<T>(_ name: String, edit: OutlineEdit? = nil, joiningLine: Bool = true, _ body: () -> T) -> T {
        // Named before it runs, while a line it deletes still has its text.
        let name = edit.flatMap(hooks.nameEdit) ?? name
        return editorEdit(joiningLine: joiningLine, naming: { (edit, name) }, body)
    }

    /// As ``editorEdit(_:edit:joiningLine:_:)``, with the edit and its name
    /// read once `body` has run, so what it did names the step.
    @discardableResult
    private func editorEdit<T>(joiningLine: Bool = true, naming step: @escaping () -> (edit: OutlineEdit?, name: String),
                               _ body: () -> T) -> T {
        defer { drawnRows = nil }
        if joiningLine, let line = openLine(for: focus.blockID) {
            line.isStructural = true
            return env.store.recordInEditorSession(line.session, body)
        }
        return env.store.undoableEditorEdit(in: document.listID, name: step().name, undoManager: undoManager,
                                            didRegister: { [self] in
                                                let step = step()
                                                if let edit = step.edit { hooks.didRecordEdit(edit, step.name) }
                                            }, body)
    }

    private var undoManager: UndoManager? { windowUndoManager() }

    /// The window's undo manager. Checks, which have no key window, stand in
    /// one of their own.
    @ObservationIgnored var windowUndoManager: () -> UndoManager? = { NSApp?.keyWindow?.undoManager }

    /// The pasteboard ⌘V reads Openlist content from. Checks stand in one of
    /// their own, leaving the user's clipboard alone.
    @ObservationIgnored var pasteboard: () -> NSPasteboard = { .general }

    /// Closes the undo group holding what this event has registered so far,
    /// as the line being written just committed, so the change about to be
    /// made is a step of its own. Only right before a change that is sure
    /// to register: a group left empty stays on the stack.
    private func separateUndoStep() {
        guard let undoManager, undoManager.groupingLevel > 0,
              !undoManager.isUndoing, !undoManager.isRedoing else { return }
        undoManager.endUndoGrouping()
        undoManager.beginUndoGrouping()
    }

    /// The name of the step Undo would take back now, if any.
    private var undoStepName: String? {
        guard let undoManager, undoManager.canUndo else { return nil }
        return undoManager.undoActionName.isEmpty ? "Undo" : undoManager.undoActionName
    }

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
        NotificationCenter.default.post(name: .commitPendingEditorDrafts, object: nil)
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
                undoManager: undoManager)
            // Named and logged, when anything moved.
            guard !moved.isEmpty, outlineShape() != shape else { return }
            let edit = OutlineEdit.dragged(moved)
            let name = hooks.nameEdit(edit) ?? edit.defaultName
            undoManager?.setActionName(name)
            hooks.didRecordEdit(edit, name)
        } catch {
            // As for a move from the menu: a refusal that changed nothing
            // passes in the tray, a move that failed to save is the red card.
            if error is BulkActionError { env.store.refuse(error.localizedDescription) }
            else { env.store.actionError = error.localizedDescription }
        }
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
        func fit(at depth: Int) -> Bool {
            dragged.allSatisfy { (depth == 0 || OutlinePolicy.nests($0.kind)) && depth + Self.height(of: $0, in: index) <= OutlinePolicy.maximumDepth }
        }
        let depth = BlockTree.ancestors(of: target, in: current).count
        if position == .inside, OutlinePolicy.nests(target.kind), fit(at: depth + 1) { return .inside }
        return fit(at: depth) ? (position == .inside ? .after : position) : nil
    }

    /// Every line's place in the outline, to tell whether a move changed any.
    private func outlineShape() -> [String] {
        BlockTree.flatten(blocks, respectCollapse: false).map { "\($0.id)/\($0.depth)" }
    }

    /// Pasted lines go in after `block` under the document's rules: `> `
    /// makes text, or right under a pasted task that task's note, as
    /// Openlist content's Markdown writes one; a line goes under the one it
    /// was pasted under only when both are tasks or list items and it stays
    /// two levels deep at most, counting where the paste lands. Otherwise it
    /// goes beside that line, stepping out as far as it must, after the lines
    /// already under it, so the pasted lines keep their order, lines pasted
    /// side by side stay side by side, and the document's lines keep their
    /// places. A drop can put them before `block` instead, the first one
    /// that can't go as deep before the line holding it, or inside it, as
    /// its first lines, opening it. Returns the lines they went in as,
    /// `block` among them when the first one fills it.
    @discardableResult
    private func insertPastedLines(_ pasted: [MarkdownInputRules.ParsedLine], at block: Block,
                                   position: DropPosition = .after, filling: Bool = true) -> [Block] {
        var lines = pasted
        guard !lines.isEmpty else { return [] }
        // The task a `> ` line one level in writes the note of, while it's the last line pasted.
        var noteTask: (block: Block, pasted: Int)?
        // The indent of the line `block` holds: the first line's, when it takes it.
        var blockPasted = 0
        var placed: [Block] = []

        // Pasting into an empty block fills it, rather than leaving a blank
        // line above the pasted content. A kind that doesn't nest takes it to
        // the top level, as typing its prefix does. Showing only tasks, only
        // a task fills it, as a line turns into no kind that isn't drawn.
        if filling, position == .after, fills(block, with: lines) {
            let first = lines.removeFirst()
            convert(block, to: first.kind == .quote ? .paragraph : first.kind)
            env.store.setPlainText(block, first.text)
            block.isCompleted = first.isCompleted
            block.completedAt = first.isCompleted ? .now : nil
            if !first.note.isEmpty { block.note = block.note.isEmpty ? first.note : block.note + "\n" + first.note }
            blockPasted = first.depth
            noteTask = block.isTask ? (block, first.depth) : nil
            placed.append(block)
        }

        // The lines from the document root to the last one placed, with the
        // indent each was pasted at: the paste's own lines at theirs, `block`
        // at the first line's, and the lines above it under every indent, as
        // `block` is for lines dropped inside it. Before it, the first line
        // takes its place.
        let ancestors: [(block: Block, pasted: Int)] = BlockTree.ancestors(of: block, in: blocks).reversed().map { ($0, -1) }
        var path: [(block: Block, pasted: Int)] = switch position {
        case .after: ancestors + [(block, blockPasted)]
        case .inside: ancestors + [(block, -1)]
        case .before: ancestors
        }
        for line in lines {
            if line.kind == .quote, let task = noteTask, line.depth == task.pasted + 1 {
                let note = Self.unescapingMarkdown(line.text)
                task.block.note = task.block.note.isEmpty ? note : task.block.note + "\n" + note
                continue
            }
            let kind = line.kind == .quote ? .paragraph : line.kind
            // Under the lines on the path it was pasted under.
            var depth = min(path.prefix { $0.pasted < line.depth }.count, OutlinePolicy.maximumDepth)
            while depth > 0, !(OutlinePolicy.nests(kind) && OutlinePolicy.nests(path[depth - 1].block.kind)) {
                depth -= 1
            }
            let created: Block
            if position == .before, placed.isEmpty {
                // In the place of `block`, or of the line holding it as deep
                // as this one can go, which stays after the lines dropped there.
                let place = depth < path.count ? path[depth].block : block
                created = env.store.insertBlock(kind: kind, text: line.text, after: place)
                env.store.move(created, toParent: place.parentID, above: place, in: document.listID)
            } else if depth < path.count {
                created = env.store.insertBlock(kind: kind, text: line.text, after: path[depth].block)
            } else {
                let parent = path[depth - 1].block
                let first = position == .inside && parent.id == block.id
                created = env.store.insertChild(kind: kind, text: line.text, of: parent, at: first ? .first : .last)
                // As a line dragged into a folded task opens it, so the
                // caret has the lines to land in.
                if first, block.isCollapsed { env.store.setCollapsed(false, for: block) }
            }
            created.isCompleted = line.isCompleted
            if line.isCompleted { created.completedAt = .now }
            if !line.note.isEmpty { created.note = line.note }
            path = Array(path.prefix(depth)) + [(created, line.depth)]
            noteTask = created.isTask ? (created, line.depth) : nil
            placed.append(created)
        }

        env.store.save()
        // The caret ends the last line put in that shows. A line folded away,
        // settled into Completed or, showing only tasks, not a task, can't
        // take it.
        drawnRows = nil
        let shown = Set(rows.map(\.id))
        if let last = placed.last(where: { shown.contains($0.id) }) { focus.request(last.id, caret: -1) }
        return placed
    }

    /// Markdown's backslash escapes read back, as a note's text is written
    /// escaped in Openlist content's Markdown.
    private static func unescapingMarkdown(_ text: String) -> String {
        var result = ""
        var escaped = false
        for character in text {
            if !escaped, character == "\\" {
                escaped = true
                continue
            }
            if escaped, !(character.isASCII && (character.isPunctuation || character.isSymbol)) {
                result.append("\\")
            }
            escaped = false
            result.append(character)
        }
        if escaped { result.append("\\") }
        return result
    }

    /// ⌘V of Openlist content after `blockID`, as a step of its own.
    private func editorEditFragment(after blockID: UUID) {
        let fragment: DocumentFragment
        do { fragment = try FragmentClipboard.read(from: pasteboard()) } catch {
            env.store.actionError = error.localizedDescription
            return
        }
        separateUndoStep()
        pasteEdit(includingNewLabels: true) {
            do {
                let ids = try env.store.pasteFragment(fragment, inList: document.listID, after: blockID)
                env.navigator.selection = Set(ids)
                // The first line pasted that shows takes the caret, as one
                // settled into Completed or, showing only tasks, one that
                // isn't a task can't.
                drawnRows = nil
                let shown = Set(rows.map(\.id))
                if let first = ids.first(where: shown.contains) { focus.request(first, caret: 0) }
                return ids
            } catch {
                env.store.actionError = error.localizedDescription
                return []
            }
        }
    }

    /// Runs a paste or drop that isn't a line's as one undo step, named for
    /// the lines `body` returns, the ones it put in at its top level, and
    /// reported to the host, as the design's steps are logged.
    private func pasteEdit(includingNewLabels: Bool = false, _ body: () -> [UUID]) {
        defer { drawnRows = nil }
        var roots: [UUID] = []
        func name() -> String {
            let edit = OutlineEdit.pasted(roots)
            return hooks.nameEdit(edit) ?? edit.defaultName
        }
        env.store.undoableEditorEdit(in: document.listID, name: name(), undoManager: undoManager,
                                     includingNewLabels: includingNewLabels,
                                     didRegister: { [self] in hooks.didRecordEdit(.pasted(roots), name()) }) {
            roots = body()
        }
    }

    // MARK: - Menu commands

    /// Runs the pending menu command, if this is the document the user is
    /// working in. Call it whenever `env.commandToken` changes.
    func receiveCommand() {
        // Only the document that claimed menu commands responds. Without a
        // claim, RootView runs them on the workbench's targets instead, so a
        // command never runs twice.
        guard env.activeDocument == document else { return }
        defer { drawnRows = nil }
        let structural: [EditorCommand] = [.indent, .outdent, .moveUp, .moveDown]
        if let command = env.pendingCommand, structural.contains(command) {
            // A move is named for the rows that went, once they have, so
            // one held back isn't in its step or the Changes log.
            var ids = commandTargets.map(\.id)
            editorEdit(naming: { [self] in
                let edit = outlineEdit(for: command, on: ids)
                return (edit, edit.flatMap(hooks.nameEdit) ?? "Edit outline")
            }) {
                if let moved = handleCommand() { ids = moved }
            }
        } else {
            // A task command comes after the line being written, as it would
            // after a click away from it, so neither step takes in the other.
            if env.pendingCommand != nil { commitLine() }
            handleCommand()
        }
    }

    private func outlineEdit(for command: EditorCommand, on ids: [UUID]) -> OutlineEdit? {
        guard !ids.isEmpty else { return nil }
        switch command {
        case .indent: return .indented(ids)
        case .outdent: return .outdented(ids)
        case .moveUp: return .moved(ids, up: true)
        case .moveDown: return .moved(ids, up: false)
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

    /// Runs the pending command; for a move, the targets that went, each
    /// row that did and the ones selected under it.
    @discardableResult
    private func handleCommand() -> [UUID]? {
        guard let command = env.consumeCommand() else { return nil }
        let targets = commandTargets
        guard !SelectionCommandPolicy.reject(command, selectedCount: env.navigator.selection.count, store: env.store) else { return nil }
        if sorting != .manual, [.moveUp, .moveDown, .indent, .outdent].contains(command) {
            env.store.refuse("Switch to manual order before rearranging rows.")
            return nil
        }

        // Task commands are the host's, which runs them through its own
        // action layer; only the cases that need the outline stay here.
        if hooks.taskCommand(command, targets.map(\.id)) {
            if command == .deleteSelection {
                focus.request(nil)
                env.navigator.selection.removeAll()
            }
            return nil
        }

        switch command {
        case .indent:
            env.store.batch { for block in topmost(targets) { _ = indentLine(block) } }

        case .outdent:
            env.store.batch { for block in topmost(targets).reversed() { _ = outdentLine(block) } }

        case .moveUp, .moveDown:
            let moved = Set(moveLines(topmost(targets), up: command == .moveUp))
            let current = blocks
            return targets.filter { target in
                moved.contains(target.id) || BlockTree.ancestors(of: target, in: current).contains { moved.contains($0.id) }
            }.map(\.id)

        case .expandAll, .collapseAll:
            // Every line, the ones folded away too.
            let all = BlockTree.flatten(blocks, respectCollapse: false)
            let sections = BlockTree.sections(in: all)
            env.store.batch {
                for row in all {
                    let hasSection = sections[row.id]?.isEmpty == false
                    if command == .expandAll {
                        if row.hasChildren || hasSection { env.store.setCollapsed(false, for: row.block) }
                    } else if OutlinePolicy.folds(row.block.kind) ? row.hasChildren : hasSection {
                        // Only the lines that draw a caret to open them
                        // again: tasks with lines under them, and headings
                        // with a section.
                        env.store.setCollapsed(true, for: row.block)
                    }
                }
            }

        default:
            break
        }
        return nil
    }

    /// Move Up and Move Down: the line, with what's under it, goes past the
    /// nearest line beside it that shows, itself or a line under it, as the
    /// rows draw them, and past the lines between with nothing drawn: a done
    /// top-level task in Completed, the lines a folded heading holds or,
    /// showing only tasks, a heading, list item or text line with no task
    /// under it. Going down past a folded heading, a heading at the folded
    /// one's level or above lands after its section, which stays folded; any
    /// other folded heading whose section the move puts lines in opens. So
    /// each step moves it on screen, and no line goes into a fold unseen. A
    /// line that doesn't show, or has no such line on that side, stays, and
    /// nothing is recorded.
    ///
    /// Rows selected together move together, as their drag does: each goes
    /// past the nearest line beside it that shows, the nearest to the way
    /// they go first, unless that line is moving too or holds a row that
    /// is, so they keep their order. One that can't go holds back only the
    /// rows that would pass it, and the rest still go, closing up to it.
    /// Returns the rows that went.
    private func moveLines(_ lines: [Block], up: Bool) -> [UUID] {
        let drawn = rows.map(\.id)
        let shown = Set(drawn)
        let order = Dictionary(drawn.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let lines = lines.filter { shown.contains($0.id) }.sorted { order[$0.id, default: 0] < order[$1.id, default: 0] }
        guard !lines.isEmpty else { return [] }
        let moving = Set(lines.map(\.id))
        // A move keeps each line's parent, so this holds as the lines go.
        let index = BlockTree.childIndex(of: blocks)
        func shows(_ sibling: Block) -> Bool {
            shown.contains(sibling.id) || BlockTree.descendants(of: sibling.id, using: index).contains { shown.contains($0.id) }
        }
        func carries(_ sibling: Block) -> Bool {
            moving.contains(sibling.id) || BlockTree.descendants(of: sibling.id, using: index).contains { moving.contains($0.id) }
        }
        let folded = foldedSections()
        var moved: [UUID] = []
        env.store.batch {
            for block in up ? lines : lines.reversed() {
                let siblings = env.store.orderedSiblings(of: block)
                guard let position = siblings.firstIndex(where: { $0.id == block.id }) else { continue }
                if up {
                    guard let past = siblings[..<position].last(where: shows), !carries(past) else { continue }
                    if env.store.move(block, toParent: block.parentID, above: past, in: document.listID) { moved.append(block.id) }
                } else {
                    guard let past = siblings[(position + 1)...].firstIndex(where: shows), !carries(siblings[past]) else { continue }
                    var end = past + 1
                    // A top-level heading ends the section of one at its level or
                    // below, so past a folded one it lands after that section rather
                    // than taking in the lines folded there.
                    if !tasksOnly, block.parentID == nil, let level = BlockTree.sectionLevel(of: block.kind),
                       let passed = BlockTree.sectionLevel(of: siblings[past].kind), level <= passed {
                        let bound = siblings[end...].firstIndex { (BlockTree.sectionLevel(of: $0.kind) ?? .max) <= passed }
                            ?? siblings.endIndex
                        if !siblings[end..<bound].contains(where: shows) { end = bound }
                    }
                    if env.store.move(block, toParent: block.parentID, above: siblings.indices.contains(end) ? siblings[end] : nil,
                                      in: document.listID) { moved.append(block.id) }
                }
            }
            let opening = foldedSections().filter { heading, lines in !lines.isSubset(of: folded[heading] ?? []) }.keys
            for id in opening { if let heading = env.store.block(id: id) { env.store.setCollapsed(false, for: heading) } }
        }
        return moved
    }

    /// The lines each folded top-level heading's section holds, when the
    /// document draws those sections folded: showing only tasks, a heading
    /// folds nothing.
    private func foldedSections() -> [UUID: Set<UUID>] {
        guard !tasksOnly else { return [:] }
        let all = BlockTree.flatten(blocks, respectCollapse: false)
        let folding = Set(all.lazy.filter { $0.depth == 0 && $0.block.isCollapsed }.map(\.id))
        return BlockTree.sections(in: all).filter { folding.contains($0.key) }.mapValues { Set($0.map(\.id)) }
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

    /// The document claims menu commands on appear.
    func didAppear() {
        env.activeDocument = document
    }

    func didDisappear() {
        commitLine(leaving: true)
        escapedBlockID = nil
        if env.navigator.rowSelection.scopeID == selectionScopeID { env.navigator.clearSelection() }
    }

    func documentDidChange() {
        commitLine(leaving: true)
        focus = EditorFocus()
        slash = nil
        completedTasksKeptVisible = []
        escapedBlockID = nil
        drawnRows = nil
        env.activeDocument = document
    }

    func activeDocumentDidChange(_ active: DocumentContext?) {
        if active != document { slash = nil }
    }

    func openTaskDidChange(_ openTaskID: UUID?) {
        // Closing the inspector hands control back to the list.
        if openTaskID == nil { env.activeDocument = document }
    }

    /// The rows on show changed from `old` to `ids`.
    func visibleRowsDidChange(_ ids: [UUID], from old: [UUID] = []) {
        env.navigator.reconcileSelection(scope: selectionScopeID, visible: ids)
        // A line that stops showing while it holds the caret, folded away or
        // settled into Completed, is left, as a click away leaves it. Nothing
        // could take the caret there. A line just added, not drawn yet,
        // keeps it.
        guard let id = focus.blockID, old.contains(id), !ids.contains(id) else { return }
        if holdsEdit(id) { commitLine(leaving: true) }
        focus.request(nil)
    }

    /// Forgets the edit of a removed line, and moves a caret whose block went away.
    func blocksDidChange(_ ids: [UUID]) {
        // Undo or Trash took the line being edited: nothing is left to commit.
        if let edit = line, !ids.contains(edit.blockID) {
            line = nil
            edit.undoTargets.allObjects.forEach(discardTyping)
            endLine(edit)
        }
        if let pending = untrimmed, !ids.contains(pending.blockID) { untrimmed = nil }
        if let focused = focus.blockID, !ids.contains(focused) {
            // The caret goes; the host keeps the focus.
            focus.request(nil)
        }
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
/// reveal focus, row-selection reconciliation and the end of the line being written.
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
