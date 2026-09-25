//
//  NextInspector.swift
//  openlist
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A task's ancestors in its list document, nearest first, looked up again
/// only when the chain changes, so typing in the task doesn't fetch them on
/// every keystroke.
@MainActor
private final class NXLineage {
    private var key: [UUID?] = []
    private var chain: [Block] = []

    func ancestors(of task: Block, store: Store) -> [Block] {
        let live = chain.allSatisfy { $0.modelContext != nil && !$0.isDeleted && $0.trashID == nil }
        // A chain that stopped short of the top, at a parent out of reach, is looked up again.
        let complete = (chain.last?.parentID ?? task.parentID) == nil
        if live, complete, key == Self.key(of: task, chain: chain) { return chain }
        var result: [Block] = []
        var seen: Set<UUID> = [task.id]
        var next = task.parentID
        while let id = next, seen.insert(id).inserted, let block = store.block(id: id) {
            result.append(block)
            next = block.parentID
        }
        chain = result
        key = Self.key(of: task, chain: result)
        return result
    }

    /// The task and each link's parent, read from the models without a fetch.
    private static func key(of task: Block, chain: [Block]) -> [UUID?] {
        [task.id, task.parentID] + chain.map(\.parentID)
    }
}

/// Ends the title's or note's editing when the mouse goes down off the field,
/// as a browser blurs an input on a click elsewhere. AppKit leaves a text field
/// first responder when a SwiftUI row, subtask, crumb or pill is clicked, so
/// the next key would type into the title, the next task's once the panel
/// moves on, rather than act on the row. A click in the box drawn around a
/// field is in the field, as in a textarea's padding. While capture, search
/// or the palette is open, the clicks are its card's, drawn over the panel.
@MainActor
private final class NXInspectorClicks {
    private var monitor: Any?
    private var settling: Task<Void, Never>?
    /// The panel's own view, for its window and frame.
    weak var panel: NSView?
    /// The title's and the note box's areas, the padding around the text included.
    private let areas = NSHashTable<NSView>.weakObjects()
    /// Whether an overlay card covers the panel.
    private var covered: () -> Bool = { false }

    func install(covered: @escaping () -> Bool) {
        self.covered = covered
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        settling?.cancel()
    }

    fileprivate func mark(_ view: NSView, as role: NXInspectorMark.Role) {
        switch role {
        case .panel: panel = view
        case .field: areas.add(view)
        }
    }

    /// Lets the field go at once, as the panel moves to another task.
    func endEditing() {
        guard let window = panel?.window, editedFrame(in: window) != nil else { return }
        window.makeFirstResponder(nil)
    }

    /// Runs `action` once the click under way, if any, is over, and a beat
    /// more, so what it changes doesn't move what was clicked out from under
    /// the pointer before its button fires on mouse-up, as the Tasks bar waits.
    func afterClick(_ action: @escaping @MainActor () -> Void) {
        settling?.cancel()
        guard NSEvent.pressedMouseButtons != 0 else { return action() }
        settling = Task { @MainActor in
            repeat {
                try? await Task.sleep(for: .milliseconds(60))
            } while NSEvent.pressedMouseButtons != 0 && !Task.isCancelled
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    /// A click on text or a scroller goes as AppKit sends it: in the field it
    /// places the caret, another field takes the keys, and scrolling leaves
    /// the edit be. One in the box around a field puts the caret there;
    /// anywhere else it ends the edit.
    private func handle(_ event: NSEvent) {
        guard let window = panel?.window, event.window === window, !covered() else { return }
        let point = event.locationInWindow
        // Only what shows of a box counts, not the part scrolled under the bars.
        let area = areas.allObjects.lazy.filter { $0.window === window }
            .map { $0.convert($0.visibleRect, to: nil) }.first { $0.contains(point) }
        guard area != nil || editedFrame(in: window) != nil else { return }
        if let hit = window.contentView?.hitTest(point),
           hit is NSScroller || sequence(first: hit, next: \.superview).contains(where: { $0 is NSText || $0 is NSTextField }) {
            return
        }
        if let area {
            // A right click there leaves things be, as a textarea keeps its focus.
            guard event.type == .leftMouseDown, let field = field(in: area, window: window) else { return }
            if !isEditing(field, in: window) { window.makeFirstResponder(field) }
            placeCaret(near: point, in: window)
        } else {
            window.makeFirstResponder(nil)
        }
    }

    /// Where the field being edited is in the window, when it's the panel's.
    private func editedFrame(in window: NSWindow) -> CGRect? {
        guard let panel, let editor = window.firstResponder as? NSText else { return nil }
        let field = editor.delegate as? NSView ?? editor
        let frame = field.convert(field.visibleRect, to: nil)
        return panel.convert(panel.bounds, to: nil).contains(CGPoint(x: frame.midX, y: frame.midY)) ? frame : nil
    }

    private func isEditing(_ field: NSView, in window: NSWindow) -> Bool {
        guard let editor = window.firstResponder as? NSText else { return false }
        return (editor.delegate as? NSView ?? editor) === field
    }

    /// The editable field an area is drawn around: the one being edited, or
    /// the one found inside it.
    private func field(in area: CGRect, window: NSWindow) -> NSView? {
        if let editor = window.firstResponder as? NSText {
            let field = editor.delegate as? NSView ?? editor
            if area.contains(Self.center(of: field)) { return field }
        }
        return window.contentView.flatMap { Self.editableText(in: area, under: $0) }
    }

    private static func editableText(in area: CGRect, under view: NSView) -> NSView? {
        for subview in view.subviews where !subview.isHidden {
            if (subview as? NSTextField)?.isEditable == true || (subview as? NSTextView)?.isEditable == true,
               area.contains(center(of: subview)) {
                return subview
            }
            if let found = editableText(in: area, under: subview) { return found }
        }
        return nil
    }

    /// The caret at the place in the text nearest the click, as a textarea
    /// puts it for a click in its padding: below the last line, at its end.
    private func placeCaret(near point: CGPoint, in window: NSWindow) {
        guard let editor = window.firstResponder as? NSTextView else { return }
        let local = editor.convert(point, from: nil)
        let bounds = editor.bounds
        let clamped = CGPoint(x: min(max(local.x, bounds.minX), bounds.maxX),
                              y: min(max(local.y, bounds.minY), bounds.maxY))
        let length = (editor.string as NSString).length
        let index = editor.characterIndexForInsertion(at: clamped)
        editor.setSelectedRange(NSRange(location: index == NSNotFound ? length : min(index, length), length: 0))
    }

    private static func center(of view: NSView) -> CGPoint {
        let frame = view.convert(view.bounds, to: nil)
        return CGPoint(x: frame.midX, y: frame.midY)
    }
}

/// Hands `NXInspectorClicks` the panel's view, or the area drawn around a
/// field, taking no clicks itself.
private struct NXInspectorMark: NSViewRepresentable {
    enum Role { case panel, field }
    let role: Role
    let clicks: NXInspectorClicks

    func makeNSView(context: Context) -> NSView {
        let view = MarkView()
        clicks.mark(view, as: role)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { clicks.mark(nsView, as: role) }

    private final class MarkView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The 360pt panel that slides in from the right with one task's details.
struct NextInspector: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let task: Block
    /// Drafts belong to `draftID`, which lags `task` until they are committed.
    @State private var title = SyncedTextDraft()
    @State private var note = SyncedTextDraft()
    @State private var draftID: UUID?
    /// The open popover, and the task it was opened on. The shell reuses this
    /// view for every task, so a popover never carries over to the next one.
    @State private var picker: (section: DetailPicker, taskID: UUID)?
    @State private var lineage = NXLineage()
    /// "Add a note" opened the note, which shows while it has focus or text.
    @State private var addingNote = false
    /// The note just let go keeps its box until the click that ended it is over.
    @State private var holdsNote = false
    @State private var dropTargeted = false
    @State private var clicks = NXInspectorClicks()
    @State private var fields = NXInspectorFields()
    /// The field being written, as its text view reports it.
    @State private var focus: Field?

    typealias Field = NXInspectorText.Role

    private var workbench: Workbench { env.workbench }

    /// A search hit or link that landed in this task's title or note.
    private var reveal: ContentReveal? {
        guard let request = env.navigator.contentReveal, request.taskID == task.id else { return nil }
        return request
    }
    private var readyRevealID: UUID? { env.navigator.isSearchOpen ? nil : reveal?.id }

    var body: some View {
        let list = library.list(task.listID)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let list { NXListGlyph(list: list, size: 12) }
                Text(list?.displayTitle ?? "No list")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NX.ink(0.55))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button { env.navigator.closeTask() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).frame(width: 16, height: 16)
                }
                // As the design's, only its fill shows on hover.
                .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 6,
                                                padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                                                foreground: NX.ink(0.45)))
                .help("Close (Esc)")
                .accessibilityLabel("Close details")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        let ancestors = lineage.ancestors(of: task, store: env.store)
                        if let parent = ancestors.first(where: \.isTask) {
                            NXInspectorParentCrumb(parent: parent)
                                .id(parent.id)
                        }
                        titleRow
                            .id(ContentReveal.Anchor.taskTitle(task.id))
                        properties(list: list)
                        TaskReminderStatus(block: task, attentionOnly: true)
                        // As the design: not two levels down.
                        if ancestors.count < OutlinePolicy.maximumDepth {
                            NXInspectorSubtasks(task: task, showsEmpty: offersSubtasks)
                                .id(task.id)
                        }
                        planCard
                        // As the design, the note shows only when there is one.
                        if showsNote {
                            VStack(alignment: .leading, spacing: 8) {
                                noteBox
                                    .id(ContentReveal.Anchor.taskNote(task.id))
                                TaskNoteLinks(note: task.note)
                            }
                        }
                        NXInspectorFiles(task: task, addsNote: noteAction)
                        activity
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.automatic)
                .task(id: readyRevealID) {
                    // A reminder, a link or a search hit opens the task as
                    // the design's search does, its row keeping the focus
                    // for the keys; a match only brings its field into view.
                    guard readyRevealID != nil, let reveal, !reveal.query.isEmpty else { return }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    if reveal.field == .note {
                        proxy.scrollTo(ContentReveal.Anchor.taskNote(task.id), anchor: .center)
                    } else {
                        proxy.scrollTo(ContentReveal.Anchor.taskTitle(task.id), anchor: .top)
                    }
                }
            }

            HStack(spacing: 6) {
                Button {
                    // Save what is being typed first, so it goes to Trash, and
                    // comes back on Undo, with the task and its subtasks: the
                    // trash is a step of its own, which leaves the text alone.
                    NotificationCenter.default.post(name: .commitPendingTaskTitles, object: nil)
                    workbench.trash([task.id])
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash").font(.system(size: 12.5, weight: .medium))
                        Text("Trash").font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(NXHoverButtonStyle(hover: NX.red.opacity(0.1), radius: 8,
                                                padding: EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9),
                                                foreground: NX.ink(0.6), hoverForeground: NX.redText))
                Spacer(minLength: 8)
                startButton
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }
        }
        .frame(width: 360)
        .frame(maxHeight: .infinity)
        .background(NX.inspector)
        .background(NXInspectorMark(role: .panel, clicks: clicks))
        // Files dropped anywhere on the panel are kept with the task.
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            NXTaskFiles(workbench: env.workbench).drop(providers, on: task.id)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style.accent.opacity(0.5), lineWidth: 1)
                    .background(style.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .leading) { Rectangle().fill(NX.ink(0.1)).frame(width: 0.5) }
        .shadow(color: NX.shadowWarm.opacity(0.1), radius: 17, x: -14)
        .contentShape(Rectangle())
        .onTapGesture {}
        .onAppear {
            load()
            adoptRequestedPicker()
            let env = env
            clicks.install { env.workbench.captureOpen || env.navigator.isSearchOpen || env.navigator.isCommandPaletteOpen }
        }
        .onChange(of: task.id) { _, _ in
            // The shell reuses this view for every task. A field being edited
            // lets go first, as a browser blurs it, so the caret doesn't
            // follow to the next task and the keys act on the row; then the
            // old task's drafts are saved before the new one's load.
            clicks.endEditing()
            focus = nil
            commitTitle()
            commitNote()
            if picker?.taskID != task.id { picker = nil }
            load()
        }
        .onChange(of: task.text) { _, _ in title.receive(Self.title(of: task)) }
        .onChange(of: task.note) { _, _ in note.receive(task.note) }
        .onChange(of: focus) { old, new in
            // Task ▸ Open Details stands down while the note is written,
            // leaving ⌘↩ to finish it.
            workbench.isWritingInspectorNote = new == .note
            if old == .title { commitTitle() }
            if old == .note {
                // A box the click that ended the note leaves empty closes
                // once that click is over, so a button below doesn't move out
                // from under the pointer before it fires on mouse-up.
                holdsNote = showsNote
                commitNote()
                addingNote = false
                clicks.afterClick { holdsNote = false }
            }
        }
        .onChange(of: env.requestedPicker) { _, _ in adoptRequestedPicker() }
        .onReceive(NotificationCenter.default.publisher(for: .commitPendingTaskTitles)) { _ in
            commitTitle()
            commitNote()
        }
        .onDisappear {
            commitTitle()
            commitNote()
            clicks.uninstall()
            workbench.isWritingInspectorNote = false
        }
    }

    /// Whether Subtasks shows before the task has any. The design's Inbox has
    /// no document, so its tasks get none; here they nest in the Inbox's
    /// document, so they do while the Inbox shows as one.
    private var offersSubtasks: Bool {
        guard library.isInbox(task) else { return true }
        return env.navigator.inboxListID.map { env.navigator.listViewMode(for: $0) == .document } ?? false
    }

    private func load() {
        draftID = task.id
        title.reset(to: Self.title(of: task))
        note.reset(to: task.note)
        addingNote = false
        holdsNote = false
    }

    /// The title as written, so an untitled task shows the field's placeholder, as
    /// the design shows its text, rather than the "Untitled" it goes by elsewhere.
    /// On one line, as the title is written.
    private static func title(of task: Block) -> String {
        singleLine(task.text)
    }

    /// A title as it's kept: one line, as a list document line is, each break
    /// a space, and trimmed.
    private static func singleLine(_ text: String) -> String {
        NXInspectorTextView.oneLine(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The task the drafts were loaded from. Unlike `store.block(id:)` this
    /// also finds it in Trash, so when a menu or shortcut trashes the open
    /// task, what was typed goes with it and comes back on Undo or Restore.
    private var draftTarget: Block? {
        guard let block = env.store.blockIncludingTrash(id: draftID), block.modelContext != nil else { return nil }
        return block
    }

    /// Writes only what the user typed, to the task the draft was loaded
    /// from, as one Undo step with a Changes entry.
    private func commitTitle() {
        guard let target = draftTarget else { return }
        if let edited = title.editedValue(normalize: Self.singleLine),
           !edited.isEmpty, edited != Self.title(of: target) {
            workbench.setTitle(edited, of: target)
        }
        title.reset(to: Self.title(of: target))
    }

    /// As the list document commits a note: trailing space goes, and an
    /// emptied note closes there too.
    private func commitNote() {
        guard let target = draftTarget else { return }
        if let edited = note.editedValue(normalize: Workbench.committedNote), edited != target.note {
            workbench.setNote(edited, of: target)
        }
        note.reset(to: target.note)
    }

    /// ⇧⌘D and ⇧⌘L open their popover on the inspected task.
    private func adoptRequestedPicker() {
        guard let requested = env.requestedPicker else { return }
        env.requestedPicker = nil
        openPicker(requested)
    }

    // MARK: Title

    private var titleRow: some View {
        let closing = workbench.closing[task.id]
        return HStack(alignment: .top, spacing: 10) {
            // As the design's, it only fills: the list row keeps the pop.
            NXCheckbox(filled: task.isCompleted || closing != nil, closing: closing, priority: task.priority,
                       title: task.displayTitle, size: 18, pops: false) {
                workbench.toggle(task.id)
            }
            .padding(.top, 3)
            // The design's 600 18/1.3, grey and struck through once done.
            NXInspectorText(role: .title, text: $title.value, done: task.isCompleted,
                            caretColor: env.settings.accent.editorColor, fields: fields,
                            onFocus: { focused(.title, $0) },
                            onSwitch: showsNote ? { fields.write(.note) } : nil)
                .background(NXInspectorMark(role: .field, clicks: clicks))
        }
    }

    // MARK: Properties

    private func properties(list: TaskList?) -> some View {
        let recurrence = task.recurrence
        // Labels sit centred against their values, as in the design's grid.
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 11) {
            GridRow {
                propertyLabel("List")
                VStack(alignment: .leading, spacing: 4) {
                    Text(list?.displayTitle ?? "No list")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NX.ink)
                        .lineLimit(1)
                        .padding(.bottom, 2)
                    NXFlow(spacing: 4) {
                        ForEach(library.lists, id: \.id) { option in
                            let current = option.id == task.listID
                            // The design's 13/1 glyph in 4/7 padding.
                            NXInspectorPill(isOn: current, padding: EdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 7), line: 13) {
                                if !current { workbench.move([task.id], to: option.id, quiet: true) }
                            } label: {
                                NXListGlyph(list: option, size: 13)
                            }
                            .help(option.displayTitle)
                            // Named, not read as its emoji.
                            .accessibilityLabel(current ? option.displayTitle : "Move to \(option.displayTitle)")
                            .accessibilityAddTraits(current ? .isSelected : [])
                        }
                    }
                }
            }
            GridRow {
                propertyLabel("Due")
                // A date that isn't one of the fixed choices comes first, as
                // its own pill; it opens the picker rather than rescheduling.
                let options = dueOptions
                let customLabel = options.count > 4 ? options.first?.label : nil
                NXFlow(spacing: 4) {
                    ForEach(options, id: \.label) { option in
                        let custom = option.label == customLabel
                        let pill = NXInspectorPill(isOn: isDue(option.offset)) {
                            if custom { openPicker(.due) }
                            else { workbench.schedule([task.id], offset: option.offset) }
                        } label: {
                            Text(option.label)
                        }
                        if custom { pill.help("Date and time (⇧⌘D)") } else { pill }
                    }
                    // Native addition: the design has no picker. It wraps with the
                    // pills, as the design's row already does at this width.
                    NXInspectorPill(isOn: false) { openPicker(.due) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar").font(.system(size: 10.5, weight: .medium))
                            if task.includesTime, let due = task.dueDate { Text(NXFormat.clock(due)).monospacedDigit() }
                        }
                    }
                    .help("Date and time (⇧⌘D)")
                    .accessibilityLabel("Due date and time")
                }
                .popover(isPresented: pickerBinding(.due), arrowEdge: .bottom) { schedulePopover(.due) }
            }
            GridRow {
                propertyLabel("Repeat")
                NXInspectorPill(isOn: recurrence != nil) { openPicker(.repeatRule) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "repeat").font(.system(size: 10.5, weight: .medium))
                        Text(recurrence?.displayText ?? "Never")
                    }
                }
                .help(recurrence?.displayText ?? "Repeat this task")
                .popover(isPresented: pickerBinding(.repeatRule), arrowEdge: .bottom) { schedulePopover(.repeatRule) }
            }
            GridRow {
                propertyLabel("Reminder")
                NXInspectorPill(isOn: task.reminderAt != nil) { openPicker(.reminder) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bell").font(.system(size: 10.5, weight: .medium))
                        // A timed task with none of its own reminds you at its due time.
                        Text(task.reminderAt.map { NXFormat.dueAndClock($0) }
                            ?? (ReminderPicker.dueTimeReminder(of: task) == nil ? "None" : "At the due time"))
                    }
                }
                .popover(isPresented: pickerBinding(.reminder), arrowEdge: .bottom) { schedulePopover(.reminder) }
            }
            GridRow {
                propertyLabel("Priority")
                HStack(spacing: 4) {
                    ForEach([TaskPriority.none, .low, .medium, .high], id: \.self) { priority in
                        let on = task.priority == priority
                        NXInspectorPill(isOn: on) { workbench.setPriority(task.id, priority) } label: {
                            HStack(spacing: 5) {
                                // As the design's dot, it changes at once while the pill fades.
                                Circle()
                                    .animation(nil) { $0.foregroundStyle(on ? .white : Self.priorityColor(priority)) }
                                    .frame(width: 6, height: 6)
                                Text(Self.priorityTitle(priority))
                            }
                        }
                    }
                }
            }
            GridRow {
                propertyLabel("Labels")
                NXFlow(spacing: 4) {
                    ForEach(library.labels, id: \.id) { label in
                        let on = task.labelIDs.contains(label.id)
                        let color = label.nxColor
                        Button { workbench.toggleLabel(task.id, labelID: label.id) } label: {
                            // 600 11/1, as NXInspectorPill's line.
                            Text("#\(label.name)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(on ? .white : color)
                                .frame(height: 11)
                                .padding(.vertical, 5)
                                .padding(.horizontal, 8)
                                // The design's `background 140ms ease`; the text's colour changes at once.
                                .animation(NX.cssEase(140)) {
                                    $0.background(on ? color : color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    NXInspectorPill(isOn: false) { openPicker(.labels) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .medium))
                            if library.labels.isEmpty { Text("Add label") }
                        }
                    }
                    .help("Find or create a label (⇧⌘L)")
                    .accessibilityLabel("Edit labels")
                    .popover(isPresented: pickerBinding(.labels), arrowEdge: .bottom) {
                        LabelPicker(block: task).id(task.id).environment(env)
                    }
                }
            }
            GridRow {
                propertyLabel("Starred")
                Button { workbench.star([task.id]) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: task.isStarred ? "star.fill" : "star")
                            .font(.system(size: 11.5, weight: task.isStarred ? .semibold : .medium))
                        Text(task.isStarred ? "Starred" : "Not starred")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    // The design's 13px star sets the line, over its 11.5/1 text.
                    .frame(height: 13)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    // Built on the design's pill, it fades as the pill does.
                    .modifier(NXInspectorPillFade(isOn: task.isStarred, on: (NX.amberText, NX.amber.opacity(0.16)),
                                                  off: (NX.ink(0.66), NX.ink(0.05))))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Star (F)")
            }
        }
    }

    private func openPicker(_ section: DetailPicker) { picker = (section, task.id) }

    /// One popover per row; the schedule rows each open the shared picker on their section.
    private func pickerBinding(_ section: DetailPicker) -> Binding<Bool> {
        Binding(get: { picker?.section == section && picker?.taskID == task.id },
                set: { if !$0, picker?.section == section { picker = nil } })
    }

    private func schedulePopover(_ section: DetailPicker) -> some View {
        // Staged input belongs to the task the popover was opened on.
        TaskSchedulePicker(block: task, initialSection: section)
            .id(task.id)
            .environment(env)
    }

    private func propertyLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(NX.ink(0.45))
            .frame(width: 78, alignment: .leading)
            .gridColumnAlignment(.leading)
    }

    /// The coming Monday, `Store.nextWeekDay`, so it never equals Tomorrow.
    private var nextWeekOffset: Int { NXFormat.nextWeekOffset() }

    private var dueOptions: [(label: String, offset: Int?)] {
        var options: [(String, Int?)] = [("Today", 0), ("Tomorrow", 1), ("Next week", nextWeekOffset), ("None", nil)]
        if let due = task.dueDate {
            let offset = NXFormat.dayOffset(due)
            if ![0, 1, nextWeekOffset].contains(offset) { options.insert((NXFormat.dueLabel(due), offset), at: 0) }
        }
        return options
    }

    private func isDue(_ offset: Int?) -> Bool {
        guard let due = task.dueDate else { return offset == nil }
        return offset == NXFormat.dayOffset(due)
    }

    static func priorityColor(_ priority: TaskPriority) -> Color {
        NX.priorityStroke(priority) ?? NX.ink(0.25)
    }

    static func priorityTitle(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "None"
        case .low: "Low"
        case .medium: "Med"
        case .high: "High"
        }
    }

    // MARK: Plan card

    private var planCard: some View {
        let planned = workbench.isPlanned(task)
        let estimate = task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : env.workbench.defaultEstimate
        // The slot line's 500 11/1.4.
        let slotLeading = 11 * 1.4 - NX.lineHeight(11)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // The switch speaks for the row.
                Image(systemName: "calendar.badge.clock").font(.system(size: 13, weight: .medium)).foregroundStyle(style.accent)
                    .accessibilityHidden(true)
                Text("Plan for today").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(NX.ink)
                    .accessibilityHidden(true)
                Spacer(minLength: 6)
                NXToggle(isOn: planned, label: "Plan for today") { workbench.plan([task.id]) }
                    .disabled(task.isCompleted)
            }
            // Planning skips completed tasks, so the switch says so. The row
            // carries the tooltip, which a disabled switch wouldn't show.
            .opacity(task.isCompleted ? 0.45 : 1)
            .contentShape(Rectangle())
            .help(task.isCompleted ? "Completed tasks can’t be planned" : "Plan for today (P)")
            HStack(spacing: 8) {
                Text("Estimate").font(.system(size: 11.5, weight: .medium)).foregroundStyle(NX.ink(0.5))
                Spacer(minLength: 6)
                NXStepButton(icon: "minus", label: "Shorter estimate") { workbench.setEstimate(task.id, delta: -5) }
                // Like the design's 44pt cell, a wider value overflows it evenly.
                Text("\(estimate) min")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(NX.ink)
                    .contentTransition(.numericText())
                    .fixedSize()
                    .frame(width: 44)
                NXStepButton(icon: "plus", label: "Longer estimate") { workbench.setEstimate(task.id, delta: 5) }
            }
            .padding(.top, 11)
            Text(slotText)
                .font(.system(size: 11, weight: .medium))
                .lineSpacing(slotLeading)
                .foregroundStyle(NX.ink(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, slotLeading / 2)
                .padding(.top, 9)
            // Its popover, sheet and expansion belong to one task.
            NXInspectorPlanOptions(task: task)
                .id(task.id)
                .padding(.top, 9)
        }
        .padding(12)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(NX.ink(0.1), lineWidth: 0.5))
    }

    /// Reads a slot the calendar grid draws for the task, as the design reads
    /// its placement, past or done ones too: see `CalendarWeek.shownSlot`.
    private var slotText: String {
        guard let placement = CalendarWeek.shownSlot(of: task.id, occurrenceID: task.occurrenceID, in: env.calendar.visibleBlocks,
                                                     now: .now, calendar: env.settings.calendar) else {
            return "Not in the calendar yet — ⌘K › Find a slot"
        }
        let offset = NXFormat.dayOffset(placement.start)
        let day = offset == 0 ? "today" : placement.start.formatted(.dateTime.weekday(.abbreviated).day())
        return "In the calendar \(day), \(NXFormat.clock(placement.start))–\(NXFormat.clock(placement.end))"
    }

    // MARK: Note & activity

    /// A note, or one being written or revealed; else "Add a note" stands in.
    private var showsNote: Bool {
        !note.value.isEmpty || !task.note.isEmpty || addingNote || holdsNote || focus == .note || reveal?.field == .note
    }

    /// What "Add a note" does while it stands in for the note.
    private var noteAction: (() -> Void)? {
        showsNote ? nil : { addingNote = true }
    }

    /// The title or note took the keyboard, or let it go.
    private func focused(_ field: Field, _ isFocused: Bool) {
        if isFocused { focus = field } else if focus == field { focus = nil }
    }

    private var noteBox: some View {
        // The design's 400 13/1.55 in 10/12 padding. Opened by "Add a note"
        // on this task, not one the panel is moving on from, it takes the keyboard.
        NXInspectorText(role: .note, text: $note.value, caretColor: env.settings.accent.editorColor,
                        fields: fields, takesKeyboard: addingNote && draftID == task.id,
                        onFocus: { focused(.note, $0) },
                        onSwitch: { fields.write(.title) })
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(NX.ink(focus == .note ? 0.05 : 0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            // A click anywhere in the box is in the note, as in a textarea.
            .background(NXInspectorMark(role: .field, clicks: clicks))
    }

    private var activity: some View {
        let captured = library.isInbox(task) ? "Inbox" : library.list(task.listID)?.displayTitle ?? "a list"
        // Newest first, like the log, with the capture always last.
        let entries = workbench.entries(for: task.id)
        return VStack(alignment: .leading, spacing: 0) {
            NXInspectorHeading(title: "Activity") { EmptyView() }
                .padding(.bottom, 8)
            // Each row, the capture's too, plays the design's liftIn as it
            // appears: with the panel, for another task or as a change logs
            // it. A row Undo takes back, or the last task's, goes at once, as
            // the design's does.
            ForEach(entries) { entry in
                activityRow(icon: entry.icon, text: entry.label, date: entry.at)
                    .modifier(NXLiftIn(animation: NX.cssEase(220)))
                    .transition(.identity)
            }
            activityRow(icon: "plus.circle", text: "Captured in \(captured)", date: task.createdAt)
                .modifier(NXLiftIn(animation: NX.cssEase(220)))
                .transition(.identity)
                .id(task.id)
            NXInspectorHistory(task: task)
                .id(task.id)
                .padding(.top, 6)
        }
    }

    private func activityRow(icon: String, text: String, date: Date) -> some View {
        // 400 12/1.4, which sets the row's height, as in the design.
        let leading = 12 * 1.4 - NX.lineHeight(12)
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: icon).font(.system(size: 11.5, weight: .medium)).foregroundStyle(NX.ink(0.4)).frame(width: 14)
            Text(text).font(.system(size: 12)).lineSpacing(leading).foregroundStyle(NX.ink(0.66))
                .padding(.vertical, leading / 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            // "just now" moves on while the panel stays open.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(NXFormat.relative(date, now: context.date)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(NX.ink(0.36))
            }
        }
        .padding(.vertical, 5)
    }

    private var startButton: some View {
        // Work on this task, running or paused, reads "Working…" as the
        // design's does; Resume is the notch's.
        let working = workbench.workTask?.id == task.id
        return Button {
            if !working { workbench.startWork(task.id) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: working ? "timer" : "play.fill").font(.system(size: 12, weight: .medium))
                Text(working ? "Working…" : "Start working").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(working ? NX.ink(0.55) : .white)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(working ? NX.ink(0.06) : style.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(task.isCompleted)
    }
}

/// The inspector's small toggle pills: accent when on, faint grey when off.
/// As the design's, they have no hover; only choosing one changes its fill.
struct NXInspectorPill<Label: View>: View {
    @Environment(\.nextStyle) private var style
    let isOn: Bool
    var padding = EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
    /// The design's line box, 11.5/1: the label is this tall, and text or a
    /// symbol running taller overflows it evenly, as CSS lays out line-height 1.
    /// A fixed box, not half-leading, as SF Symbols stand taller than the
    /// design's icons (a 10.5pt bell is 13pt).
    var line: CGFloat = 11.5
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .frame(height: line)
                .padding(padding)
                .modifier(NXInspectorPillFade(isOn: isOn, on: (.white, style.accent), off: (NX.ink(0.66), NX.ink(0.05))))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The design's pill `transition: background 140ms ease, color 140ms ease`:
/// the text's and the fill's colours fade, while the label, and the width it
/// takes, change at once, as CSS moves neither. The colours follow in a step
/// of their own, since an animation scoped to them wouldn't reach the text.
private struct NXInspectorPillFade: ViewModifier {
    let isOn: Bool
    let on: (text: Color, fill: Color)
    let off: (text: Color, fill: Color)
    /// The colours shown, `isOn`'s once it has changed.
    @State private var shown: Bool

    init(isOn: Bool, on: (text: Color, fill: Color), off: (text: Color, fill: Color)) {
        self.isOn = isOn
        self.on = on
        self.off = off
        _shown = State(initialValue: isOn)
    }

    func body(content: Content) -> some View {
        let colors = shown ? on : off
        content
            .foregroundStyle(colors.text)
            .background(colors.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onChange(of: isOn) { _, now in withAnimation(NX.cssEase(140)) { shown = now } }
    }
}
