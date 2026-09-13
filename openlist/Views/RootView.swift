//
//  RootView.swift
//  openlist
//

import SwiftData
import SwiftUI

/// The main window: sidebar, content, and the task detail inspector.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openWindow) private var openWindow
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var lastCommandToken = 0
    @State private var availableWidth: CGFloat = 1180
    @State private var sidebarBeforeInspector: NavigationSplitViewVisibility?
    /// The route whose unwanted initial focus has already been cleared, so the
    /// clear happens once per navigation and never steals a later click.
    @State private var focusClearedFor: AppRoute?
    @State private var hostWindow = RootWindowReference()
    @State private var searchReturnFocus = SearchReturnFocus()

    @Query(filter: #Predicate<Block> { $0.kindRaw == "task" && !$0.isCompleted })
    private var openTasks: [Block]
    @Query(filter: #Predicate<TaskList> { $0.mergedIntoID == nil }) private var allLists: [TaskList]

    var body: some View {
        @Bindable var navigator = env.navigator
        @Bindable var captureEnvironment = env

        navigationContent
        .navigationTitle("Openlist")
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            availableWidth = width
            adaptInspectorColumns()
        }
        .toolbar { toolbarContent }
        .sheet(item: $captureEnvironment.taskCaptureRequest) { request in
            TaskCaptureView(request: request)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $captureEnvironment.templateCopyRequest) { request in
            TemplateCopySheet(request: request)
        }
        .sheet(isPresented: $navigator.isCommandPaletteOpen) {
            CommandPaletteView()
        }
        .sheet(isPresented: $navigator.isSearchOpen, onDismiss: {
            searchReturnFocus.restore(in: hostWindow.window, activation: env.navigator.searchActivation)
        }) {
            SearchView()
        }
        .sheet(isPresented: $navigator.isShortcutSheetOpen) {
            ShortcutsSheet()
        }
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
            Text("Its tasks and notes will be deleted too, including on your other Macs when iCloud sync is available. This cannot be undone.")
        }
        .background(Theme.canvas)
        .overlay(alignment: .bottom) { CalendarCompletionFeedback() }
        .background {
            RootWindowReader { window in
                hostWindow.window = window
                env.reminderNavigation.windowReady(window != nil)
                installCompletionUndo(in: window)
                clearInitialFocus(for: env.navigator.route)
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .top) { statusNotices }
        .task { installQuickCapture() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window === hostWindow.window else { return }
            installCompletionUndo(in: window)
            // The real trigger: at launch the window is not key yet, so the
            // first responder has not been assigned when `task`/`onChange` run.
            clearInitialFocus(for: env.navigator.route)
        }
        .onChange(of: dockBadgeCount) { _, _ in updateDockBadge() }
        .onChange(of: env.settings.showsDockBadge) { _, _ in updateDockBadge() }
        .onChange(of: openTasks.map(\.id)) { _, _ in
            // Models can arrive after the first window/layout pass. An empty
            // pre-render pass must not disable protection for their first row.
            clearInitialFocus(for: env.navigator.route)
        }
        .onChange(of: env.navigator.selection) { _, _ in
            // Smart rows report focus through the selection. This also catches
            // AppKit assigning a responder after the first query/layout pass.
            clearInitialFocus(for: env.navigator.route)
        }
        .onAppear {
            updateDockBadge()
            env.reminderNavigation.openMainWindow = { openWindow(id: WindowID.main) }
        }
        .onDisappear { env.reminderNavigation.windowReady(false) }
        .onChange(of: env.navigator.isSearchOpen) { _, isOpen in
            if isOpen {
                searchReturnFocus.remember(in: hostWindow.window, activation: env.navigator.searchActivation)
            }
        }
        .onChange(of: env.navigator.route) { _, route in
            focusClearedFor = nil
            clearInitialFocus(for: route)
            // Screens that aren't documents (Today, Tasks, …) have no editor to
            // claim menu commands, so hand them to the fallback below.
            if route.hasDocumentEditor {
                // The document view claims it on appear.
            } else {
                env.activeDocument = nil
            }
        }
        .onChange(of: env.navigator.openTaskID) { _, newValue in
            adaptInspectorColumns()
            // Editing a subtask inside the detail panel makes that panel the
            // command target. On a smart view there is no list document to hand
            // control back to, so closing the panel has to release it or ⌘N and
            // the "+" buttons stay dead.
            if newValue == nil, !env.navigator.route.hasDocumentEditor {
                env.activeDocument = nil
                // Dismissing the inspector lets SwiftUI assign the first smart
                // row as responder again, often with its entire title selected.
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
    }

    /// Keep the document and inspector usable in a narrow window. Restore only
    /// sidebar visibility that this adaptive behavior changed itself.
    private func adaptInspectorColumns() {
        if env.navigator.openTaskID != nil, availableWidth < 980 {
            if columnVisibility != .detailOnly {
                sidebarBeforeInspector = columnVisibility
                columnVisibility = .detailOnly
            }
        } else if let previous = sidebarBeforeInspector,
                  env.navigator.openTaskID == nil || availableWidth >= 1100 {
            columnVisibility = previous
            sidebarBeforeInspector = nil
        }
    }

    private var navigationContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 236, max: 340)
        } detail: {
            GeometryReader { viewport in
                VStack(spacing: 0) {
                    if env.store.labelMergeUndo != nil || env.store.labelMaintenanceError != nil {
                        LabelMergeNotice()
                    }
                    ReminderNavigationNotice()
                    contentArea
                        .frame(minHeight: 0, maxHeight: .infinity)
                }
                // The notice reserves space inside the detail viewport. Its
                // wrapping height must not increase the split view's minimum
                // window size during AppKit's zero-width fitting pass.
                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .top)
            }
            .inspector(isPresented: taskPanelBinding) {
                TaskDetailPanel()
                    .inspectorColumnWidth(min: 300, ideal: 380, max: 480)
            }
        }
    }

    private var statusNotices: some View {
        VStack(spacing: 0) {
            if let notice = env.store.editorNotice {
                HStack(alignment: .top, spacing: 12) {
                    Label(notice, systemImage: "info.circle")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Dismiss") { env.store.editorNotice = nil }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ListAccent.blue.softBackground)
            }
            if let error = env.store.persistenceError {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Changes are not saved", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                    Text(error).font(.callout)
                    Button("Retry saving") { env.store.save() }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ListAccent.red.softBackground)
            }
            if let warning = syncWarning {
                Label(warning, systemImage: "icloud.slash")
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ListAccent.orange.softBackground)
            }
        }
    }

    // MARK: - Commands outside a document

    private func installCompletionUndo(in window: NSWindow?) {
        guard let window else { return }
        env.store.onCompletionUndoAvailable = { [weak window, weak store = env.store] action in
            guard let manager = window?.undoManager else { return }
            store?.registerCompletionUndo(action, with: manager)
        }
    }

    private var syncWarning: String? {
        env.store.syncPreparationError ?? env.sync.startupWarning ?? env.sync.pushRegistrationError
            ?? (env.sync.state.hasProblem ? env.sync.state.detail : nil)
    }

    /// Runs menu commands on the smart views, where the selection comes from
    /// tapped rows rather than a text caret.
    ///
    /// The task commands themselves live on `Store`, so this only decides what
    /// the targets are and handles the cases a cross-list screen owns.
    private func handleGlobalCommand() {
        guard let command = env.consumeCommand() else { return }
        let targets = env.navigator.selection.compactMap { env.store.block(id: $0) }

        if env.store.perform(command, on: targets) {
            if command == .deleteSelection { env.navigator.selection.removeAll() }
            return
        }

        switch command {
        case .newTask:
            env.presentTaskCapture()

        case .openDetails:
            if let first = targets.first(where: \.isTask) { env.navigator.openTask(first.id) }

        case .pickDueDate:
            if let first = targets.first(where: \.isTask) { env.openTask(first.id, showing: .due) }

        case .pickLabel:
            if let first = targets.first(where: \.isTask) { env.openTask(first.id, showing: .labels) }

        case .indent, .outdent, .moveUp, .moveDown, .expandAll, .collapseAll:
            // Outline-only operations have no meaning in a cross-list view.
            break

        default:
            break
        }
    }

    // MARK: - Quick capture & Dock

    /// Drops the window's first responder when arriving somewhere that focus
    /// would be destructive.
    ///
    /// AppKit hands initial focus to the first text field it finds. On the
    /// cross-list screens that is a task's `TextField`, which focuses *with its
    /// text selected* — one keystroke would silently replace the task. Document
    /// editors are left alone: their first responder is an `NSTextView`, which
    /// takes a caret rather than a selection, and on a brand-new list it is the
    /// title field, which is exactly where you want to be typing.
    private func clearInitialFocus(for route: AppRoute) {
        guard !route.hasDocumentEditor, focusClearedFor != route,
              !env.navigator.isSearchOpen, !env.navigator.isCommandPaletteOpen,
              !env.navigator.isShortcutSheetOpen, env.taskCaptureRequest == nil,
              env.navigator.openTaskID == nil,
              let initialWindow = hostWindow.window, initialWindow.isKeyWindow
        else { return }

        // Deferred because AppKit assigns the initial first responder after the
        // window becomes key. Recorded per route so this runs once per
        // navigation and cannot steal focus the user establishes afterwards.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak initialWindow] in
            guard env.navigator.route == route, focusClearedFor != route,
                  !env.navigator.isSearchOpen, !env.navigator.isCommandPaletteOpen,
                  !env.navigator.isShortcutSheetOpen, env.taskCaptureRequest == nil,
              env.navigator.openTaskID == nil,
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

    private func installQuickCapture() {
        QuickCaptureHotKey.shared.onTrigger = {
            openWindow(id: WindowID.quickAdd)
            NSApp.activate(ignoringOtherApps: true)
        }
        if env.settings.quickCaptureHotKeyEnabled {
            QuickCaptureHotKey.shared.register()
        }
    }

    /// Overdue plus due-today work — the number worth surfacing on the Dock.
    private var dockBadgeCount: Int {
        ActiveTaskPolicy(lists: allLists).tasks(in: openTasks)
            .filter { $0.isDueOnOrBeforeToday || $0.isStarred || ($0.selectedForDay.map { Calendar.current.startOfDay(for: $0) <= Calendar.current.startOfDay(for: .now) } ?? false) }.count
    }

    private func updateDockBadge() {
        let count = dockBadgeCount
        NSApp.dockTile.badgeLabel = (env.settings.showsDockBadge && count > 0) ? "\(count)" : nil
    }

    private var taskPanelBinding: Binding<Bool> {
        Binding(
            get: { env.navigator.openTaskID != nil },
            set: { if !$0 { env.navigator.closeTask() } }
        )
    }

    // MARK: - Content routing

    private var contentArea: some View {
        VStack(spacing: 0) {
            CalendarWorkBanner()
            routedContent
                .modifier(PageArrivalTransition(route: env.navigator.route))
        }
    }

    @ViewBuilder
    private var routedContent: some View {
        switch env.navigator.route {
        case .inbox:
            InboxScreen()
        case .today:
            TodayScreen()
        case .calendar:
            CalendarScreen()
        case .updates:
            UpdatesScreen()
        case .tasks:
            TasksScreen()
        case .lists:
            ListsScreen()
        case .completed:
            CompletedScreen()
        case let .list(id):
            if let list = env.store.list(id: id) {
                ListScreen(list: list)
                    .id(id)
            } else {
                MissingContentView(message: "This list no longer exists.")
            }
        case let .label(id):
            if let label = env.store.allLabels().first(where: { $0.id == id }) {
                LabelScreen(label: label)
                    .id(id)
            } else {
                MissingContentView(message: "This label no longer exists.")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Back", systemImage: "chevron.left") { env.navigator.goBack() }
                .labelStyle(.iconOnly)
            .disabled(!env.navigator.canGoBack)
            .help("Back (⌘[)")

            Button("Forward", systemImage: "chevron.right") { env.navigator.goForward() }
                .labelStyle(.iconOnly)
            .disabled(!env.navigator.canGoForward)
            .help("Forward (⌘])")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button("Search", systemImage: "magnifyingglass") { env.navigator.isSearchOpen = true }
                .labelStyle(.iconOnly)
            .help("Search (⌘F)")

            Button("Quick command", systemImage: "command") { env.navigator.isCommandPaletteOpen = true }
                .labelStyle(.iconOnly)
            .help("Quick command (⌘K)")

            Button("Add task", systemImage: "plus") { env.send(.newTask) }
                .labelStyle(.iconOnly)
            .help("New task (⌘N)")
        }
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
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                guard let scrollRoute, scrollRoute == env.navigator.route else { return }
                env.navigator.rememberScrollOffset(offset, for: scrollRoute)
            }
            .onAppear {
                scrollRoute = env.navigator.route
                if readyRevealID == nil {
                    scrollPosition.scrollTo(y: env.navigator.scrollOffset(for: env.navigator.route))
                }
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
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.tertiaryText)

            Text(title)
                .font(.system(size: 15, weight: .semibold))

            Text(message)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

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
