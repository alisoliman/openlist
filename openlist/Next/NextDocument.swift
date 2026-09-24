//
//  NextDocument.swift
//  openlist
//
//  The list as the design's document: every line of it written in place,
//  over the outline engine the legacy editor shares.
//

import AppKit
import SwiftData
import SwiftUI

/// The document's task rows in order, for the page's J/K and ⌘A.
struct NXDocumentRowsKey: PreferenceKey {
    static let defaultValue: [UUID] = []
    static func reduce(value: inout [UUID], nextValue: () -> [UUID]) { value += nextValue() }
}

/// A list's lines, then the add row and the shortcut hints. Done top-level
/// tasks leave it for the Completed group the screen shows below.
struct NXDocumentOutline: View {
    @Environment(AppEnvironment.self) private var env
    let list: TaskList
    /// Draws only the tasks, as the list's Tasks presentation.
    var tasksOnly = false

    var body: some View {
        NXDocumentLines(list: list, tasksOnly: tasksOnly, env: env)
            // One engine per list, as the outline requires.
            .id(list.id)
    }
}

private struct NXDocumentLines: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Query private var fetched: [Block]
    @State private var editor: OutlineEditor
    @State private var contents = NXContentCache()
    let list: TaskList
    let tasksOnly: Bool

    init(list: TaskList, tasksOnly: Bool, env: AppEnvironment) {
        self.list = list
        self.tasksOnly = tasksOnly
        let document = DocumentContext(listID: list.id)
        // SwiftUI keeps the first editor for the view's lifetime and drops the
        // one built on each later init. Building one only assigns its inputs.
        _editor = State(initialValue: OutlineEditor(env: env, document: document, sorting: list.sorting,
                                                    policy: .nextDocument))
        _fetched = OutlineEditor.blocksQuery(for: document)
    }

    var body: some View {
        let document = DocumentContext(listID: list.id)
        editor.configure(document: document, showsCompleted: true, sorting: list.sorting, hooks: hooks)
        editor.tasksOnly = tasksOnly
        let blocks = fetched.filter { $0.modelContext != nil && !$0.isDeleted }
        let rows = editor.rowsToDraw(in: blocks)
        let workbench = env.workbench
        // The whole document, hidden lines too, for sections and progress.
        let everything = BlockTree.flatten(blocks, respectCollapse: false)
        let reveal = editor.reveal
        let context = NXLineContext(
            editor: editor,
            listID: list.id,
            focus: editor.focus,
            slashBlockID: editor.slash?.blockID,
            sections: BlockTree.sections(in: everything),
            progress: Self.progress(in: blocks, closing: Set(workbench.closing.keys)),
            contents: contents,
            drawnIDs: rows.map(\.id),
            reveal: reveal,
            readyRevealID: editor.readyRevealID)

        return LazyVStack(alignment: .leading, spacing: 1) {
            if let reveal {
                ContentRevealNotice(request: reveal, finish: env.navigator.finishReveal)
                    .padding(.bottom, 8)
            }
            ForEach(rows) { row in
                if row.block.modelContext != nil, !row.block.isDeleted {
                    NXDocumentRow(row: row, context: context)
                        // The grip's drags land before, after or inside a line.
                        .modifier(BlockDragAndDrop(
                            row: row,
                            isEnabled: list.sorting == .manual,
                            holdsDrops: OutlinePolicy.holdsDrops(row),
                            accent: style.accent,
                            indicatorInset: 10,
                            radius: 9,
                            onMove: { ids, position in editor.move(ids, relativeTo: row, position: position) },
                            onDropText: { text in editor.dropText(text, after: row.block) }))
                        .id(row.id)
                }
            }
            NXDocumentAddRow(text: rows.isEmpty
                             ? "Start typing — # for a heading, / to turn a line into anything"
                             : "Add to \(list.displayTitle)") {
                editor.appendTask()
            }
            NXDocumentHints()
        }
        .padding(.top, 12)
        .overlayPreferenceValue(EditorTextBoundsKey.self) { anchors in
            NXSlashCard(editor: editor, anchors: anchors)
        }
        .modifier(OutlineEditorLifecycle(editor: editor, document: document,
                                         visibleIDs: rows.map(\.id), blockIDs: blocks.map(\.id)))
        .preference(key: NXDocumentRowsKey.self, value: rows.filter(\.block.isTask).map(\.id))
        .onAppear {
            workbench.document = editor
            // The inspector's Add subtask, once this list's document is on show.
            if let id = workbench.pendingSubtaskParentID, env.store.block(id: id)?.listID == list.id {
                workbench.pendingSubtaskParentID = nil
                editor.appendSubtask(to: id)
            }
        }
        .onDisappear { if workbench.document === editor { workbench.document = nil } }
        .onChange(of: blocks.map(\.id)) { _, ids in contents.retain(Set(ids)) }
    }

    /// Where the design's document defers to the workbench: completion with
    /// its dwell, the inspector, focus and selection, Task-menu commands, and
    /// the change log with its names.
    private var hooks: OutlineHooks {
        let workbench = env.workbench
        let store = env.store
        let navigator = env.navigator
        var hooks = OutlineHooks()
        hooks.toggleCompletion = { workbench.toggle($0) }
        hooks.openDetails = { workbench.inspect($0) }
        hooks.didFocus = { id in
            guard let block = store.block(id: id) else { return }
            // As the design's startEdit: a task takes the focus, and the
            // selection clears. Writing a closing task keeps it open.
            if workbench.closing[id] != nil { workbench.cancelClosing([id]) }
            workbench.clearSelection()
            if workbench.editingNoteID != nil { workbench.editingNoteID = nil }
            workbench.focusID = block.isTask ? id : nil
            // A new line leaves the inspector where it is, as the design's addLine does.
            if block.isTask, navigator.openTaskID != nil, !workbench.fresh.contains(id) { navigator.openTask(id) }
        }
        // The caret leaves; the line stays focused for the keys.
        hooks.didEscape = { workbench.focusID = $0 }
        // Return and the arrows are the Next keys' once the caret has left.
        hooks.resumesAfterEscape = false
        hooks.taskCommand = { command, ids in
            env.performTaskCommand(command, on: ids.filter { store.block(id: $0)?.isTask == true })
        }
        hooks.commandTargets = { workbench.targetIDs }
        hooks.nameEdit = { Self.name(of: $0, store: store) }
        hooks.didRecordEdit = { edit, name in workbench.logEdit(name, ids: Self.ids(of: edit)) }
        hooks.didAddLine = { id in
            workbench.flash(\.fresh, [id], for: 1100)
            // A new task takes the focus, so the page brings it into view.
            if store.block(id: id)?.isTask == true { workbench.focusID = id }
        }
        hooks.editNote = { workbench.editNote($0) }
        return hooks
    }

    /// The design's undo labels.
    private static func name(of edit: OutlineEdit, store: Store) -> String {
        func quoted(_ id: UUID) -> String {
            guard let block = store.block(id: id) else { return "a line" }
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return NXFormat.quoted(text.isEmpty ? block.kind.title : text)
        }
        func described(_ ids: [UUID]) -> String { ids.count == 1 ? quoted(ids[0]) : "\(ids.count) lines" }
        switch edit {
        case let .added(id): return "Added \(quoted(id))"
        case let .edited(id): return "Edited \(quoted(id))"
        case .removedEmptyLine: return "Removed an empty line"
        case let .indented(ids): return "Indented \(described(ids))"
        case let .outdented(ids): return "Outdented \(described(ids))"
        case let .moved(id, up): return "Moved \(quoted(id)) \(up ? "up" : "down")"
        case let .dragged(ids): return "Moved \(described(ids))"
        }
    }

    private static func ids(of edit: OutlineEdit) -> [UUID] {
        switch edit {
        case let .added(id), let .edited(id), let .removedEmptyLine(id), let .moved(id, _): [id]
        case let .indented(ids), let .outdented(ids), let .dragged(ids): ids
        }
    }

    /// Done and total tasks under every task, counting those closing as done,
    /// as the design's progress chip does.
    private static func progress(in blocks: [Block], closing: Set<UUID>) -> [UUID: (done: Int, total: Int)] {
        let index = BlockTree.childIndex(of: blocks)
        var counts: [UUID: (done: Int, total: Int)] = [:]
        func visit(_ block: Block) -> (done: Int, total: Int) {
            if let cached = counts[block.id] { return cached }
            var result = (done: 0, total: 0)
            for child in index[block.id] ?? [] {
                let below = visit(child)
                if child.isTask {
                    result.total += 1
                    if child.isCompleted || closing.contains(child.id) { result.done += 1 }
                }
                result.done += below.done
                result.total += below.total
            }
            counts[block.id] = result
            return result
        }
        for block in blocks where block.isTask { _ = visit(block) }
        return counts
    }
}

/// What every line reads from its document in one pass.
private struct NXLineContext {
    let editor: OutlineEditor
    let listID: UUID
    let focus: EditorFocus
    let slashBlockID: UUID?
    let sections: [UUID: ArraySlice<BlockRow>]
    let progress: [UUID: (done: Int, total: Int)]
    let contents: NXContentCache
    /// The rows drawn, in order, for the grip to drag a selection in.
    let drawnIDs: [UUID]
    /// A search hit or link shown in the document.
    let reveal: ContentReveal?
    let readyRevealID: UUID?
}

/// Decoded line content, kept until its block changes, so a render doesn't
/// decode every line's rich text again.
@MainActor
private final class NXContentCache {
    private struct Key: Equatable {
        let updatedAt: Date
        let kind: BlockKind
        let isCompleted: Bool
        let text: String
    }

    private var entries: [UUID: (key: Key, content: NSAttributedString)] = [:]

    func content(of block: Block, store: Store) -> NSAttributedString {
        let key = Key(updatedAt: block.updatedAt, kind: block.kind, isCompleted: block.isCompleted, text: block.text)
        if let entry = entries[block.id], entry.key == key { return entry.content }
        let content = store.attributedContent(of: block)
        entries[block.id] = (key, content)
        return content
    }

    func retain(_ ids: Set<UUID>) {
        entries = entries.filter { ids.contains($0.key) }
    }
}

// MARK: - Lines

/// One line: a task on the Next row's chrome, or a heading, list item, text
/// or one of the editor's other kinds in the same language. It plays the
/// design's morphIn when its kind changes and rowIn when it's new.
private struct NXDocumentRow: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let row: BlockRow
    let context: NXLineContext
    @State private var morphing = false
    @State private var entered = false
    @State private var hovering = false
    /// Lets the pointer cross the margin to the grip before it hides.
    @State private var unhover: Task<Void, Never>?

    private var block: Block { row.block }
    private var workbench: Workbench { env.workbench }

    var body: some View {
        let fresh = !block.isTask && workbench.fresh.contains(row.id)
        let revealed = context.reveal?.blockID == row.id
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if block.isTask {
                    NXDocumentTask(row: row, context: context)
                } else {
                    NXDocumentBlock(row: row, context: context)
                }
            }
            .overlay {
                // Where a search hit or link landed.
                if revealed {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(style.accent, lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
            // A note found on a line that isn't a task, which has no inspector.
            if revealed, context.reveal?.field == .note, !block.isTask, !block.note.isEmpty {
                ContentRevealNote(text: block.note, query: context.reveal?.query ?? "", requestID: context.readyRevealID)
                    .id(ContentReveal.Anchor.blockNote(row.id))
                    .padding(.leading, CGFloat(row.depth) * 26 + 10)
                    .padding(.vertical, 4)
            }
        }
        .overlay(alignment: .topLeading) {
            if hasCaret {
                NXDocumentCaret(open: !block.isCollapsed) {
                    withAnimation(style.ease(180)) { context.editor.actions(for: row).onToggleCollapse() }
                }
                .offset(x: CGFloat(row.depth) * 26 - 10, y: caretTop)
            }
        }
        .overlay(alignment: .topLeading) {
            // In the margin, left of the caret's place.
            NXLineGrip(row: row, context: context, lineHovered: hovering)
                .offset(x: CGFloat(row.depth) * 26 - 28, y: caretTop)
        }
        .onHover { inside in
            unhover?.cancel()
            guard !inside else { hovering = true; return }
            unhover = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled { hovering = false }
            }
        }
        // morphIn, when a line turns into another kind.
        .opacity(morphing ? 0.3 : 1)
        .offset(x: morphing ? -6 : 0)
        // rowIn, for a new line; a task's chrome plays its own.
        .opacity(fresh && !entered ? 0 : 1)
        .offset(y: fresh && !entered ? -8 : 0)
        .scaleEffect(fresh && !entered ? 0.99 : 1)
        .onAppear { if fresh { enter() } }
        .onChange(of: block.kind) { _, _ in morph() }
    }

    /// Tasks with anything under them and headings with a section always
    /// show their caret.
    private var hasCaret: Bool {
        row.hasChildren || BlockTree.sectionLevel(of: block.kind) != nil && context.sections[row.id]?.isEmpty == false
    }

    private var caretTop: CGFloat {
        switch block.kind {
        case .heading1: 23
        case .heading2: 15
        default: 6
        }
    }

    private var animates: Bool { style.motion > 0.4 }

    private func morph() {
        guard animates else { return }
        withTransaction(\.disablesAnimations, true) { morphing = true }
        // Released on the next update, so the two changes don't merge into none.
        Task { @MainActor in
            withAnimation(.timingCurve(0.2, 0.9, 0.2, 1, duration: 0.32)) { morphing = false }
        }
    }

    private func enter() {
        guard animates else { entered = true; return }
        withAnimation(.timingCurve(0.2, 0.9, 0.2, 1, duration: 0.3)) { entered = true }
    }
}

/// The hover grip in a line's margin: drag it to move the line, with the
/// rows selected alongside it, before, after or into another line, or onto
/// a list in the sidebar. A click focuses the line, as a click on it does.
private struct NXLineGrip: View {
    @Environment(AppEnvironment.self) private var env
    let row: BlockRow
    let context: NXLineContext
    let lineHovered: Bool
    @State private var hovering = false

    var body: some View {
        let ids = draggedIDs
        ZStack {
            // Six dots, two by three.
            VStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 2.5) {
                        Circle().frame(width: 2.5, height: 2.5)
                        Circle().frame(width: 2.5, height: 2.5)
                    }
                }
            }
            .foregroundStyle(NX.ink(0.3))
            .opacity(lineHovered || hovering ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: lineHovered || hovering)
        }
        .frame(width: 14, height: 16)
        .background(hovering ? NX.ink(0.06) : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .pointerStyle(.grabIdle)
        .onTapGesture { click() }
        .onDrag { provider() } preview: {
            NXLineDragPreview(title: row.block.kind.isVoid ? row.block.kind.title : row.block.displayTitle, count: ids.count)
        }
        .help("Drag to move")
        .accessibilityHidden(true)
    }

    /// The line, or the drawn rows selected with it, in document order.
    private var draggedIDs: [UUID] {
        let selection = env.workbench.selection
        guard selection.contains(row.id) else { return [row.id] }
        return context.drawnIDs.filter(selection.contains)
    }

    /// The row drag the document, and the sidebar's lists, take: this
    /// library's own payload, never text another app or a line could read.
    private func provider() -> NSItemProvider {
        let payload = DragPayload.encodeBlocks(draggedIDs, session: env.navigator.blockDragSessionID)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: DragPayload.blockTypeIdentifier, visibility: .ownProcess) { load in
            load(Data(payload.utf8), nil)
            return nil
        }
        return provider
    }

    private func click() {
        if row.block.isTask {
            NXDocumentEditing.end()
            env.workbench.click(row.id, command: NXModifiers.command, shift: NXModifiers.shift)
        } else if !row.block.kind.isVoid {
            context.editor.edit(row.id)
        }
    }
}

/// What a dragged line looks like under the pointer: its text on a card,
/// with a count of the rows moving with it.
private struct NXLineDragPreview: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13.8))
                .foregroundStyle(NX.ink)
                .lineLimit(1)
            if count > 1 {
                Text("+\(count - 1)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NX.ink(0.58))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .nxCardShadow(radius: 9, hairline: 0.14, drop: 0.12, y: 6, blur: 18)
    }
}

/// The disclosure chevron left of a line.
private struct NXDocumentCaret: View {
    let open: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .rotationEffect(.degrees(open ? 90 : 0))
                .animation(NX.cssEase(180), value: open)
                .frame(width: 16, height: 16)
                .foregroundStyle(hovering ? NX.ink : NX.ink(0.34))
                .background(hovering ? NX.ink(0.06) : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .accessibilityLabel(open ? "Collapse" : "Expand")
    }
}

// MARK: Tasks

/// A task line: the Next row's chrome, its title the live text, with the
/// subtask progress chip, the note button and the note in place.
private struct NXDocumentTask: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let row: BlockRow
    let context: NXLineContext

    private var task: Block { row.block }
    private var workbench: Workbench { env.workbench }

    var body: some View {
        let id = row.id
        let editing = context.focus.blockID == id
        let noteEditing = workbench.editingNoteID == id
        let noteOpen = workbench.openNotes.contains(id)
        NXTaskRowChrome(task: task, options: NXRowOptions(showList: false, listID: context.listID),
                        indent: CGFloat(row.depth) * 26, leadingChips: progressChip,
                        editing: editing || noteEditing, entrance: 300, draggable: false,
                        onClick: {
                            // Clicking beside the text leaves any line being written, as a click away does.
                            NXDocumentEditing.end()
                            workbench.click(id, command: NXModifiers.command, shift: NXModifiers.shift)
                        }) {
            VStack(alignment: .leading, spacing: 0) {
                NXLineText(row: row, context: context, editing: editing)
                    .overlay(alignment: .topLeading) {
                        // The design's hint that a folded note is there.
                        if !editing, !noteOpen, !noteEditing, !task.note.isEmpty {
                            NXNoteHint(content: context.contents.content(of: task, store: env.store))
                        }
                    }
                if noteOpen || noteEditing {
                    NXDocumentNote(task: task, listID: context.listID, editing: noteEditing)
                        .padding(.top, 3)
                        .padding(.bottom, 4)
                        .transition(.opacity.animation(.easeOut(duration: 0.18)))
                }
            }
        } buttons: {
            Button { workbench.toggleNote(id) } label: {
                Image(systemName: "text.alignleft").font(.system(size: 12.5, weight: .medium))
            }
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), radius: 6,
                                            padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3),
                                            foreground: noteOpen ? style.accent : NX.ink(0.45), hoverForeground: NX.ink))
            .opacity(!task.note.isEmpty || noteOpen ? 0.9 : 0.2)
            .animation(.easeOut(duration: 0.14), value: noteOpen)
            .help("Note · Space")
            .accessibilityLabel(noteOpen ? "Hide note" : "Show note")
        }
    }

    private var progressChip: [NXChipModel] {
        guard let progress = context.progress[row.id], progress.total > 0 else { return [] }
        return [NXChipModel(id: "subtasks", label: "\(progress.done)/\(progress.total)", icon: "arrow.turn.down.right",
                            tone: progress.done == progress.total ? .green : .neutral)]
    }
}

/// The notes glyph after a task's title whose note is folded away, set
/// after the last line's text as the design's inline icon.
private struct NXNoteHint: View {
    let content: NSAttributedString

    var body: some View {
        GeometryReader { proxy in
            let inset = Theme.Editor.lineBoxInset(for: .task)
            let end = NXTextMeasure.end(of: content, width: proxy.size.width)
            Image(systemName: "text.alignleft")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NX.ink(0.3))
                .frame(width: 13, height: 13)
                // 7pt after the text, its box 2pt under the baseline.
                .offset(x: min(end.x + 7, max(0, proxy.size.width - 13)), y: inset + end.baseline - 11)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Where a line's text ends, laid out by TextKit as its text view lays it.
private enum NXTextMeasure {
    static func end(of content: NSAttributedString, width: CGFloat) -> (x: CGFloat, baseline: CGFloat) {
        guard content.length > 0, width > 1 else { return (0, 13) }
        let storage = NSTextStorage(attributedString: content)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let last = max(0, layout.numberOfGlyphs - 1)
        let line = layout.lineFragmentUsedRect(forGlyphAt: last, effectiveRange: nil)
        return (line.maxX, line.minY + layout.location(forGlyphAt: last).y)
    }
}

/// A task's note written in place, or shown, under its title.
private struct NXDocumentNote: View {
    @Environment(AppEnvironment.self) private var env
    let task: Block
    let listID: UUID
    let editing: Bool

    var body: some View {
        if editing {
            NXNoteEditor(initial: task.note, caretColor: env.settings.accent.editorColor, onCommit: commit,
                         onBackToTitle: { env.workbench.document?.edit(task.id) })
        } else {
            let empty = task.note.isEmpty
            let leading = max(0, 13 * 1.55 - NXStrikeText.glyphLineHeight(13))
            Text(empty ? "Add a note…" : task.note)
                .font(.system(size: 13))
                .lineSpacing(leading)
                .foregroundStyle(NX.ink(empty ? 0.32 : 0.62))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, leading / 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { env.workbench.editNote(task.id) }
                .pointerStyle(.horizontalText)
        }
    }

    /// The design's note commit: trailing space goes, the note stays open
    /// only if it has something, and a change is one step, logged.
    private func commit(_ text: String, typing: NSTextStorage) {
        let workbench = env.workbench
        let store = env.store
        if workbench.editingNoteID == task.id { workbench.editingNoteID = nil }
        let value = text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        if value.isEmpty { workbench.openNotes.remove(task.id) } else { workbench.openNotes.insert(task.id) }
        // The note's typing folds into its one step.
        let view = typing.layoutManagers.first?.firstTextView
        view?.breakUndoCoalescing()
        view?.undoManager?.removeAllActions(withTarget: typing)
        guard let current = store.block(id: task.id), value != current.note else { return }
        let title = current.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = "Edited note on \(NXFormat.quoted(title.isEmpty ? "Untitled" : title))"
        store.undoableEditorEdit(in: listID, name: label, undoManager: workbench.undoManager,
                                 didRegister: { workbench.logEdit(label, ids: [current.id]) }) {
            store.setNote(value, for: current)
        }
    }
}

/// The note's textarea: 400 13/1.55 ink .66. Return breaks the line; Esc and
/// ⌘Return commit; ⇧Tab commits and goes back to the title. Leaving it by
/// any other way commits too.
private struct NXNoteEditor: NSViewRepresentable {
    let initial: String
    let caretColor: NSColor
    let onCommit: (String, NSTextStorage) -> Void
    let onBackToTitle: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NXNoteTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let view = NXNoteTextView(frame: .zero, textContainer: container)
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isContinuousSpellCheckingEnabled = true
        view.textContainerInset = NSSize(width: 0, height: NXNoteTextView.inset)
        view.typingAttributes = NXNoteTextView.attributes
        view.textStorage?.setAttributedString(NSAttributedString(string: initial, attributes: NXNoteTextView.attributes))
        view.insertionPointColor = caretColor
        context.coordinator.parent = self
        // Once the view is in its window, the note takes the keyboard.
        DispatchQueue.main.async { [weak view] in
            guard let view, let window = view.window else { return }
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        }
        return view
    }

    func updateNSView(_ view: NXNoteTextView, context: Context) {
        context.coordinator.parent = self
    }

    /// Taken away while it's still being written, the note keeps what was
    /// typed, once the update that took it away is over.
    static func dismantleNSView(_ view: NXNoteTextView, coordinator: Coordinator) {
        coordinator.commit(view, later: true)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NXNoteTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 1 else { return nil }
        return CGSize(width: width, height: nsView.height(fittingWidth: width))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NXNoteEditor?
        private var committed = false

        func textDidChange(_ notification: Notification) {
            (notification.object as? NSView)?.invalidateIntrinsicContentSize()
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            commit(view)
        }

        func commit(_ view: NSTextView, later: Bool = false) {
            guard !committed, let storage = view.textStorage, let parent else { return }
            committed = true
            let text = view.string
            if later {
                DispatchQueue.main.async { parent.onCommit(text, storage) }
            } else {
                parent.onCommit(text, storage)
            }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)):
                textView.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.makeFirstResponder(nil)
                parent?.onBackToTitle()
                return true
            default:
                return false
            }
        }
    }
}

/// The note's text view: self-sizing, with a placeholder and ⌘Return.
final class NXNoteTextView: NSTextView {
    static let font = NSFont.systemFont(ofSize: 13)
    /// The design's 1.55 line box around TextKit's own line.
    static let inset: CGFloat = max(0, 13 * 1.55 - NSLayoutManager().defaultLineHeight(for: font)) / 2
    static let attributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = inset * 2
        return [.font: font, .foregroundColor: Theme.Editor.secondaryInk, .paragraphStyle: paragraph]
    }()

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 36 || event.keyCode == 76, flags.contains(.command) {
            window?.makeFirstResponder(nil)
            return
        }
        super.keyDown(with: event)
    }

    func height(fittingWidth width: CGFloat) -> CGFloat {
        guard let container = textContainer, let layout = layoutManager else { return 20 }
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let line = max(used.maxY, layout.extraLineFragmentRect.maxY, layout.defaultLineHeight(for: Self.font))
        return ceil(line) + textContainerInset.height * 2
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        var attributes = Self.attributes
        attributes[.foregroundColor] = Theme.Editor.placeholderInk
        NSAttributedString(string: "Add a note…", attributes: attributes)
            .draw(in: NSRect(origin: textContainerOrigin, size: bounds.size))
    }
}

// MARK: Other kinds

/// A heading, list item, text line or one of the editor's other kinds.
private struct NXDocumentBlock: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let row: BlockRow
    let context: NXLineContext

    private var block: Block { row.block }

    var body: some View {
        let editing = context.focus.blockID == row.id
        // Left with Escape, a line keeps the keys' focus; the design has no
        // mark for it, so it keeps the editing fill.
        let focused = !editing && env.workbench.focusID == row.id
        let heading = BlockTree.sectionLevel(of: block.kind) != nil
        HStack(alignment: .top, spacing: 0) {
            if row.depth > 0 { Color.clear.frame(width: CGFloat(row.depth) * 26, height: 1) }
            gutter
            content(editing: editing)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if let chip = openChip {
                NXChip(chip: chip)
                    .padding(.top, 1)
                    .padding(.leading, 6)
            }
        }
        .padding(.top, padding.top)
        .padding(.bottom, padding.bottom)
        .padding(.horizontal, 10)
        .background(editing && !heading || focused ? NX.ink(0.035) : .clear,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(.easeOut(duration: 0.18), value: editing || focused)
        .zIndex(editing ? 4 : 0)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !block.kind.isVoid else { return }
            context.editor.edit(row.id)
        }
    }

    /// The design's line paddings: 20/4 and 13/3 for its headings, 5 for the rest.
    private var padding: (top: CGFloat, bottom: CGFloat) {
        switch block.kind {
        case .heading1: (20, 4)
        case .heading2: (13, 3)
        default: (5, 5)
        }
    }

    /// A collapsed heading counts the open tasks it folds away.
    private var openChip: NXChipModel? {
        guard block.isCollapsed, let section = context.sections[row.id] else { return nil }
        let tasks = section.filter(\.block.isTask)
        guard !tasks.isEmpty else { return nil }
        return NXChipModel(id: "open", label: "\(tasks.filter { !$0.block.isCompleted }.count) open")
    }

    @ViewBuilder
    private var gutter: some View {
        switch block.kind {
        case .bullet:
            Circle()
                .fill(NX.ink(0.45))
                .frame(width: 5, height: 5)
                .padding(.top, 8)
                .frame(width: 26)
        case .numbered:
            // The ordinal's baseline on the text's first baseline.
            let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            let baseline = Theme.Editor.lineBoxInset(for: .numbered) + Theme.Editor.baselineOffset(for: .numbered)
            Text("\(row.ordinal).")
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(NX.ink(0.45))
                .padding(.top, max(0, baseline - font.ascender))
                .frame(width: 26, alignment: .leading)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func content(editing: Bool) -> some View {
        switch block.kind {
        case .divider:
            Rectangle()
                .fill(NX.ink(0.1))
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        case .image:
            NXDocumentImage(block: block)
        case .code:
            NXLineText(row: row, context: context, editing: editing)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(NX.ink(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .quote:
            // A 2.5pt accent rail down the quote's side.
            NXLineText(row: row, context: context, editing: editing)
                .padding(.leading, 13.5)
                .overlay(alignment: .leading) {
                    Capsule().fill(style.accent.opacity(0.45)).frame(width: 2.5)
                }
        default:
            NXLineText(row: row, context: context, editing: editing)
        }
    }
}

/// An image line: rounded 11, a hairline, its caption under it.
private struct NXDocumentImage: View {
    let block: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let filename = block.mediaFilename, let image = MediaStore.shared.image(named: filename, data: block.mediaData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: min(560, block.mediaWidth > 0 ? block.mediaWidth : 560), alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(NX.ink(0.1), lineWidth: 0.5))
            } else {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(NX.ink(0.035))
                    .frame(height: 80)
                    .overlay(Image(systemName: "photo").foregroundStyle(NX.ink(0.3)))
            }
            if !block.mediaCaption.isEmpty {
                Text(block.mediaCaption)
                    .font(.system(size: 12))
                    .foregroundStyle(NX.ink(0.5))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: Text

/// A line's live text, in its kind's font and the design's line box.
private struct NXLineText: View {
    @Environment(AppEnvironment.self) private var env
    let row: BlockRow
    let context: NXLineContext
    let editing: Bool

    var body: some View {
        let block = row.block
        let workbench = env.workbench
        let id = row.id
        let closing = block.isTask ? workbench.closing[id] : nil
        let editor = context.editor
        var callbacks = editor.actions(for: row).editorCallbacks
        callbacks.onInactiveClick = { event in
            // As the design's onEdit: a closing row's click takes it back,
            // and ⌘ or ⇧ selects rather than writes.
            if workbench.closing[id] != nil {
                workbench.cancelClosing([id])
                return true
            }
            let flags = event.modifierFlags.intersection([.command, .shift])
            guard flags.isEmpty else {
                if block.isTask { workbench.toggleSelection(id) }
                return true
            }
            return false
        }
        callbacks.onDoubleClick = { if block.isTask { workbench.inspect(id) } }
        return BlockTextView(
            blockID: id,
            kind: block.kind,
            isCompleted: block.isCompleted,
            struck: closing,
            strikeColor: closing != nil ? env.settings.accent.editorColor : nil,
            dimsStruck: closing == nil,
            verticalInset: Theme.Editor.lineBoxInset(for: block.kind),
            attributedText: context.contents.content(of: block, store: env.store),
            placeholder: editing ? Self.placeholder(for: block.kind) : "",
            isFocused: editor.isFocused(id),
            pendingCaret: editor.pendingCaret(for: id),
            focusToken: context.focus.token,
            isSlashMenuOpen: context.slashBlockID == id,
            slashOpensAtStartOnly: true,
            caretColor: env.settings.accent.editorColor,
            onSlashCommand: { editor.handleSlashCommand($0) },
            callbacks: callbacks
        )
        .anchorPreference(key: EditorTextBoundsKey.self, value: .bounds) { [id: $0] }
    }

    /// The design's placeholders, and the editor's for its other kinds.
    static func placeholder(for kind: BlockKind) -> String {
        switch kind {
        case .task: "Task — “/” turns it into anything, ⇥ makes it a subtask"
        case .bullet, .numbered: "List item"
        case .heading1: "Heading"
        case .heading2: "Subheading"
        case .heading3: "Small heading"
        case .quote: "Quote"
        case .code: "Code"
        default: "Write something…"
        }
    }
}

/// Ends the writing of any document line, as a click away from it does.
enum NXDocumentEditing {
    @MainActor
    static func end() {
        guard let window = NSApp.keyWindow, window.firstResponder is BlockNSTextView else { return }
        window.makeFirstResponder(nil)
    }
}

// MARK: - Turn into

/// The design's "Turn into" card under a line that starts with `/`: its
/// five kinds, then the editor's others under "More".
private struct NXSlashCard: View {
    @Environment(\.nextStyle) private var style
    let editor: OutlineEditor
    let anchors: [UUID: Anchor<CGRect>]

    var body: some View {
        if let slash = editor.slash, let anchor = anchors[slash.blockID] {
            GeometryReader { proxy in
                let frame = proxy[anchor]
                card(options: OutlineSlashOption.matching(slash.query), selected: slash.selectedIndex)
                    .offset(x: frame.minX - 6, y: frame.maxY + 6)
            }
            .id(slash.blockID)
        }
    }

    private func card(options: [OutlineSlashOption], selected: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            header("Turn into")
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                if option.isExtra, index == 0 || !options[index - 1].isExtra {
                    header("More")
                }
                item(option, index: index, selected: index == selected)
            }
        }
        .padding(5)
        .frame(width: 270, alignment: .leading)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .nxCardShadow(radius: 11, hairline: 0.14, drop: 0.18, y: 16, blur: 40)
        .background(SlashMenuDismissal(onDismiss: { editor.dismissSlashMenu() }))
        .modifier(NXPopIn())
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.8)
            .textCase(.uppercase)
            .foregroundStyle(NX.ink(0.36))
            .padding(.top, 7)
            .padding(.horizontal, 9)
            .padding(.bottom, 6)
    }

    private func item(_ option: OutlineSlashOption, index: Int, selected: Bool) -> some View {
        Button { editor.applySlashSelection(option.kind) } label: {
            HStack(spacing: 10) {
                Image(systemName: option.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.white : NX.ink(0.5))
                    .frame(width: 16, height: 16)
                Text(option.label)
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !option.hint.isEmpty {
                    Text(option.hint).font(NX.mono(10.5)).opacity(0.5)
                }
            }
            .foregroundStyle(selected ? Color.white : NX.ink)
            .padding(.vertical, 8)
            .padding(.horizontal, 9)
            .background(selected ? style.accent : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { if $0 { editor.highlightSlashResult(index) } }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(option.kind.subtitle)
    }
}

/// The design's popIn, from the top-left corner, each time a card opens.
private struct NXPopIn: ViewModifier {
    @Environment(\.nextStyle) private var style
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.97, anchor: .topLeading)
            .offset(y: shown ? 0 : -4)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.timingCurve(0.2, 0.9, 0.2, 1, duration: style.ms(160) / 1000)) { shown = true } }
    }
}

// MARK: - Add row and hints

/// The design's docAdd: adds a task line at the end and writes it.
private struct NXDocumentAddRow: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(NX.ink(0.24), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
                .frame(width: 15, height: 15)
            // 400 13.5/1.3.
            Text(text)
                .font(.system(size: 13.5))
                .padding(.vertical, (13.5 * 1.3 - NXStrikeText.glyphLineHeight(13.5)) / 2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(hovering ? NX.ink(0.55) : NX.ink(0.36))
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(hovering ? NX.ink(0.035) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .pointerStyle(.horizontalText)
        .padding(.top, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

/// The shortcut strip under the document.
private struct NXDocumentHints: View {
    private static let hints: [(key: String, label: String)] = [
        ("#", "Heading"), ("##", "Subheading"), ("-", "Bullet"), ("[ ]", "Task"),
        ("/", "Turn into"), ("⇥", "Subtask"), ("⇧↩", "Note"), ("Space", "Show note"),
    ]

    var body: some View {
        MetadataFlowLayout(spacing: 14) {
            ForEach(Self.hints, id: \.key) { hint in
                HStack(spacing: 5) {
                    Text(hint.key)
                        .font(NX.mono(10))
                        // The design's line-height 1, inside 2/5 padding.
                        .padding(.vertical, 2 + (10 - NXStrikeText.glyphLineHeight(10)) / 2)
                        .padding(.horizontal, 5)
                        .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                    Text(hint.label)
                        .fixedSize()
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(NX.ink(0.38))
        .padding(.top, 10)
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
    }
}
