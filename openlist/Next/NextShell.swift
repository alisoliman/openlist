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
    @Query(filter: #Predicate<Block> { $0.trashID != nil }) private var trashedBlocks: [Block]
    @Query(filter: #Predicate<TaskList> { $0.trashID != nil }) private var trashedLists: [TaskList]

    var body: some View {
        let library = NextLibrary(lists: allLists, sections: sections, labels: labels, tasks: tasks)
        let style = env.workbench.style
        HStack(spacing: 0) {
            NextSidebar(trashCount: trashCount)
            NextMain()
        }
        .overlay { NextOverlays() }
        .environment(\.nextLibrary, library)
        .environment(\.nextStyle, style)
        .tint(style.accent)
        .background(NX.paper)
        .background { NextKeyMonitorHost(library: library) }
    }

    private var trashCount: Int {
        trashedBlocks.filter { $0.trashID == $0.id }.count + trashedLists.filter { $0.trashID == $0.id }.count
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

            if let inspected {
                NextInspector(task: inspected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.top, 52)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(30)
            }

            NXBottomBars()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.trailing, inspected == nil ? 0 : 360)
                .allowsHitTesting(workbench.tray != nil || !workbench.selection.isEmpty)
                .zIndex(35)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NX.paper)
        .animation(style.ease(280), value: inspected?.id)
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
        Group {
            switch env.navigator.route {
            case .inbox: NextInboxScreen()
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
                    if workbench.documentListIDs.contains(id) {
                        ListScreen(list: list)
                    } else {
                        NextListScreen(list: list)
                    }
                } else {
                    MissingContentView(message: "This list no longer exists.")
                }
            case let .label(id):
                if let label = library.label(id) {
                    NextLabelScreen(label: label)
                } else {
                    MissingContentView(message: "This label no longer exists.")
                }
            }
        }
        .id(env.navigator.route)
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
