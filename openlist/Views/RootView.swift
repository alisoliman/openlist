//
//  RootView.swift
//  openlist
//

import SwiftData
import SwiftUI

/// The main window. `NextShell` draws everything; this view owns the window
/// wiring: sheets, alerts, notices, menu commands and the Dock badge.
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
        .alert(
            "Delete “\(env.listPendingDeletion?.displayTitle ?? "")”?",
            isPresented: Binding(
                get: { env.listPendingDeletion != nil },
                set: { if !$0 { env.listPendingDeletion = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { env.listPendingDeletion = nil }
            Button("Delete", role: .destructive) {
                if let list = env.listPendingDeletion { env.performDeleteList(list) }
            }
        } message: {
            Text("This moves the list and its child documents, tasks, notes, and files to Trash as one restorable unit. You can restore them later. With iCloud enabled, this change also syncs to your other Macs.")
        }
        .overlay(alignment: .top) { statusNotices.padding(.top, 52) }
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
        }
        .onDisappear {
            env.isMainWindowKey = false
            env.reminderNavigation.windowReady(false)
            env.localLinks.windowReady(false)
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
            // Editing a subtask on a legacy task page makes it the command
            // target. Closing the task has to release that or ⌘N stays dead.
            if newValue == nil, !env.navigator.documentOwnsEditorCommands {
                env.activeDocument = nil
                focusClearedFor = nil
                clearInitialFocus(for: env.navigator.route)
            }
        }
        .onChange(of: env.navigator.selection) { _, selection in
            // Esc in a legacy task page drops its selection but not its
            // claim. With no row left to act on, the screen takes over: a
            // list's own document, or the Next screen's targets.
            if selection.isEmpty, env.activeDocument?.rootBlockID != nil {
                env.activeDocument = env.navigator.documentListID.map { DocumentContext(listID: $0) }
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
            QuickCapturePanel.shared.showFromWidget(QuickCaptureRequest(listID: listID, plansForToday: forToday,
                                                                        appendsToList: listID != nil))
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
        case .calendar: env.workbench.go(.calendar)
        case .activity: env.workbench.go(.activity)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private var statusNotices: some View {
        VStack(spacing: 6) {
            if let notice = env.store.editorNotice {
                NXNoticeCard(icon: "info.circle", message: notice) {
                    Button("Dismiss") { env.store.editorNotice = nil }
                        .buttonStyle(NXPanelButtonStyle(kind: .quiet))
                }
            }
            if let error = env.store.persistenceError {
                NXNoticeCard(icon: "exclamationmark.triangle", tone: .error, message: "Changes are not saved. \(error)") {
                    Button("Retry saving") { env.store.save() }
                        .buttonStyle(NXPanelButtonStyle(kind: .link))
                }
            }
            if let warning = syncWarning {
                NXNoticeCard(icon: "icloud.slash", tone: .warning, message: warning) {}
            }
        }
        // They float over the screen, so they lift off it like the design's menus.
        .shadow(color: NX.shadowWarm.opacity(0.18), radius: 20, y: 16)
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        // Drawn over the shell, outside its style.
        .environment(\.nextStyle, env.workbench.style)
    }

    // MARK: - Commands outside a document

    /// This window, or a popover shown from it (a child window). Quick Add,
    /// Settings and the menu bar window are not, so the Task menu ignores them.
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

    private var syncWarning: String? {
        env.store.syncPreparationError ?? env.sync.startupWarning ?? env.sync.pushRegistrationError
            ?? (env.sync.state.hasProblem ? env.sync.state.detail : nil)
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

/// Shown when a route points at something that has since been deleted.
struct MissingContentView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 30))
                .foregroundStyle(Theme.tertiaryText)
            Text(message)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }
}

/// Standard page scaffold: big title, optional subtitle and trailing controls,
/// then scrolling content constrained to a comfortable measure.
struct ScreenScaffold<Header: View, Content: View>: View {
    @Environment(AppEnvironment.self) private var env
    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    @State private var scrollRoute: AppRoute?
    @State private var hasRestoredScroll = false
    @State private var visibleNoteRevealID: UUID?
    var maxContentWidth: CGFloat = 820
    /// Gap between the title block and the content below it.
    var headerSpacing: CGFloat = 14
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    private var readyRevealID: UUID? {
        guard !env.navigator.isSearchOpen, let request = env.navigator.contentReveal,
              request.taskID == nil, env.navigator.route == .list(request.listID) else { return nil }
        return request.id
    }

    var body: some View {
        GeometryReader { geometry in
            let gutter = min(Theme.Spacing.documentGutter, max(16, geometry.size.width * 0.045))
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header()
                        .padding(.bottom, headerSpacing)
                        .id(ContentReveal.Anchor.pageHeader)
                    content()
                }
                .frame(maxWidth: maxContentWidth, alignment: .leading)
                .padding(.horizontal, gutter)
                .padding(.top, 24)
                .padding(.bottom, 60)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollPosition($scrollPosition)
            .onChange(of: env.navigator.rowSelection.focusID) { _, id in
                guard env.navigator.isSelectingRows, let id,
                      env.activeDocument?.rootBlockID == nil,
                      NSApp.keyWindow?.firstResponder is RowSelectionNSControl else { return }
                if env.activeDocument == nil { proxy.scrollTo(TaskSelectionScrollID.first(id)) }
                else { proxy.scrollTo(id) }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                guard hasRestoredScroll, let scrollRoute, scrollRoute == env.navigator.route else { return }
                env.navigator.rememberScrollOffset(offset, for: scrollRoute)
            }
            .onAppear {
                scrollRoute = env.navigator.route
                if readyRevealID == nil {
                    if let offset = env.navigator.scrollOffset(for: env.navigator.route) {
                        scrollPosition.scrollTo(y: offset)
                    } else {
                        scrollPosition.scrollTo(edge: .top)
                    }
                }
                hasRestoredScroll = true
            }
            .task(id: readyRevealID) {
                guard readyRevealID != nil, let request = env.navigator.contentReveal else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                if request.revealsSummary(for: request.listID) {
                    proxy.scrollTo(ContentReveal.Anchor.listSummary(request.listID), anchor: .center)
                } else if let id = request.blockID, request.field == .note,
                          visibleNoteRevealID == request.id {
                    proxy.scrollTo(ContentReveal.Anchor.blockNote(id), anchor: .center)
                } else if let id = request.blockID { scrollPosition.scrollTo(id: id, anchor: .center) }
                else { proxy.scrollTo(ContentReveal.Anchor.pageHeader, anchor: .top) }
            }
            .onPreferenceChange(ContentRevealNoteReadyKey.self) { requestID in
                visibleNoteRevealID = requestID
                guard let requestID, requestID == readyRevealID,
                      let id = env.navigator.contentReveal?.blockID else { return }
                // The first scroll materializes the row. Only then does its
                // nested note anchor exist in the lazy document.
                proxy.scrollTo(ContentReveal.Anchor.blockNote(id), anchor: .center)
            }
            .background(Theme.canvas)
            }
        }
    }
}

/// Empty-state placeholder used across the smart views.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String = ""
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.tertiaryText)

            Text(title)
                .font(.system(size: 15, weight: .semibold))

            if !message.isEmpty {
                Text(message)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

/// Weak ownership prevents the hosted SwiftUI view from retaining its window.
private final class RootWindowReference {
    weak var window: NSWindow?
}

/// Identifies this RootView's window without relying on SwiftUI's generated
/// window identifiers or accidentally targeting Quick Add and Settings.
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
