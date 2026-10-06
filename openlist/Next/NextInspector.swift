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

    /// A click on text or a scroller goes as AppKit sends it: in the field it
    /// places the caret, another field takes the keys, and scrolling leaves
    /// the edit be. One in the box around a field puts the caret there;
    /// anywhere else it ends the edit.
    private func handle(_ event: NSEvent) {
        guard let window = panel?.window, event.window === window, !covered() else { return }
        let point = event.locationInWindow
        // Only what shows of a box counts, not the part scrolled under the bars.
        let area = areas.allObjects.lazy.filter { $0.window === window }
            .map { Self.shownFrame(of: $0) }.first { $0.contains(point) }
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
        let frame = Self.shownFrame(of: field)
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

    /// What shows of `view`, in the window. A view no longer clips to its
    /// bounds, so its visible rect can reach past them, over the whole
    /// scroll view it's in; only the part inside its bounds counts.
    private static func shownFrame(of view: NSView) -> CGRect {
        view.convert(view.visibleRect.intersection(view.bounds), to: nil)
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

/// One task's details, as Superlist sets them: a slim bar, the title, one
/// quiet line of details, then the note as the task's body, its subtasks,
/// plan, files and activity. A 360pt panel that slides in from the right,
/// or, opened out, a page in the screen's place, in the column and margins
/// every screen reads in.
struct NextInspector: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    static let width: CGFloat = 360
    /// The widest the page's note runs, so its lines stay comfortable to
    /// read; everything else on the page runs to the column's edge, as a
    /// screen's rows and controls do.
    static let noteMeasure: CGFloat = 720
    let task: Block
    /// Opened out over the main pane, in the screen's place.
    var isPage = false
    /// Drafts belong to `draftID`, which lags `task` until they are committed.
    @State private var title = SyncedTextDraft()
    @State private var note = SyncedTextDraft()
    @State private var draftID: UUID?
    /// The open popover, and the task it was opened on. The shell reuses this
    /// view for every task, so a popover never carries over to the next one.
    @State private var picker: (section: DetailPicker, taskID: UUID)?
    @State private var lineage = NXLineage()
    @State private var dropTargeted = false
    @State private var clicks = NXInspectorClicks()
    @State private var fields = NXInspectorFields()
    /// The field being written, as its text view reports it.
    @State private var focus: Field?
    /// Activity opens on request, and stays open from task to task while
    /// the panel does.
    @State private var showsActivity = false
    /// The page rises in as a screen does.
    @State private var appeared = false

    typealias Field = NXInspectorText.Role

    private var workbench: Workbench { env.workbench }

    /// A search hit or link that landed in this task's title or note.
    private var reveal: ContentReveal? {
        guard let request = env.navigator.contentReveal, request.taskID == task.id else { return nil }
        return request
    }
    private var readyRevealID: UUID? { env.navigator.isSearchOpen ? nil : reveal?.id }

    var body: some View {
        VStack(spacing: 0) {
            if !isPage {
                topBar
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    // The page's 26/40/120, as `NXPage` pads every screen.
                    column {
                        content
                            .padding(.top, isPage ? 26 : 18)
                            .padding(.bottom, isPage ? 120 : 24)
                    }
                    .offset(y: isPage && !appeared ? 6 : 0)
                    .opacity(isPage && !appeared ? 0 : 1)
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

            column { footer }
                .padding(.vertical, 10)
                .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }
        }
        .frame(width: isPage ? nil : Self.width)
        .frame(maxWidth: isPage ? .infinity : nil, maxHeight: .infinity)
        // The page is the paper the screen was on.
        .background(isPage ? NX.paper : NX.inspector)
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
        // Docked beside the page, it's divided from it rather than floating over it.
        .overlay(alignment: .leading) { if !isPage { Rectangle().fill(NX.ink(0.1)).frame(width: 0.5) } }
        .contentShape(Rectangle())
        .onTapGesture {}
        .onAppear {
            load()
            adoptRequestedPicker()
            let env = env
            clicks.install { env.workbench.captureOpen || env.navigator.isSearchOpen || env.navigator.isCommandPaletteOpen }
            if isPage { withAnimation(style.ease(260)) { appeared = true } }
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
            if old == .note { commitNote() }
        }
        .onChange(of: env.requestedPicker) { _, _ in adoptRequestedPicker() }
        .onReceive(NotificationCenter.default.publisher(for: .commitPendingEditorDrafts)) { _ in
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

    /// The page sets its parts in the column and margins every screen has
    /// (`NXPage`), so it opens where the screen's own header was; the panel,
    /// in its own 16pt margins.
    @ViewBuilder private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if isPage {
            NXReadingColumnView(measure: NXPageMeasure.reading + 80) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 40)
            }
        } else {
            content().padding(.horizontal, 16)
        }
    }

    /// The details, then the note under a hairline as the task's body, then
    /// the sections.
    private var content: some View {
        let ancestors = lineage.ancestors(of: task, store: env.store)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: isPage ? 12 : 10) {
                if let parent = ancestors.first(where: \.isTask) {
                    NXInspectorParentCrumb(parent: parent)
                        .id(parent.id)
                }
                titleRow
                    .id(ContentReveal.Anchor.taskTitle(task.id))
                detailsLine
                TaskReminderStatus(block: task, attentionOnly: true)
            }
            Rectangle().fill(NX.ink(0.07)).frame(height: 0.5)
                .padding(.top, isPage ? 20 : 16)
            VStack(alignment: .leading, spacing: 8) {
                noteBox
                    .id(ContentReveal.Anchor.taskNote(task.id))
                TaskNoteLinks(note: task.note)
            }
            .padding(.top, isPage ? 16 : 12)
            VStack(alignment: .leading, spacing: 28) {
                // As the design: not two levels down.
                if ancestors.count < OutlinePolicy.maximumDepth {
                    NXInspectorSubtasks(task: task, showsEmpty: offersSubtasks)
                        .id(task.id)
                }
                // Its slider, popover, sheet and expansion belong to one task.
                NXInspectorPlan(task: task, isPage: isPage)
                    .id(task.id)
                NXInspectorFiles(task: task)
                activity
            }
            .padding(.top, 24)
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

    // MARK: Bar

    /// The panel's slim bar, as Superlist's: close and Complete lead, the
    /// page and the task's menu trail.
    private var topBar: some View {
        HStack(spacing: 6) {
            closeButton
            completeButton
            Spacer(minLength: 6)
            pageButton
            moreMenu
        }
    }

    /// The page's, on its title's first line, as a screen's header keeps its
    /// controls at the trailing edge.
    private var pageControls: some View {
        HStack(spacing: 4) {
            completeButton
                .padding(.trailing, 4)
            pageButton
            moreMenu
            closeButton
        }
    }

    private var closeButton: some View {
        headerButton("xmark", label: "Close details", help: isPage ? "Close details" : "Close details (Esc)") {
            env.navigator.closeTask()
        }
    }

    /// Opens the task out over the main pane, or puts it back; Esc puts it back too.
    private var pageButton: some View {
        headerButton(isPage ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                     label: isPage ? "Collapse details" : "Expand details",
                     help: isPage ? "Collapse details (Esc)" : "Expand details (⇧⌘↩)") {
            workbench.toggleTaskPage()
        }
    }

    /// The row's own menu, for everything the bar doesn't show.
    private var moreMenu: some View {
        Menu {
            NXTaskMenu(ids: [task.id])
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium)).frame(width: 16, height: 16)
        }
        .menuStyle(.button)
        .buttonStyle(Self.headerStyle)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel("More actions")
    }

    /// Complete, grey until the task is done, then a green tint: done is a
    /// status, and the title strikes through with it. Ticking it runs the
    /// rows' dwell, which a second click takes back.
    private var completeButton: some View {
        let done = task.isCompleted || workbench.closing[task.id] != nil
        return Button { workbench.toggle(task.id) } label: {
            HStack(spacing: 5) {
                Image(systemName: done ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 12, weight: .medium))
                Text(done ? "Completed" : "Complete")
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(height: 16)
        }
        .buttonStyle(NXHoverButtonStyle(hover: done ? NX.green.opacity(0.18) : NX.ink(0.08),
                                        rest: done ? NX.green.opacity(0.12) : NX.ink(0.05), radius: 7,
                                        padding: EdgeInsets(top: 4, leading: 7, bottom: 4, trailing: 9),
                                        foreground: done ? NX.greenText : NX.textSecondary,
                                        hoverForeground: done ? NX.greenText : NX.ink))
        .fixedSize()
        .help(done ? "Reopen (⌘D)" : "Mark as done (⌘D)")
        .accessibilityLabel(done ? "Reopen" : "Mark as done")
        .accessibilityValue(done ? "Completed" : "Open")
    }

    /// A symbol in the bar; as the design's close, only its fill shows on hover.
    private func headerButton(_ icon: String, label: String, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .medium)).frame(width: 16, height: 16)
        }
        .buttonStyle(Self.headerStyle)
        .help(help)
        .accessibilityLabel(label)
    }

    private static let headerStyle = NXHoverButtonStyle(hover: NX.ink(0.06), radius: 6,
                                                        padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                                                        foreground: NX.ink(0.5), hoverForeground: NX.ink)

    // MARK: Title

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 16) {
            // The panel's 600 20/1.25, or a screen title's on the page;
            // grey and struck through once done.
            NXInspectorText(role: .title, text: $title.value, done: task.isCompleted, large: isPage, serif: serifTitle,
                            caretColor: env.settings.accent.editorColor, fields: fields,
                            onFocus: { focused(.title, $0) },
                            onSwitch: { fields.write(.note) })
                .background(NXInspectorMark(role: .field, clicks: clicks))
            if isPage {
                // Centred on the title's 24pt-high first line.
                let line = NXInspectorTextView.metrics(.title, large: true, serif: serifTitle).line
                pageControls.padding(.top, max(0, (line - 24) / 2))
            }
        }
    }

    /// The page's title in the screens' serif, while they're set in it.
    private var serifTitle: Bool { isPage && style.serifTitles }

    // MARK: Details

    /// The task's details as one quiet line under its title, as Superlist
    /// sets them: each a grey symbol with its value, which opens its picker.
    /// One not set yet is the symbol alone, fainter, named under the
    /// pointer. Colour is kept for what it says: a late date, the
    /// priority's flag, the list's glyph, the labels' dots and the star,
    /// which shows only once the task has it.
    private var detailsLine: some View {
        let due = task.dueDate
        let late = due.map { !task.isCompleted && NXFormat.dayOffset($0) < 0 } ?? false
        let dueText = due.map { task.includesTime ? NXFormat.dueAndClock($0) : NXFormat.dueLabel($0) }
        // A timed task with no reminder of its own reminds you at the time
        // the date beside it shows: the filled bell says so.
        let reminderText = task.reminderAt.map { NXFormat.dueAndClock($0) }
        let atDueTime = reminderText == nil && ReminderPicker.dueTimeReminder(of: task) != nil
        let labels = library.labels.filter { task.labelIDs.contains($0.id) }
        return NXFlow(spacing: 2) {
            detailButton(icon: late ? "exclamationmark.circle" : "calendar", value: dueText,
                         foreground: late ? NX.redText : nil,
                         help: "Due date (⇧⌘D)", label: dueText.map { "Due \($0)" } ?? "Add a due date") {
                openPicker(.due)
            }
            .popover(isPresented: pickerBinding(.due), arrowEdge: .bottom) { schedulePopover(.due) }
            listMenu
            Button { openPicker(.labels) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tag").font(.system(size: 11, weight: .medium))
                    ForEach(labels, id: \.id) { label in
                        HStack(spacing: 4) {
                            Circle().fill(label.nxColor).frame(width: 6, height: 6)
                            Text(label.name).lineLimit(1)
                        }
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .frame(height: 16)
            }
            .buttonStyle(Self.detailStyle(set: !labels.isEmpty))
            .help("Labels (⇧⌘L)")
            .accessibilityLabel(labels.isEmpty ? "Add labels" : "Labels: \(labels.map(\.name).joined(separator: ", "))")
            .popover(isPresented: pickerBinding(.labels), arrowEdge: .bottom) {
                LabelPicker(block: task).id(task.id).environment(env)
            }
            detailButton(icon: "repeat", value: task.recurrence?.displayText, help: "Repeat",
                         label: task.recurrence.map { "Repeats \($0.displayText)" } ?? "Make it repeat") {
                openPicker(.repeatRule)
            }
            .popover(isPresented: pickerBinding(.repeatRule), arrowEdge: .bottom) { schedulePopover(.repeatRule) }
            detailButton(icon: atDueTime ? "bell.fill" : "bell", value: reminderText, set: atDueTime,
                         help: atDueTime ? "Reminds you at the due time" : "Reminder",
                         label: reminderText.map { "Reminder \($0)" } ?? (atDueTime ? "Reminds you at the due time" : "Add a reminder")) {
                openPicker(.reminder)
            }
            .popover(isPresented: pickerBinding(.reminder), arrowEdge: .bottom) { schedulePopover(.reminder) }
            priorityMenu
            // Only a starred task shows its star; ⋯ stars one.
            if task.isStarred {
                Button { workbench.star([task.id]) } label: {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NX.amber)
                        .frame(height: 16)
                }
                .buttonStyle(Self.detailStyle(set: true))
                .help("Unstar (⇧⌘S)")
                .accessibilityLabel("Starred")
                .accessibilityHint("Unstars the task")
            }
        }
        // The symbols line up with the title.
        .padding(.leading, -6)
    }

    /// The list, which moves the task to another.
    private var listMenu: some View {
        let list = library.list(task.listID)
        return Menu {
            ForEach(library.lists, id: \.id) { option in
                NXListMenuButton(list: option) { workbench.move([task.id], to: option.id, quiet: true) }
                    .disabled(option.id == task.listID)
            }
        } label: {
            HStack(spacing: 5) {
                if let list { NXListGlyph(list: list, size: 11) } else { Image(systemName: "tray").font(.system(size: 11, weight: .medium)) }
                Text(list?.displayTitle ?? "No list").lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .frame(height: 16)
        }
        .menuStyle(.button)
        .buttonStyle(Self.detailStyle(set: true))
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Move to another list")
        .accessibilityLabel("List: \(list?.displayTitle ?? "No list")")
        .accessibilityHint("Moves the task to another list")
    }

    /// The priority's flag, in its colour once it has one; a menu of the four.
    private var priorityMenu: some View {
        let priority = task.priority
        return Menu {
            ForEach([TaskPriority.high, .medium, .low, .none], id: \.self) { option in
                Button { workbench.setPriority(task.id, option) } label: {
                    if option == priority {
                        Label(Self.priorityTitle(option), systemImage: "checkmark")
                    } else {
                        Text(Self.priorityTitle(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: priority == .none ? "flag" : "flag.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(priority == .none ? AnyShapeStyle(.foreground) : AnyShapeStyle(Self.priorityColor(priority)))
                if priority != .none { Text(Self.priorityTitle(priority)) }
            }
            .font(.system(size: 12, weight: .medium))
            .frame(height: 16)
        }
        .menuStyle(.button)
        .buttonStyle(Self.detailStyle(set: priority != .none))
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Priority")
        .accessibilityLabel(priority == .none ? "Set a priority" : "\(Self.priorityTitle(priority)) priority")
    }

    /// One of the details: its symbol, and its value once it has one.
    private func detailButton(icon: String, value: String?, set: Bool = false, foreground: Color? = nil,
                              help: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                if let value { Text(value).lineLimit(1) }
            }
            .font(.system(size: 12, weight: .medium))
            .frame(height: 16)
        }
        .buttonStyle(Self.detailStyle(set: set || value != nil, foreground: foreground))
        .help(help)
        .accessibilityLabel(label)
    }

    /// Grey words on nothing, as Superlist's, that darken over a faint fill
    /// under the pointer; a detail not set yet is fainter still.
    private static func detailStyle(set: Bool, foreground: Color? = nil) -> NXHoverButtonStyle {
        NXHoverButtonStyle(hover: NX.ink(0.06), radius: 6, padding: EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6),
                           foreground: foreground ?? (set ? NX.textTertiary : NX.textQuaternary),
                           hoverForeground: foreground ?? NX.ink)
    }

    private func openPicker(_ section: DetailPicker) {
        picker = (section, task.id)
    }

    /// One popover per detail; the schedule ones each open the shared picker on their section.
    private func pickerBinding(_ section: DetailPicker) -> Binding<Bool> {
        Binding(get: { picker?.section == section && picker?.taskID == task.id },
                set: {
                    guard !$0, picker?.section == section else { return }
                    picker = nil
                })
    }

    private func schedulePopover(_ section: DetailPicker) -> some View {
        // Staged input belongs to the task the popover was opened on.
        TaskSchedulePicker(block: task, initialSection: section)
            .id(task.id)
            .environment(env)
    }

    static func priorityColor(_ priority: TaskPriority) -> Color {
        NX.priorityStroke(priority) ?? NX.ink(0.25)
    }

    static func priorityTitle(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "No priority"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    // MARK: Note & activity

    /// The title or note took the keyboard, or let it go.
    private func focused(_ field: Field, _ isFocused: Bool) {
        if isFocused { focus = field } else if focus == field { focus = nil }
    }

    /// The task's body, always there to read or start, set as a page's text
    /// rather than in a field: 400 13.5/1.6 in the reading ink, or the
    /// page's 14.5/1.65, with "Add notes…" while there's none. The room
    /// under it is the note's too, as a page's, so a click there writes.
    private var noteBox: some View {
        NXInspectorText(role: .note, text: $note.value, large: isPage, caretColor: env.settings.accent.editorColor,
                        fields: fields,
                        onFocus: { focused(.note, $0) },
                        onSwitch: { fields.write(.title) })
            .frame(maxWidth: isPage ? Self.noteMeasure : .infinity, minHeight: isPage ? 140 : 84, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A click anywhere in that room is in the note, as in a textarea.
            .background(NXInspectorMark(role: .field, clicks: clicks))
    }

    private var activity: some View {
        let captured = library.isInbox(task) ? "Inbox" : library.list(task.listID)?.displayTitle ?? "a list"
        // Newest first, like the log, with the capture always last.
        let entries = workbench.entries(for: task.id)
        return VStack(alignment: .leading, spacing: 0) {
            NXInspectorFold(title: "Activity", isExpanded: $showsActivity)
            if showsActivity {
                // Each row, the capture's too, plays the design's liftIn as it
                // appears: with the section, for another task or as a change
                // logs it. A row Undo takes back, or the last task's, goes at
                // once, as the design's does.
                VStack(alignment: .leading, spacing: 0) {
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
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
    }

    private func activityRow(icon: String, text: String, date: Date) -> some View {
        // 400 12/1.4, which sets the row's height, as in the design.
        let leading = 12 * 1.4 - NX.lineHeight(12)
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: icon).font(.system(size: 11.5, weight: .medium)).foregroundStyle(NX.ink(0.4)).frame(width: 14)
            Text(text).font(.system(size: 12)).lineSpacing(leading).foregroundStyle(NX.textSecondary)
                .padding(.vertical, leading / 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            // "just now" moves on while the panel stays open.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(NXFormat.relative(date, now: context.date)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(NX.textQuaternary)
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: Footer

    /// Trash and Attach as symbols, named under the pointer, and the one
    /// primary action, Start working.
    private var footer: some View {
        HStack(spacing: 2) {
            Button {
                // Save what is being typed first, so it goes to Trash, and
                // comes back on Undo, with the task and its subtasks: the
                // trash is a step of its own, which leaves the text alone.
                NotificationCenter.default.post(name: .commitPendingEditorDrafts, object: nil)
                workbench.trash([task.id])
            } label: {
                Image(systemName: "trash").font(.system(size: 12.5, weight: .medium)).frame(width: 16, height: 16)
            }
            .buttonStyle(NXHoverButtonStyle(hover: NX.red.opacity(0.1), radius: 8,
                                            padding: EdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7),
                                            foreground: NX.ink(0.5), hoverForeground: NX.redText))
            .help("Move to Trash")
            .accessibilityLabel("Move to Trash")
            Button { NXTaskFiles(workbench: workbench).choose(for: task) } label: {
                Image(systemName: "paperclip").font(.system(size: 12.5, weight: .medium)).frame(width: 16, height: 16)
            }
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 8,
                                            padding: EdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7),
                                            foreground: NX.ink(0.5), hoverForeground: NX.ink))
            .help("Attach files")
            .accessibilityLabel("Attach files to task")
            Spacer(minLength: 8)
            startButton
        }
        // The symbols line up with the text above them.
        .padding(.leading, -7)
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
            .foregroundStyle(working ? NX.textTertiary : .white)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(working ? NX.ink(0.06) : style.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(task.isCompleted)
    }
}

/// The inspector's small toggle pills: a faint accent tint when on, faint
/// grey when off. As the design's, they have no hover; only choosing one
/// changes its fill.
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
                .modifier(NXInspectorPillFade(isOn: isOn, on: (style.accent, style.accent.opacity(0.12)),
                                              off: (NX.textSecondary, NX.ink(0.05))))
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
