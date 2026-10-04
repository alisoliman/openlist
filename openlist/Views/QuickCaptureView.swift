import AppKit
import SwiftData
import SwiftUI

/// Quick Add's card: the main window's capture card on its own, floating in
/// `QuickCapturePanel`. Return adds the task and closes, Shift-Return adds it
/// and keeps the card for the next, Tab steps the destination and Escape
/// closes, as they do in the main window.
struct QuickCaptureView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: TaskList.availablePredicate) private var allLists: [TaskList]
    @Query(filter: #Predicate<SidebarSection> { $0.mergedIntoID == nil }) private var sections: [SidebarSection]
    @Query private var labels: [TaskLabel]
    @State private var draft: QuickCaptureDraft
    @State private var shown = false
    let animatesPresentation: Bool
    let close: (QuickCapturePanel.Dismissal) -> Void

    init(draft: QuickCaptureDraft, animatesPresentation: Bool = true, close: @escaping (QuickCapturePanel.Dismissal) -> Void) {
        _draft = State(initialValue: draft)
        self.animatesPresentation = animatesPresentation
        self.close = close
    }

    var body: some View {
        // The card reads lists and labels; task counts aren't shown here.
        let library = NextLibrary(lists: allLists, sections: sections, labels: labels, tasks: [])
        let style = env.workbench.style
        let undo: (() -> Void)? = draft.canUndoCapture ? { draft.undoCapture() } : nil
        // The design's popIn, as the window's capture card plays it, at its
        // own speed whatever the Motion setting; with Reduce Motion it only fades.
        let settled = shown || !style.slides || !animatesPresentation
        NXCaptureCard<QuickCaptureDraft>(draft: draft, notice: draft.notice, voice: draft.voice, managesVoiceLifecycle: false,
                      onVoiceSave: { [weak draft, weak workbench = env.workbench, close] outcome in
                          guard let draft, let workbench else { return }
                          draft.complete(outcome, workbench: workbench, keepOpen: false, automatically: true, close: close)
                      }, undoCapture: undo, add: { add(keepOpen: $0) })
            .frame(width: 600)
            .nxOverlayCard()
            .scaleEffect(settled ? 1 : 0.97, anchor: .top)
            .offset(y: settled ? 0 : -4)
            .opacity(shown || !animatesPresentation ? 1 : 0)
            // Room for the card's shadow in the transparent panel.
            .padding(EdgeInsets(top: 28, leading: 56, bottom: 88, trailing: 56))
            // A click on the shadow closes the card, as one on the backdrop
            // does in the window. Clicks on the margin's clear pixels go to the
            // app below, as they do around Spotlight, and close it by taking
            // the keyboard. Either way the draft waits for the next Quick Add.
            .background { Color.clear.contentShape(Rectangle()).onTapGesture { close(.dismissed) } }
            .background {
                QuickCaptureKeys(perform: { handle($0, lists: library.lists, labels: library.labels) },
                                 undo: draft.captureText.isEmpty ? undo : nil)
            }
            .environment(\.nextLibrary, library)
            .environment(\.nextStyle, style)
            .tint(style.accent)
            .animation(style.ease(140), value: draft.notice)
            .onAppear {
                if animatesPresentation { withAnimation(NX.ease(180)) { shown = true } }
                else { shown = true }
            }
            .onChange(of: draft.captureText) {
                if draft.notice?.failed == true { draft.notice = nil }
            }
            .onChange(of: draft.voice.isActive) {
                if draft.voice.isActive { draft.beginPresentation() }
            }
    }

    private func handle(_ key: QuickCaptureKey, lists: [TaskList], labels: [TaskLabel]) {
        let voice = draft.voice
        switch key {
        // While listening, Return is done speaking.
        case let .add(keepOpen):
            if voice.isActive {
                if voice.phase == .listening { voice.stop() }
            } else {
                add(keepOpen: keepOpen)
            }
        // The lit destination fades over the chip's 140ms, as in the main window.
        case let .step(delta): draft.cycleCaptureDestination(by: delta, among: lists.map(\.id))
        case .voice:
            voice.toggle(for: draft, lists: lists, labels: labels) { [weak draft, weak workbench = env.workbench, close] outcome in
                guard let draft, let workbench else { return }
                draft.complete(outcome, workbench: workbench, keepOpen: false, automatically: true, close: close)
            }
        // Escape stops listening, then puts away the tasks heard, then closes.
        case .close:
            if voice.isActive {
                voice.cancel()
            } else if !draft.spokenTasks.isEmpty {
                draft.spokenTasks = []
            } else {
                close(.finished)
            }
        }
    }

    /// The window's capture's Return, from the same `addCapture`: tokens
    /// alone add nothing, as there, and a failed save says why on the card.
    private func add(keepOpen: Bool) {
        draft.complete(draft.addCapture(), workbench: env.workbench, keepOpen: keepOpen, close: close)
    }
}

extension QuickCaptureDraft {
    func complete(_ outcome: NXCaptureOutcome, workbench: Workbench, keepOpen: Bool, automatically: Bool = false,
                  close: @escaping (QuickCapturePanel.Dismissal) -> Void) {
        let block: Block, opened: [UUID]
        switch outcome {
        case .untitled:
            return
        case let .failed(notice):
            show(notice)
            return
        case let .saved(saved, headings):
            block = saved
            opened = headings
        case let .savedSeveral(blocks, headings, failure):
            let manager = workbench.undoManager ?? fallbackUndoManager
            workbench.separateUndoStep(using: manager)
            manager.beginUndoGrouping()
            workbench.didAddSpoken(blocks, opened: headings, showsTray: false, using: manager)
            manager.endUndoGrouping()
            captureUndoManager = manager
            undoWorkbench = workbench
            undoBatch = workbench.log.first?.batch
            captureUndoLabel = manager.undoActionName
            let lists = Set(blocks.map(\.listID))
            let added = "Added \(blocks.count == 1 ? "1 task" : "\(blocks.count) tasks") to "
                + (lists.count == 1 ? store.list(id: blocks[0].listID)?.displayTitle ?? "Inbox" : "\(lists.count) lists")
            if let failure {
                show(failure)
            } else if automatically, !keepOpen, !hasCaptureDraft {
                show(NXCaptureNotice(text: added), closing: { close(.finished) })
            } else if keepOpen || hasCaptureDraft {
                show(NXCaptureNotice(text: added))
            } else {
                AccessibilityNotification.Announcement(added).post()
                close(.finished)
            }
            return
        }
        // The main window takes the task in as it does its own captures,
        // Undo and Changes included, folding again what the capture opened.
        workbench.didQuickAdd(block, opened: opened)
        let added = "Added to \(store.list(id: block.listID)?.displayTitle ?? "Inbox")"
        if !keepOpen {
            AccessibilityNotification.Announcement(added).post()
            close(.finished)
            return
        }
        captureText = ""
        show(NXCaptureNotice(text: added))
    }

    /// Shows a failure until the text changes, and what was added for two seconds.
    func show(_ notice: NXCaptureNotice, closing: (() -> Void)? = nil) {
        noticeTask?.cancel()
        noticeTask = nil
        self.notice = notice
        noticeRevision += 1
        AccessibilityNotification.Announcement(notice.text).post()
        guard !notice.failed else { return }
        let revision = noticeRevision
        let generation = voice.generation
        noticeTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(closing == nil ? 2 : 3)) }
            catch { return }
            guard let self, self.noticeRevision == revision, self.voice.generation == generation, !self.voice.isActive else { return }
            self.noticeTask = nil
            self.notice = nil
            if !self.hasCaptureDraft { closing?() }
        }
    }
}

/// Quick Add's own draft, so its half-typed text never meets the main
/// window's capture. It files into Inbox unless what opened it chose a list.
@Observable @MainActor
final class QuickCaptureDraft: NXCaptureDraft {
    @ObservationIgnored let store: Store
    @ObservationIgnored let settings: AppSettings
    var captureText = "" {
        didSet { if captureText != oldValue { invalidateFeedback() } }
    }
    var captureListID: UUID? {
        didSet { if captureListID != oldValue { invalidateFeedback() } }
    }
    let captureLabelID: UUID? = nil
    var spokenTasks: [SpokenTask] = [] {
        didSet { invalidateFeedback() }
    }
    var notice: NXCaptureNotice?
    @ObservationIgnored private var noticeRevision = 0
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private let fallbackUndoManager = UndoManager()
    @ObservationIgnored private var captureUndoManager: UndoManager?
    @ObservationIgnored private weak var undoWorkbench: Workbench?
    private var undoBatch: Int?
    private var captureUndoLabel: String?
    /// Quick Add's own voice capture.
    let voice = VoiceCapture()
    /// The Today widget asked for a task due today.
    private var dueToday = false

    var canUndoCapture: Bool {
        guard notice != nil, !voice.isActive, let undoBatch, let undoWorkbench,
              undoWorkbench.log.first?.batch == undoBatch else { return false }
        _ = undoWorkbench.canUndo
        return captureUndoManager?.canUndo == true && captureUndoManager?.undoActionName == captureUndoLabel
    }

    func undoCapture() {
        guard canUndoCapture, let captureUndoManager else { return }
        let keepsFailure = notice?.failed == true
        invalidateFeedback()
        captureUndoManager.undo()
        undoBatch = nil
        self.captureUndoManager = nil
        if !keepsFailure { show(NXCaptureNotice(text: "Undid added tasks")) }
    }

    func beginPresentation() { invalidateFeedback() }

    func endPresentation() {
        invalidateFeedback()
        voice.preserveForReview()
        voice.applicationResignedActive()
    }

    private func invalidateFeedback() {
        noticeTask?.cancel()
        noticeTask = nil
        noticeRevision += 1
        if notice?.failed == false { notice = nil }
    }

    /// A task with no date of its own is due today when the Today widget
    /// asked for one, or while new tasks go to Today.
    var captureForToday: Bool { dueToday || settings.defaultDestination == .today }

    init(store: Store, settings: AppSettings, request: QuickCaptureRequest) {
        self.store = store
        self.settings = settings
        fallbackUndoManager.groupsByEvent = false
        captureListID = store.inboxList()?.id
        apply(request)
    }

    /// Aims the draft where `request` asks, keeping its text: Inbox with no
    /// date when it names no list and doesn't ask for today.
    func apply(_ request: QuickCaptureRequest) {
        guard !request.listens || !hasCaptureDraft else { return }
        let chosen = store.list(id: request.listID).flatMap { $0.isEffectivelyArchived ? nil : $0 }
        captureListID = chosen?.id ?? store.inboxList()?.id
        dueToday = request.dueToday
    }
}

/// The keys Quick Add's card answers.
enum QuickCaptureKey {
    case add(keepOpen: Bool)
    case step(Int)
    /// ⌥⌘V: speak tasks, or stop listening.
    case voice
    case close
}

/// Return, Shift-Return, Tab, Escape, ⌥⌘V and ⌘W for the panel's card, taken
/// before its text field sees them, as the main window's key monitor does
/// for its capture.
private struct QuickCaptureKeys: NSViewRepresentable {
    let perform: (QuickCaptureKey) -> Void
    var undo: (() -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = KeyHostView()
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.perform = perform
        context.coordinator.undo = undo
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator { Coordinator(perform: perform, undo: undo) }

    @MainActor
    final class Coordinator {
        var perform: (QuickCaptureKey) -> Void
        var undo: (() -> Void)?
        weak var view: NSView?
        private var monitor: Any?

        init(perform: @escaping (QuickCaptureKey) -> Void, undo: (() -> Void)?) {
            self.perform = perform
            self.undo = undo
        }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let handled = MainActor.assumeIsolated { self.handle(event) }
                return handled ? nil : event
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard let window = view?.window, event.window === window else { return false }
            // An input method's marked text keeps Return, Tab and Escape.
            if (window.firstResponder as? NSTextInputClient)?.hasMarkedText() == true { return false }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "z", let undo {
                undo()
                return true
            }
            let key: QuickCaptureKey
            switch event.keyCode {
            case 36, 76:
                guard !flags.contains(.command) else { return false }
                key = .add(keepOpen: flags.contains(.shift))
            case 48:
                key = .step(flags.contains(.shift) ? -1 : 1)
            case 53:
                key = .close
            default:
                let chars = event.charactersIgnoringModifiers?.lowercased()
                if flags == [.command, .option], chars == "v" {
                    key = .voice
                } else {
                    guard flags == .command, chars == "w" else { return false }
                    key = .close
                }
            }
            perform(key)
            return true
        }
    }

    /// Takes no clicks; it only lends the monitor its window.
    private final class KeyHostView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
