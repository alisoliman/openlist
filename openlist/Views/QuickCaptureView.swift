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
    @State private var notice: NXCaptureNotice?
    @State private var noticeRevision = 0
    @State private var shown = false
    let close: (QuickCapturePanel.Dismissal) -> Void

    init(draft: QuickCaptureDraft, close: @escaping (QuickCapturePanel.Dismissal) -> Void) {
        _draft = State(initialValue: draft)
        self.close = close
    }

    var body: some View {
        // The card reads lists and labels; task counts aren't shown here.
        let library = NextLibrary(lists: allLists, sections: sections, labels: labels, tasks: [])
        let style = env.workbench.style
        // The design's popIn, as the window's capture card plays it; with
        // Reduce Motion it only fades.
        let settled = shown || !style.slides
        NXCaptureCard(draft: draft, notice: notice, add: { add(keepOpen: $0) })
            .frame(width: 600)
            .nxOverlayCard()
            .scaleEffect(settled ? 1 : 0.97, anchor: .top)
            .offset(y: settled ? 0 : -4)
            .opacity(shown ? 1 : 0)
            // Room for the card's shadow in the transparent panel.
            .padding(EdgeInsets(top: 28, leading: 56, bottom: 88, trailing: 56))
            // A click on the shadow closes the card, as one on the backdrop
            // does in the window. Clicks on the margin's clear pixels go to the
            // app below, as they do around Spotlight, and close it by taking
            // the keyboard. Either way the draft waits for the next Quick Add.
            .background { Color.clear.contentShape(Rectangle()).onTapGesture { close(.dismissed) } }
            .background { QuickCaptureKeys(perform: { handle($0, lists: library.lists) }) }
            .environment(\.nextLibrary, library)
            .environment(\.nextStyle, style)
            .tint(style.accent)
            .animation(style.ease(140), value: notice)
            .onAppear { withAnimation(style.ease(180)) { shown = true } }
            .onChange(of: draft.captureText) {
                if notice?.failed == true { notice = nil }
            }
    }

    private func handle(_ key: QuickCaptureKey, lists: [TaskList]) {
        switch key {
        case let .add(keepOpen): add(keepOpen: keepOpen)
        case let .step(delta):
            // Command selection doesn't animate, as in the main window.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { draft.cycleCaptureDestination(by: delta, among: lists.map(\.id)) }
        case .close: close(.finished)
        }
    }

    private func add(keepOpen: Bool) {
        let parse = draft.captureParse()
        guard !parse.title.isEmpty else {
            // Tokens alone would make an untitled task; say so rather than doing nothing.
            if !parse.text.trimmingCharacters(in: .whitespaces).isEmpty {
                show(NXCaptureNotice(text: "Type a title as well as the date, label, priority or estimate.", failed: true))
            }
            return
        }
        let block: Block
        do {
            block = try draft.saveCapture(parse)
        } catch {
            show(NXCaptureNotice(text: "Task wasn’t added. \(error.localizedDescription) Your draft is still here; try again.",
                                 failed: true))
            return
        }
        // The main window greets the task as it does its own captures.
        env.workbench.flash(\.fresh, [block.id], for: 1200)
        env.workbench.pulse(list: block.listID)
        let added = "Added to \(env.store.list(id: block.listID)?.displayTitle ?? "Inbox")"
        if !keepOpen {
            AccessibilityNotification.Announcement(added).post()
            close(.finished)
            return
        }
        draft.captureText = ""
        show(NXCaptureNotice(text: added))
    }

    /// Shows a failure until the text changes, and what was added for two seconds.
    private func show(_ notice: NXCaptureNotice) {
        self.notice = notice
        AccessibilityNotification.Announcement(notice.text).post()
        guard !notice.failed else { return }
        noticeRevision += 1
        let revision = noticeRevision
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if noticeRevision == revision { self.notice = nil }
        }
    }
}

/// Quick Add's own draft, so its half-typed text never meets the main
/// window's capture. It files into Inbox unless what opened it chose a list.
@Observable @MainActor
final class QuickCaptureDraft: NXCaptureDraft {
    @ObservationIgnored let store: Store
    @ObservationIgnored let settings: AppSettings
    var captureText = ""
    var captureListID: UUID?
    let captureLabelID: UUID? = nil
    /// The Today widget asked for a task due today.
    private var dueToday = false

    /// A task with no date of its own is due today when the Today widget
    /// asked for one, or while new tasks go to Today.
    var captureForToday: Bool { dueToday || settings.defaultDestination == .today }

    init(store: Store, settings: AppSettings, request: QuickCaptureRequest) {
        self.store = store
        self.settings = settings
        captureListID = store.inboxList()?.id
        apply(request)
    }

    /// Aims the draft where `request` asks, keeping its text: Inbox with no
    /// date when it names no list and doesn't ask for today.
    func apply(_ request: QuickCaptureRequest) {
        let chosen = store.list(id: request.listID).flatMap { $0.isEffectivelyArchived ? nil : $0 }
        captureListID = chosen?.id ?? store.inboxList()?.id
        dueToday = request.dueToday
    }
}

/// The keys Quick Add's card answers.
enum QuickCaptureKey {
    case add(keepOpen: Bool)
    case step(Int)
    case close
}

/// Return, Shift-Return, Tab, Escape and ⌘W for the panel's card, taken
/// before its text field sees them, as the main window's key monitor does
/// for its capture.
private struct QuickCaptureKeys: NSViewRepresentable {
    let perform: (QuickCaptureKey) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyHostView()
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.perform = perform
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator { Coordinator(perform: perform) }

    @MainActor
    final class Coordinator {
        var perform: (QuickCaptureKey) -> Void
        weak var view: NSView?
        private var monitor: Any?

        init(perform: @escaping (QuickCaptureKey) -> Void) {
            self.perform = perform
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
                guard flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" else { return false }
                key = .close
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
