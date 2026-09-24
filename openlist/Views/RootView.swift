//
//  RootView.swift
//  openlist
//

import SwiftData
import SwiftUI

/// The main window. `NextShell` draws everything; this view owns the window
/// wiring: sheets, menu commands and the Dock badge.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow
    @State private var lastCommandToken = 0
    /// The route whose unwanted initial focus has already been cleared, so the
    /// clear happens once per navigation and never steals a later click.
    @State private var focusClearedFor: AppRoute?
    @State private var hostWindow = RootWindowReference()

    @Query(filter: #Predicate<Block> { $0.trashID == nil && $0.kindRaw == "task" && !$0.isCompleted })
    private var openTasks: [Block]
    @Query(filter: TaskList.availablePredicate) private var allLists: [TaskList]

    var body: some View {
        @Bindable var navigator = env.navigator
        @Bindable var captureEnvironment = env

        NextShell()
        .ignoresSafeArea()
        .navigationTitle("Openlist")
        .sheet(item: $captureEnvironment.templateCopyRequest) { request in
            TemplateCopySheet(request: request)
        }
        .sheet(isPresented: $navigator.isShortcutSheetOpen) {
            ShortcutsSheet()
        }
        .sheet(item: $captureEnvironment.listPendingMove) { list in MoveListSheet(list: list).environment(env) }
        .sheet(item: $captureEnvironment.listPendingDeletion) { list in DeleteListSheet(list: list).environment(env) }
        .sheet(item: $captureEnvironment.linkPrompt) { prompt in NXLinkSheet(prompt: prompt).environment(env) }
        .background {
            RootWindowReader { window in
                hostWindow.window = window
                env.isMainWindowKey = window?.isKeyWindow == true
                env.reminderNavigation.windowReady(window != nil)
                env.localLinks.windowReady(window != nil)
                installUndo(in: window)
                clearInitialFocus(for: env.navigator.route)
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow else { return }
            env.isMainWindowKey = isMainWindow(window)
            guard window === hostWindow.window else { return }
            env.reminderNavigation.windowReady(true)
            env.localLinks.windowReady(true)
            installUndo(in: window)
            // The real trigger: at launch the window is not key yet, so the
            // first responder has not been assigned when `task`/`onChange` run.
            clearInitialFocus(for: env.navigator.route)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow, isMainWindow(window) else { return }
            env.isMainWindowKey = false
        }
        .onChange(of: dockBadgeCount) { _, _ in updateDockBadge() }
        .onChange(of: env.settings.showsDockBadge) { _, _ in updateDockBadge() }
        .onChange(of: openTasks.map(\.id)) { _, _ in
            // Models can arrive after the first window/layout pass. An empty
            // pre-render pass must not disable protection for their first row.
            clearInitialFocus(for: env.navigator.route)
        }
        .onAppear {
            updateDockBadge()
            env.reminderNavigation.openMainWindow = { openWindow(id: WindowID.main) }
            env.calendarNotifications.openMainWindow = { openWindow(id: WindowID.main) }
            // ⌘L in a list document line asks in this window's link sheet.
            BlockNSTextView.linkPrompter = { env.linkPrompt = $0 }
        }
        .onDisappear {
            env.isMainWindowKey = false
            env.reminderNavigation.windowReady(false)
            env.localLinks.windowReady(false)
            // The Work panel goes with the window, and so does a Show Work
            // asked for while it was open.
            env.calendar.isWorkPanelPresented = false
            env.showsWorkPanelOnOpen = false
        }
        .onChange(of: env.navigator.route) { _, route in
            focusClearedFor = nil
            clearInitialFocus(for: route)
            // Screens that aren't documents (Today, Tasks, …) have no editor to
            // claim menu commands, so hand them to the fallback below.
            if !env.navigator.documentOwnsEditorCommands { env.activeDocument = nil }
        }
        .onChange(of: env.navigator.documentOwnsEditorCommands) { _, ownsCommands in
            // Switching the Inbox's presentation can remove the editor
            // without changing the route or closing an inspector.
            if !ownsCommands {
                env.activeDocument = nil
                focusClearedFor = nil
                clearInitialFocus(for: env.navigator.route)
            }
        }
        .onChange(of: env.navigator.openTaskID) { _, newValue in
            // An open task holds off the initial-focus clear; closing it off
            // a document gives the screen that clear, and its commands, back.
            if newValue == nil, !env.navigator.documentOwnsEditorCommands {
                env.activeDocument = nil
                focusClearedFor = nil
                clearInitialFocus(for: env.navigator.route)
            }
        }
        .onChange(of: env.commandToken) { _, newValue in
            guard newValue != lastCommandToken else { return }
            lastCommandToken = newValue
            guard env.activeDocument == nil else { return }
            handleGlobalCommand()
        }
        .onChange(of: env.pendingWidgetRoute, initial: true) { _, route in
            if let route { openWidgetRoute(route) }
        }
    }

    /// Where a widget tap asked to go: Quick Add, or a screen in this window.
    private func openWidgetRoute(_ route: WidgetRoute) {
        env.pendingWidgetRoute = nil
        switch route {
        case let .capture(listID, forToday):
            // The Quick Add panel floats over the app in front without activating Openlist.
            QuickCapturePanel.shared.showFromWidget(QuickCaptureRequest(listID: listID, dueToday: forToday))
            return
        // This Mac's choice for the Inbox, even straight after a triage visit.
        case .inbox:
            env.workbench.go(.inbox)
            env.navigator.followInboxPresentation()
        // Triage even where this Mac shows the Inbox as a document, for this visit.
        case .triage:
            env.workbench.go(.inbox)
            env.navigator.showInboxTriage()
        case .today: env.workbench.go(.today)
        // Up Next and Agenda: today's work, whichever range the Calendar was left on.
        case .calendar: env.workbench.showOnCalendar()
        case .activity: env.workbench.go(.activity)
        case .lists: env.workbench.go(.lists)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Commands outside a document

    /// This window, or a popover shown from it (a child window). Quick Add
    /// and the menu bar's popover are not, so the Task menu ignores them.
    private func isMainWindow(_ window: NSWindow) -> Bool {
        var candidate: NSWindow? = window
        while let current = candidate {
            if current === hostWindow.window { return true }
            candidate = current.parent
        }
        return false
    }

    private func installUndo(in window: NSWindow?) {
        guard let window else { return }
        env.workbench.undoManager = window.undoManager
        env.workbench.installCompletionUndo()
    }

    /// Runs menu commands on the Next screens, where the targets are the
    /// selection, else the focused row, else the inspected task. These are
    /// the tasks AppCommands enables the Task menu for.
    private func handleGlobalCommand() {
        guard let command = env.consumeCommand() else { return }
        // Outline-only operations have no meaning in a cross-list view.
        env.performTaskCommand(command, on: env.workbench.targetTasks.map(\.id))
    }

    // MARK: - Quick capture & Dock

    /// Drops the window's first responder when arriving somewhere that focus
    /// would be destructive.
    ///
    /// AppKit hands initial focus to the first text field it finds, often
    /// *with its text selected* — one keystroke would silently replace it.
    /// Document editors are left alone: their first responder is an
    /// `NSTextView`, which takes a caret rather than a selection.
    private func clearInitialFocus(for route: AppRoute) {
        guard mayClearFocus(on: route), let initialWindow = hostWindow.window, initialWindow.isKeyWindow
        else { return }

        // Deferred because AppKit assigns the initial first responder after the
        // window becomes key. Recorded per route so this runs once per
        // navigation and cannot steal focus the user establishes afterwards.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak initialWindow] in
            guard env.navigator.route == route, mayClearFocus(on: route),
                  let window = initialWindow, window === hostWindow.window,
                  window === NSApp.keyWindow, window.sheetParent == nil, window.attachedSheet == nil
            else { return }
            let editor = (window.firstResponder as? NSTextView)
                ?? ((window.firstResponder as? NSTextField)?.currentEditor() as? NSTextView)
            // Keep waiting for the query/layout pass if no field exists yet.
            // A deliberately placed caret or partial selection is safe and
            // settles this guard without taking the user's focus away.
            guard let editor else { return }
            focusClearedFor = route
            // A list document line's caret or selection is the user's own.
            guard !(editor is BlockNSTextView) else { return }
            let length = (editor.string as NSString).length
            if length > 0, editor.selectedRange() == NSRange(location: 0, length: length) {
                window.makeFirstResponder(nil)
            }
        }
    }

    /// Whether nothing on screen wants the focus AppKit handed out: no overlay
    /// or open task, and this route not already settled.
    private func mayClearFocus(on route: AppRoute) -> Bool {
        focusClearedFor != route
            && !env.navigator.isSearchOpen && !env.navigator.isCommandPaletteOpen
            && !env.navigator.isShortcutSheetOpen && !env.workbench.captureOpen
            && env.navigator.openTaskID == nil
    }

    /// Overdue, due-today, starred and planned-for-today work — the number
    /// worth surfacing on the Dock.
    private var dockBadgeCount: Int {
        ActiveTaskPolicy(lists: allLists).tasks(in: openTasks)
            .filter { $0.isDueOnOrBeforeToday || $0.isStarred || env.workbench.isPlanned($0) }.count
    }

    private func updateDockBadge() {
        let count = dockBadgeCount
        NSApp.dockTile.badgeLabel = (env.settings.showsDockBadge && count > 0) ? "\(count)" : nil
    }
}

/// The window's editor, failure, saving and sync notices. They sit under the
/// toolbar with the link, label and Trash notices, in line with the screen's
/// content, which VoiceOver hears as they appear (`NextNotices`). A refusal
/// that changed nothing passes in the tray instead; see `Store.refuse`.
struct NXStatusNotices: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            if let notice = env.store.editorNotice {
                NXNoticeCard(icon: "info.circle", message: notice) {
                    Button("Dismiss") { env.store.editorNotice = nil }
                        .buttonStyle(NXPanelButtonStyle(kind: .quiet))
                }
                .nxNoticePlacement()
            }
            if let error = env.store.actionError {
                NXNoticeCard(icon: "exclamationmark.triangle", tone: .error, message: error) {
                    Button("Dismiss") { env.store.actionError = nil }
                        .buttonStyle(NXPanelButtonStyle(kind: .quiet))
                }
                .nxNoticePlacement()
            }
            if let error = env.store.persistenceError {
                NXNoticeCard(icon: "exclamationmark.triangle", tone: .error, message: "Changes are not saved. \(error)") {
                    Button("Retry saving") { env.store.save() }
                        .buttonStyle(NXPanelButtonStyle(kind: .link))
                }
                .nxNoticePlacement()
            }
            if let warning = syncWarning {
                NXNoticeCard(icon: "icloud.slash", tone: .warning, message: warning) {}
                    .nxNoticePlacement()
            }
        }
    }

    private var syncWarning: String? {
        env.store.syncPreparationError ?? env.sync.startupWarning ?? env.sync.pushRegistrationError
            ?? (env.sync.state.hasProblem ? env.sync.state.detail : nil)
    }
}

/// Shown when a route points at something that has since been deleted, like
/// a list Back returns to after it went to Trash: the design's dashed empty
/// box on the page, and a way on.
struct MissingContentView: View {
    @Environment(AppEnvironment.self) private var env
    let message: String

    var body: some View {
        let workbench = env.workbench
        let way = destination
        NXPage {
            VStack(spacing: 12) {
                NXDashedEmpty(text: way.route == .trash ? "This list is in Trash." : message)
                Button(way.label) { workbench.go(way.route) }
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary))
            }
            .padding(.top, 8)
        }
    }

    /// Trash for a list that's there, else where lists or labels are found.
    private var destination: (label: String, route: AppRoute) {
        switch env.navigator.route {
        case let .list(id):
            let lists = (try? env.store.context.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { $0.id == id }))) ?? []
            return lists.contains { $0.trashID != nil } ? ("Open Trash", .trash) : ("Open Lists", .lists)
        default:
            return ("Open Tasks", .tasks)
        }
    }
}

/// Weak ownership prevents the hosted SwiftUI view from retaining its window.
private final class RootWindowReference {
    weak var window: NSWindow?
}

/// Identifies this RootView's window without relying on SwiftUI's generated
/// window identifiers or accidentally targeting Quick Add or the menu bar's
/// popover.
private struct RootWindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: WindowProbe, context: Context) {
        nsView.onChange = onChange
    }

    final class WindowProbe: NSView {
        var onChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                onChange?(window)
            }
        }
    }
}
