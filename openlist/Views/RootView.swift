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
        .task { installQuickCapture() }
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
            if !env.navigator.hasDocumentEditor { env.activeDocument = nil }
        }
        .onChange(of: env.navigator.hasDocumentEditor) { _, hasDocumentEditor in
            // Switching a list presentation can remove the editor without
            // changing the route or closing an inspector.
            if !hasDocumentEditor {
                env.activeDocument = nil
                focusClearedFor = nil
                clearInitialFocus(for: env.navigator.route)
            }
        }
        .onChange(of: env.navigator.openTaskID) { _, newValue in
            // Editing a subtask inside the inspector makes it the command
            // target. Closing it has to release that or ⌘N stays dead.
            if newValue == nil, !env.navigator.hasDocumentEditor {
                env.activeDocument = nil
                focusClearedFor = nil
                clearInitialFocus(for: env.navigator.route)
            }
        }
        .onChange(of: env.navigator.selection) { _, selection in
            // Esc in an inspector subtask drops its selection but not its
            // claim. With no row left to act on, the Next screen takes over.
            if selection.isEmpty, env.activeDocument?.rootBlockID != nil, !env.navigator.hasDocumentEditor {
                env.activeDocument = nil
            }
        }
        .onChange(of: env.commandToken) { _, newValue in
            guard newValue != lastCommandToken else { return }
            lastCommandToken = newValue
            guard env.activeDocument == nil else { return }
            handleGlobalCommand()
        }
    }

    private var statusNotices: some View {
        VStack(spacing: 6) {
            if let notice = env.store.editorNotice {
                noticeCard(text: notice, icon: "info.circle", tint: ListAccent.blue.softBackground, action: ("Dismiss", { env.store.editorNotice = nil }))
            }
            if let error = env.store.persistenceError {
                noticeCard(text: "Changes are not saved. \(error)", icon: "exclamationmark.triangle.fill",
                       tint: ListAccent.red.softBackground, action: ("Retry saving", { env.store.save() }))
            }
            if let warning = syncWarning {
                noticeCard(text: warning, icon: "icloud.slash", tint: ListAccent.orange.softBackground, action: nil)
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
    }

    private func noticeCard(text: String, icon: String, tint: Color, action: (String, () -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Label(text, systemImage: icon)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(NX.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
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
        let workbench = env.workbench
        let ids = workbench.targetTasks.map(\.id)

        switch command {
        case .newTask:
            workbench.openCapture()
        case .toggleCompletion:
            workbench.toggleCompletion(ids)
        case .openDetails:
            if let first = ids.first { inspect(first) }
        case .pickDueDate, .pickLabel:
            guard let first = ids.first else { return }
            env.requestedPicker = command == .pickDueDate ? .due : .labels
            inspect(first)
        case .setDueToday:
            workbench.schedule(ids, offset: 0)
        case .clearDueDate:
            workbench.schedule(ids, offset: nil)
        case .toggleStar:
            workbench.star(ids)
        case .deleteSelection:
            workbench.trash(ids)
        case .clearLabels:
            workbench.clearLabels(ids)
        case .indent, .outdent, .moveUp, .moveDown, .expandAll, .collapseAll:
            // Outline-only operations have no meaning in a cross-list view.
            break
        }
    }

    /// Opens a task in the inspector. The task already on show keeps the focus
    /// it has, so the Inbox triage keys still work once the inspector closes.
    private func inspect(_ id: UUID) {
        guard id != env.navigator.openTaskID else { return }
        env.workbench.inspect(id)
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
            let length = (editor.string as NSString).length
            if length > 0, editor.selectedRange() == NSRange(location: 0, length: length) {
                window.makeFirstResponder(nil)
            }
        }
    }

    /// Whether nothing on screen wants the focus AppKit handed out: no document
    /// editor, overlay or open task, and this route not already settled.
    private func mayClearFocus(on route: AppRoute) -> Bool {
        !env.navigator.hasDocumentEditor && focusClearedFor != route
            && !env.navigator.isSearchOpen && !env.navigator.isCommandPaletteOpen
            && !env.navigator.isShortcutSheetOpen && !env.workbench.captureOpen
            && env.navigator.openTaskID == nil
    }

    private func installQuickCapture() {
        QuickCaptureHotKey.shared.onTrigger = {
            openWindow(id: WindowID.quickAdd)
            NSApp.activate(ignoringOtherApps: true)
        }
        if env.settings.quickCaptureHotKeyEnabled {
            QuickCaptureHotKey.shared.register()
        }
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
