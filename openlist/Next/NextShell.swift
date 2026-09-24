//
//  NextShell.swift
//  openlist
//

import SwiftData
import SwiftUI

/// The whole main window: sidebar, toolbar, the routed screen, the inspector,
/// the bottom bars and the capture, search and palette overlays.
struct NextShell: View {
    @Environment(AppEnvironment.self) private var env
    @Query(filter: TaskList.availablePredicate) private var allLists: [TaskList]
    @Query(filter: #Predicate<SidebarSection> { $0.mergedIntoID == nil }) private var sections: [SidebarSection]
    @Query private var labels: [TaskLabel]
    @Query(filter: #Predicate<Block> { $0.trashID == nil && $0.kindRaw == "task" }) private var tasks: [Block]
    @State private var overlays = NXOverlayState()
    @State private var chrome = NXWindowChrome()
    @State private var width: CGFloat = 0
    @State private var sidebarFrame: CGRect = .zero

    var body: some View {
        let library = drawnLibrary()
        let style = env.workbench.style
        let showsSidebar = env.workbench.showsSidebar
        HStack(spacing: 0) {
            // Folded or hidden, the sidebar stays mounted with no width, so a
            // rename in progress keeps its draft and commits as it loses focus.
            NextSidebar()
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { sidebarFrame = $0 }
                .frame(width: showsSidebar ? nil : 0, alignment: .trailing)
                .clipped()
                .disabled(!showsSidebar)
                .allowsHitTesting(showsSidebar)
                .accessibilityHidden(!showsSidebar)
            // The overlays dim and centre on the main pane; the sidebar stays clear.
            NextMain()
                .overlay { NextOverlays(overlays: overlays) }
                // With no sidebar to hold them, the traffic lights sit on the toolbar.
                .environment(\.nxTrafficLightsInset, showsSidebar || chrome.isFullScreen ? 0 : chrome.trailingEdge)
        }
        .environment(\.nextLibrary, library)
        .environment(\.nextStyle, style)
        .tint(style.accent)
        .background(NX.paper)
        .background { NextKeyMonitorHost(library: library, overlays: overlays) }
        .background { NXWindowChromeHost(chrome: chrome) }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) {
            width = $0
            adaptSidebar()
        }
        .onChange(of: env.navigator.openTaskID) { adaptSidebar() }
        .onChange(of: env.navigator.searchActivation) { landReveal() }
        // Back/Forward, reveals and deletions change the route without `go`.
        .onChange(of: env.navigator.route) { env.workbench.routeDidChange() }
        // Every Completed group opens as the new setting says, and an old
        // fold can't come back when the setting does.
        .onChange(of: env.settings.showsCompletedTasks) { env.workbench.completedFold = nil }
    }

    /// The library the window draws, its lists left on the workbench for
    /// Task ▸ Move to. Untracked there, so the write doesn't draw again.
    private func drawnLibrary() -> NextLibrary {
        let library = NextLibrary(lists: allLists, sections: sections, labels: labels, tasks: tasks)
        env.workbench.drawnLists = library.lists
        return library
    }

    /// A reminder, a link or a search hit that opens a task lands as the
    /// design's search does: its row takes the focus, once the new screen is
    /// up so it scrolls there, and the task stays open in the inspector.
    private func landReveal() {
        let navigator = env.navigator, workbench = env.workbench
        guard let taskID = navigator.contentReveal?.taskID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            guard navigator.contentReveal?.taskID == taskID else { return }
            workbench.inspect(taskID)
        }
    }

    /// A narrow window gives the inspector the sidebar's room while it's open,
    /// and gets the sidebar back once the inspector closes or there's room again.
    /// View ▸ Hide Sidebar is separate, so this never shows a sidebar the user hid.
    private func adaptSidebar() {
        let workbench = env.workbench
        let inspecting = env.navigator.openTaskID.flatMap { env.store.block(id: $0) }
            .map { $0.isTask && $0.trashID == nil } ?? false
        var folded = workbench.isSidebarFoldedForRoom
        if inspecting && width < 980 { folded = true }
        else if !inspecting || width >= 1100 { folded = false }
        guard folded != workbench.isSidebarFoldedForRoom else { return }
        if folded { endSidebarEditing() }
        withAnimation(workbench.style.ease(280)) { workbench.isSidebarFoldedForRoom = folded }
    }

    /// Ends a rename in the sidebar as it folds, so the name is saved rather
    /// than left in a field nobody can see.
    private func endSidebarEditing() {
        guard sidebarFrame.width > 0, let window = overlays.host?.window,
              let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
              let field = editor.delegate as? NSView else { return }
        let x = field.convert(field.bounds, to: nil).midX
        if x >= sidebarFrame.minX && x <= sidebarFrame.maxX { window.makeFirstResponder(nil) }
    }
}

/// Everything right of the sidebar.
private struct NextMain: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library

    private var workbench: Workbench { env.workbench }

    var body: some View {
        let inspected = env.navigator.openTaskID.flatMap { env.store.block(id: $0) }.flatMap { $0.isTask && $0.trashID == nil ? $0 : nil }
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                NextToolbar(crumb: crumb)
                // Clear of the inspector, which would cover their buttons.
                NextNotices()
                    .padding(.trailing, inspected == nil ? 0 : 360)
                NextRoutedScreen()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            }

            // The panel itself is what comes and goes, so it slides by its own
            // width rather than the whole window's.
            ZStack(alignment: .topTrailing) {
                if let inspected {
                    NextInspector(task: inspected)
                        .transition(style.slide(.move(edge: .trailing)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.top, 52)
            .zIndex(30)

            NXBottomBars()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.trailing, inspected == nil ? 0 : 360)
                .allowsHitTesting(workbench.tray != nil || !workbench.selection.isEmpty)
                .zIndex(35)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NX.paper)
        // Opening and closing slide; moving from one task to the next is instant.
        .animation(style.ease(300), value: inspected != nil)
    }

    private var crumb: String {
        switch env.navigator.route {
        case let .list(id):
            guard let list = library.list(id) else { return "Lists" }
            let section = library.sectionTitle(for: list)
            return section.isEmpty ? list.displayTitle : "\(section) › \(list.displayTitle)"
        case let .label(id):
            guard let label = library.label(id) else { return "Labels" }
            return "Labels › #\(label.name)"
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .calendar: return "Calendar"
        case .tasks: return "Tasks"
        case .lists: return "Lists"
        case .activity: return "Activity"
        case .trash: return "Trash"
        case .settings: return "Settings"
        }
    }
}

/// The window's notices, in one place under the toolbar: errors and warnings
/// that stay until dealt with. Everything else reports in the tray.
private struct NextNotices: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            NXStatusNotices()
            if env.localLinks.error != nil { LocalLinkNotice() }
            if env.store.labelMaintenanceError != nil { LabelMergeNotice() }
            ReminderNavigationNotice()
            // Successful trash and restore report in the tray; only failures stay pinned here.
            if env.store.trashError != nil { TrashNotice() }
        }
        // What the user's own action set off appears without a sound, so
        // VoiceOver hears each card as it appears, as it hears the tray; at
        // the tray's priority, so a failed Undo's or Restore's tray line and
        // its reason are both heard. Sync's warnings, which no action set
        // off, stay quiet.
        .onChange(of: env.store.editorNotice) { _, notice in announce(notice) }
        .onChange(of: env.store.actionError) { _, error in announce(error) }
        .onChange(of: env.store.persistenceError) { _, error in announce(error.map { "Changes are not saved. \($0)" }) }
        .onChange(of: env.store.trashError) { _, error in announce(error) }
        .onChange(of: env.store.labelMaintenanceError) { _, error in announce(error) }
        .onChange(of: env.localLinks.error?.localizedDescription) { _, error in announce(error.map { "Link unavailable. \($0)" }) }
        .onChange(of: env.reminderNavigation.unavailableMessage) { _, message in announce(message) }
    }

    private func announce(_ message: String?) {
        guard let message, NSApp.isActive else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

/// Picks the screen for the current route.
private struct NextRoutedScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library

    var body: some View {
        let navigator = env.navigator
        Group {
            switch navigator.route {
            case .inbox:
                // Triage, as the design; shown as a document, the Inbox is the list document too.
                if navigator.documentOwnsEditorCommands, let inbox = library.inbox {
                    NextInboxDocumentScreen(inbox: inbox)
                } else {
                    NextInboxScreen()
                }
            case .today: NextTodayScreen()
            case .calendar: NextCalendarScreen()
            case .tasks: NextTasksScreen()
            case .activity: NextActivityScreen()
            case .lists: NextListsGallery()
            case .trash: NextTrashScreen()
            case .settings: NextSettingsScreen()
            case let .list(id):
                if let list = library.list(id) ?? env.store.list(id: id) {
                    // Both presentations are the list document; Tasks shows only its tasks.
                    NextListScreen(list: list, tasksOnly: navigator.listViewMode(for: id) == .tasks)
                } else {
                    MissingContentView(message: "This list no longer exists.").modifier(NXNoRows())
                }
            case let .label(id):
                if let label = library.label(id) {
                    NextLabelScreen(label: label)
                } else {
                    MissingContentView(message: "This label no longer exists.").modifier(NXNoRows())
                }
            }
        }
        .id(navigator.route)
    }
}

/// Screens without Next rows publish none, so J/K, ⌘A and the targets never
/// reach rows the screen before left behind. Switching a list to Document
/// keeps the route, so this runs on appear rather than on navigation.
private struct NXNoRows: ViewModifier {
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content.onAppear {
            let workbench = env.workbench
            workbench.visibleIDs = []
            workbench.selection = []
            workbench.focusID = nil
        }
    }
}

// MARK: - Page scaffold

/// The scrolling page every screen sits in: 26/40/120 padding, an 880pt
/// measure unless wide, a click-to-clear background, scroll-to-focus,
/// scrolling to what a search hit or link reveals in a list document, and,
/// as a native extra, the place Back and Forward return it to.
struct NXPage<Content: View>: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    var wide = false
    /// Row IDs in on-screen order, published for j/k and ⌘A.
    var rowIDs: [UUID] = []
    @ViewBuilder var content: () -> Content
    @State private var appeared = false
    /// The reveal whose note card has laid out, so the page can scroll to it.
    @State private var visibleNoteRevealID: UUID?

    /// A reveal in the list on show, the Inbox too, once search has stepped
    /// aside. Tasks reveal in the inspector instead.
    private var readyRevealID: UUID? {
        guard !env.navigator.isSearchOpen, let request = env.navigator.contentReveal,
              request.taskID == nil, env.navigator.shows(request.listID) else { return nil }
        return request.id
    }

    var body: some View {
        let workbench = env.workbench
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id(ContentReveal.Anchor.pageHeader)
                    content()
                }
                .frame(maxWidth: wide ? .infinity : 880, alignment: .topLeading)
                .padding(.top, 26)
                .padding(.horizontal, 40)
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .offset(y: appeared ? 0 : 6)
                .opacity(appeared ? 1 : 0)
                .background {
                    Color.clear.contentShape(Rectangle()).onTapGesture { clearBackground() }
                }
            }
            .scrollIndicators(.automatic)
            .modifier(NXScrollRestoration(revealing: readyRevealID != nil))
            .background { Color.clear.contentShape(Rectangle()).onTapGesture { clearBackground() } }
            .onChange(of: workbench.focusID) { _, id in
                guard let id, rowIDs.contains(id) else { return }
                withAnimation(style.ease(180)) { proxy.scrollTo(id) }
            }
            .onChange(of: rowIDs) { old, ids in
                workbench.visibleIDs = ids
                // A row focused before it was drawn, like a line just added,
                // comes into view once it is.
                guard let id = workbench.focusID, ids.contains(id), !old.contains(id) else { return }
                withAnimation(style.ease(180)) { proxy.scrollTo(id) }
            }
            .task(id: readyRevealID) {
                guard readyRevealID != nil, let request = env.navigator.contentReveal else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                if request.revealsSummary(for: request.listID) {
                    proxy.scrollTo(ContentReveal.Anchor.listSummary(request.listID), anchor: .center)
                } else if let id = request.blockID, request.field == .note, visibleNoteRevealID == request.id {
                    proxy.scrollTo(ContentReveal.Anchor.blockNote(id), anchor: .center)
                } else if let id = request.blockID {
                    proxy.scrollTo(id, anchor: .center)
                } else {
                    proxy.scrollTo(ContentReveal.Anchor.pageHeader, anchor: .top)
                }
            }
            .onPreferenceChange(ContentRevealNoteReadyKey.self) { requestID in
                visibleNoteRevealID = requestID
                guard let requestID, requestID == readyRevealID,
                      let id = env.navigator.contentReveal?.blockID else { return }
                // The first scroll brings the line in; only then does the
                // note card under it exist to scroll to.
                proxy.scrollTo(ContentReveal.Anchor.blockNote(id), anchor: .center)
            }
        }
        .onAppear {
            workbench.visibleIDs = rowIDs
            withAnimation(style.ease(260)) { appeared = true }
        }
    }

    private func clearBackground() {
        let workbench = env.workbench
        workbench.focusID = nil
        workbench.tasksQueryFocused = false
        if env.navigator.openTaskID != nil { env.navigator.closeTask() }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

/// Back and Forward return a page to where it was left; any other arrival
/// opens it at the top, or on what a reveal shows. Its own view, so the
/// scroll position it keeps never redraws the page's content.
private struct NXScrollRestoration: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    /// A reveal is about to scroll the page to what it shows.
    let revealing: Bool
    @State private var position = ScrollPosition()
    /// The route the page reports its offset for, once it has opened where
    /// it should.
    @State private var route: AppRoute?

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
                guard let route, route == env.navigator.route else { return }
                env.navigator.rememberScrollOffset(offset, for: route)
            }
            .onAppear {
                let current = env.navigator.route
                if let offset = env.navigator.takeScrollRestoration(for: current), !revealing {
                    position.scrollTo(y: offset)
                }
                route = current
            }
    }
}

/// Section title used on Lists, Activity, Settings, the inspector and the
/// Inbox's triage card: the design's 600 10.5/1.
struct NXCapsTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.735)
            .textCase(.uppercase)
            .foregroundStyle(NX.ink(0.36))
            .padding(.vertical, (10.5 - NXStrikeText.glyphLineHeight(10.5)) / 2)
    }
}

/// The design's Trash box ("Trash is empty."), for the empty and failed
/// states of a page: 400 13/1.5 at ink 0.45, 34 pt in from a 1 pt dashed
/// border, radius 14, fading in over 240ms whenever it appears.
struct NXDashedEmpty: View {
    let text: String
    @State private var shown = false

    var body: some View {
        // The extra leading between lines and, halved, above the first and below the last.
        let leading = 13 * 1.5 - NXStrikeText.glyphLineHeight(13)
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(NX.ink(0.45))
            .multilineTextAlignment(.center)
            .lineSpacing(leading)
            .padding(.vertical, leading / 2)
            .frame(maxWidth: .infinity)
            // The border sits outside the design's 34 pt padding.
            .padding(35)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(NX.ink(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .opacity(shown ? 1 : 0)
            // The design's fadeIn, whatever the Motion setting.
            .onAppear { withAnimation(NX.cssEase(240)) { shown = true } }
    }
}
