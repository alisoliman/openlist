import AppKit
import SwiftData
import SwiftUI

/// Quick Add's card: the main window's capture card on its own, floating in
/// `QuickCapturePanel`. Return adds the task and closes, Shift-Return adds it
/// and keeps the card for the next, Tab steps the destination and Escape
/// closes, as they do in the main window.
struct QuickAddWindowView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: TaskList.availablePredicate) private var allLists: [TaskList]
    @Query(filter: #Predicate<SidebarSection> { $0.mergedIntoID == nil }) private var sections: [SidebarSection]
    @Query private var labels: [TaskLabel]
    @State private var draft: QuickCaptureDraft
    @State private var notice: NXCaptureNotice?
    @State private var noticeRevision = 0
    @State private var shown = false
    let close: () -> Void

    init(draft: QuickCaptureDraft, close: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.close = close
    }

    var body: some View {
        // The card reads lists and labels; task counts aren't shown here.
        let library = NextLibrary(lists: allLists, sections: sections, labels: labels, tasks: [])
        let style = env.workbench.style
        NXCaptureCard(draft: draft, notice: notice)
            .frame(width: 600)
            .nxOverlayCard()
            // The design's popIn.
            .scaleEffect(shown ? 1 : 0.97, anchor: .top)
            .offset(y: shown ? 0 : -4)
            .opacity(shown ? 1 : 0)
            // Room for the card's shadow in the transparent panel.
            .padding(EdgeInsets(top: 28, leading: 56, bottom: 88, trailing: 56))
            // Around the card is the design's backdrop, where a click closes.
            .background { Color.clear.contentShape(Rectangle()).onTapGesture(perform: close) }
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
        case let .step(delta): draft.cycleCaptureDestination(by: delta, among: lists.map(\.id))
        case .close: close()
        }
    }

    private func add(keepOpen: Bool) {
        let parse = draft.captureParse()
        guard !parse.title.isEmpty else { return }
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
        if !keepOpen {
            close()
            return
        }
        draft.captureText = ""
        show(NXCaptureNotice(text: "Added to \(env.store.list(id: block.listID)?.displayTitle ?? "Inbox")"))
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
/// window's capture. It files into Inbox unless its caller chose a list.
@Observable @MainActor
final class QuickCaptureDraft: NXCaptureDraft {
    @ObservationIgnored let store: Store
    @ObservationIgnored let settings: AppSettings
    var captureText = ""
    var captureListID: UUID?
    let captureForToday: Bool
    let captureLabelID: UUID? = nil

    init(store: Store, settings: AppSettings, listID: UUID? = nil, forToday: Bool? = nil) {
        self.store = store
        self.settings = settings
        let chosen = store.list(id: listID).flatMap { $0.isEffectivelyArchived ? nil : $0 }
        captureListID = chosen?.id ?? store.inboxList()?.id
        captureForToday = forToday ?? (settings.defaultDestination == .today)
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
