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
    @State private var width: CGFloat = 0
    @State private var sidebarFrame: CGRect = .zero

    var body: some View {
        let library = NextLibrary(lists: allLists, sections: sections, labels: labels, tasks: tasks)
        let style = env.workbench.style
        let showsSidebar = env.workbench.showsSidebar
        let revealedDocuments = overlays.revealedDocuments.filter { env.navigator.listViewMode(for: $0) == .document }
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
            NextMain()
        }
        .overlay { NextOverlays(overlays: overlays) }
        .environment(\.nextLibrary, library)
        .environment(\.nextStyle, style)
        .tint(style.accent)
        .background(NX.paper)
        .background { NextKeyMonitorHost(library: library, overlays: overlays) }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) {
            width = $0
            adaptSidebar()
        }
        .onChange(of: env.navigator.openTaskID) { adaptSidebar() }
        // Back/Forward, reveals and deletions change the route without `go`.
        .onChange(of: env.navigator.route) {
            env.workbench.routeDidChange()
            settleRevealedLists()
        }
        .onChange(of: revealedDocuments) { settleRevealedLists() }
    }

    /// A search result shows a task list as a document to reveal a note in it.
    /// Leaving the list turns it back into a task list, unless you picked its
    /// presentation while there.
    private func settleRevealedLists() {
        let navigator = env.navigator
        for id in overlays.revealedDocuments {
            if navigator.listViewMode(for: id) != .document {
                overlays.revealedDocuments.remove(id)
            } else if navigator.route != .list(id) {
                overlays.revealedDocuments.remove(id)
                navigator.setListViewMode(.tasks, for: id)
            }
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
                NextNotices()
                NextRoutedScreen()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            }

            // The panel itself is what comes and goes, so it slides by its own
            // width rather than the whole window's.
            ZStack(alignment: .topTrailing) {
                if let inspected {
                    NextInspector(task: inspected)
                        .transition(.move(edge: .trailing))
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

            // Only draws while showing a completion made outside Next's rows.
            NXOutsideCompletionFeedback()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.trailing, inspected == nil ? 0 : 360)
                .zIndex(34)
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
            return "Labels › #\(library.label(id)?.name ?? "")"
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .calendar: return "Calendar"
        case .tasks, .completed: return "Tasks"
        case .lists: return "Lists"
        case .activity, .updates: return "Activity"
        case .trash: return "Trash"
        case .settings: return "Settings"
        }
    }
}

/// Library and link notices that used to sit above the content.
private struct NextNotices: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            if env.localLinks.error != nil { LocalLinkNotice() }
            if env.store.labelMergeUndo != nil || env.store.labelMaintenanceError != nil { LabelMergeNotice() }
            ReminderNavigationNotice()
            // Successful trash and restore report in the tray; only failures stay pinned here.
            if env.store.trashError != nil { TrashNotice() }
        }
    }
}

/// Picks the screen for the current route.
private struct NextRoutedScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library

    var body: some View {
        let workbench = env.workbench
        let navigator = env.navigator
        Group {
            switch navigator.route {
            case .inbox:
                if navigator.hasDocumentEditor, let inboxID = navigator.inboxListID {
                    InboxScreen()
                        .modifier(NXNoRows())
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            SelectionActionsBar(scopeID: navigator.rowSelection.scopeID)
                        }
                        // The Inbox document has no mode picker of its own.
                        .overlay(alignment: .topTrailing) {
                            NXViewModeButton(listID: inboxID, showsTitle: true)
                                .padding(.top, 18)
                                .padding(.trailing, 22)
                        }
                } else {
                    NextInboxScreen()
                }
            case .today: NextTodayScreen()
            case .calendar: NextCalendarScreen()
            case .tasks: NextTasksScreen()
            case .completed:
                NextTasksScreen().onAppear { workbench.tasksStatus = .done }
            case .updates, .activity: NextActivityScreen()
            case .lists: NextListsGallery()
            case .trash: NextTrashScreen()
            case .settings: NextSettingsScreen()
            case let .list(id):
                if let list = library.list(id) ?? env.store.list(id: id) {
                    if navigator.listViewMode(for: id) == .document {
                        ListScreen(list: list)
                            .modifier(NXNoRows())
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                SelectionActionsBar(scopeID: navigator.rowSelection.scopeID)
                            }
                    } else {
                        NextListScreen(list: list)
                    }
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
/// measure unless wide, a click-to-clear background and scroll-to-focus.
struct NXPage<Content: View>: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    var wide = false
    /// Row IDs in on-screen order, published for j/k and ⌘A.
    var rowIDs: [UUID] = []
    @ViewBuilder var content: () -> Content
    @State private var appeared = false

    var body: some View {
        let workbench = env.workbench
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
            .background { Color.clear.contentShape(Rectangle()).onTapGesture { clearBackground() } }
            .onChange(of: workbench.focusID) { _, id in
                guard let id, rowIDs.contains(id) else { return }
                withAnimation(style.ease(180)) { proxy.scrollTo(id) }
            }
        }
        .onAppear {
            workbench.visibleIDs = rowIDs
            withAnimation(style.ease(260)) { appeared = true }
        }
        .onChange(of: rowIDs) { _, ids in workbench.visibleIDs = ids }
    }

    private func clearBackground() {
        let workbench = env.workbench
        workbench.focusID = nil
        workbench.tasksQueryFocused = false
        if env.navigator.openTaskID != nil { env.navigator.closeTask() }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

/// Section title used on Lists, Activity and Settings.
struct NXCapsTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.84)
            .textCase(.uppercase)
            .foregroundStyle(NX.ink(0.36))
    }
}

/// Dashed empty box used by Calendar and Trash.
struct NXDashedEmpty: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(NX.ink(0.42))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .padding(.horizontal, 16)
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(NX.ink(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
