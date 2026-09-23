//
//  DocumentView.swift
//  openlist
//

import AppKit
import SwiftData
import SwiftUI

/// Renders and edits one document: a list, or a task's detail page.
struct DocumentView: View {
    /// Selection gutter (22), row inset (6), and disclosure slot (14).
    static let markerInset: CGFloat = 42
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
    var appendButtonTitle: String?
    var usesInboxActions = false

    @Environment(AppEnvironment.self) private var env

    init(
        document: DocumentContext,
        emptyPlaceholder: String = "Add a task…",
        showsCompleted: Bool = true,
        sorting: ListSorting = .manual,
        seedsEmptyBlock: Bool = true,
        trailingSpace: CGFloat = 120,
        appendButtonTitle: String? = nil,
        usesInboxActions: Bool = false
    ) {
        self.document = document
        self.emptyPlaceholder = emptyPlaceholder
        self.showsCompleted = showsCompleted
        self.sorting = sorting
        self.seedsEmptyBlock = seedsEmptyBlock
        self.trailingSpace = trailingSpace
        self.appendButtonTitle = appendButtonTitle
        self.usesInboxActions = usesInboxActions
    }

    var body: some View {
        DocumentOutline(configuration: self, env: env)
    }
}

/// The legacy renderer over ``OutlineEditor``: selection gutter, list-accent
/// markers and metadata chips below each task's title.
private struct DocumentOutline: View {
    let configuration: DocumentView

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var fetchedBlocks: [Block]
    @Query(sort: [SortDescriptor(\TaskLabel.name)]) private var allLabels: [TaskLabel]

    @State private var editor: OutlineEditor
    @State private var completionMotionIDs: Set<UUID> = []

    init(configuration: DocumentView, env: AppEnvironment) {
        self.configuration = configuration
        _editor = State(initialValue: OutlineEditor(env: env, document: configuration.document,
            showsCompleted: configuration.showsCompleted, sorting: configuration.sorting))
        _fetchedBlocks = OutlineEditor.blocksQuery(for: configuration.document)
    }

    private var document: DocumentContext { configuration.document }

    // MARK: - Derived state

    private var blocks: [Block] {
        fetchedBlocks.filter { $0.modelContext != nil && !$0.isDeleted }
    }

    private var listAccent: ListAccent {
        env.store.list(id: document.listID)?.accent ?? .graphite
    }

    /// Label lookup built once per render rather than per row.
    private var labelsByID: [UUID: TaskLabel] {
        Dictionary(allLabels.filter { $0.modelContext != nil && !$0.isDeleted }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        editor.configure(document: document, showsCompleted: configuration.showsCompleted, sorting: configuration.sorting)
        // Computed once per render and shared by every row, so drawing a
        // document costs one pass over the block list rather than one fetch
        // per row.
        let liveBlocks = blocks
        let visibleRows = editor.visibleRows(in: liveBlocks)
        let visibleIDs = visibleRows.map(\.id)
        let labelLookup = labelsByID
        let progress = BlockTree.subtaskCounts(in: liveBlocks)
        let completedTaskIDs = Set(liveBlocks.filter { $0.isTask && $0.isCompleted }.map(\.id))
        let reveal = editor.reveal
        // Read here rather than per row, so a caret or menu move redraws the
        // whole document as it did when this state lived in the view.
        let focus = editor.focus
        let slashBlockID = editor.slash?.blockID

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
                        rowView(for: row, labelLookup: labelLookup, progress: progress[row.id],
                                focus: focus, slashBlockID: slashBlockID, rowCount: visibleRows.count)
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
                            ContentRevealNote(text: row.block.note, query: reveal?.query ?? "", requestID: editor.readyRevealID)
                                .id(ContentReveal.Anchor.blockNote(row.id))
                        }
                    }
                    .id(row.id)
                    .zIndex(completionMotionIDs.contains(row.id) ? 1 : 0)
                }
            }

            if let appendButtonTitle = configuration.appendButtonTitle {
                Button(action: editor.appendTask) {
                    Label(appendButtonTitle, systemImage: "plus")
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(QuietButtonStyle())
                .padding(.leading, configuration.usesInboxActions ? DocumentView.markerInset : 0)
                .padding(.top, configuration.usesInboxActions ? 12 : 0)
                .accessibilityIdentifier("document-append-task")
                .contextMenu { pasteMenu }
            } else {
                trailingTapTarget(isEmpty: visibleRows.isEmpty)
            }
        }
        .environment(\.rowSelectionContext, RowSelectionContext(scopeID: editor.selectionScopeID, visibleIDs: visibleIDs) {
            editor.beginRowSelection()
        })
        .scrollTargetLayout()
        .animation(Theme.Motion.feedback(reduceMotion: reduceMotion, duration: Theme.Motion.rearrangementDuration),
                   value: completedTaskIDs)
        .animation(Theme.Motion.feedback(reduceMotion: reduceMotion, duration: Theme.Motion.rearrangementDuration),
                   value: configuration.showsCompleted)
        .onChange(of: completedTaskIDs) { previous, current in
            guard Theme.Motion.allowsAnimation(reduceMotion: reduceMotion, eventType: NSApp.currentEvent?.type) else {
                completionMotionIDs.removeAll()
                return
            }
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
            do { try await Task.sleep(for: .milliseconds(240)) }
            catch { return }
            completionMotionIDs.removeAll()
        }
        .overlayPreferenceValue(EditorTextBoundsKey.self) { anchors in
            OutlineSlashMenu(editor: editor, anchors: anchors)
        }
        .modifier(OutlineEditorLifecycle(editor: editor, document: document,
                                         visibleIDs: visibleIDs, blockIDs: liveBlocks.map(\.id)))
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowView(
        for row: BlockRow,
        labelLookup: [UUID: TaskLabel],
        progress: (done: Int, total: Int)?,
        focus: EditorFocus,
        slashBlockID: UUID?,
        rowCount: Int
    ) -> some View {
        if row.block.modelContext != nil, !row.block.isDeleted {
            HStack(alignment: .top, spacing: 0) {
                RowSelectionGutter(id: row.id, title: row.block.displayTitle, requiresSelectionMode: configuration.usesInboxActions)
                BlockRowView(
                    row: row,
                    listAccent: listAccent,
                    labels: row.block.labelIDs.compactMap { labelLookup[$0] },
                    progress: (progress?.total ?? 0) > 0 ? progress : nil,
                    isFocused: focus.blockID == row.id,
                    isSelected: editor.isSelected(row.id),
                    pendingCaret: focus.blockID == row.id ? focus.caret : nil,
                    focusToken: focus.token,
                    isSlashMenuOpen: slashBlockID == row.id,
                    onSlashCommand: { command in editor.handleSlashCommand(command) },
                    attributedText: env.store.attributedContent(of: row.block),
                    placeholder: configuration.emptyPlaceholder,
                    showsPlaceholder: editor.showsPlaceholder(for: row, rowCount: rowCount),
                    usesInboxActions: configuration.usesInboxActions,
                    actions: editor.actions(for: row)
                )
            }
            .modifier(
                BlockDragAndDrop(
                    row: row,
                    isEnabled: configuration.sorting == .manual,
                    onMove: { draggedIDs, position in editor.move(draggedIDs, relativeTo: row, position: position) },
                    onDropText: { text in editor.dropText(text, after: row.block) }
                )
            )
        }
    }

    /// Blank space under the document: clicking it appends a new task, the way
    /// clicking below a note's last line starts a new line.
    private func trailingTapTarget(isEmpty: Bool) -> some View {
        Color.clear
            .frame(height: configuration.trailingSpace)
            .overlay(alignment: .topLeading) {
                if isEmpty, configuration.seedsEmptyBlock {
                    Label(configuration.emptyPlaceholder, systemImage: "plus.circle")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isEmpty ? configuration.emptyPlaceholder : "Add a task")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { editor.appendTask() }
            .onTapGesture { editor.focusOrAppendTrailingTask() }
            .contextMenu { pasteMenu }
    }

    private var pasteMenu: some View {
        FragmentPasteMenu(document: document) { ids in editor.didPasteFragment(ids) }
    }
}
