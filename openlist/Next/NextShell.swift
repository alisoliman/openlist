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
    /// The width again, for the page's column, read apart from this body so
    /// a live resize doesn't draw the library again.
    @State private var room = NXPageRoomSource()

    var body: some View {
        let library = drawnLibrary()
        let style = env.workbench.style
        let showsSidebar = env.workbench.showsSidebar
        HStack(spacing: 0) {
            // Folded or hidden, the sidebar stays mounted with no width, so a
            // rename in progress keeps its draft and commits as it loses focus.
            NextSidebar()
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { overlays.sidebarFrame = $0 }
                .frame(width: showsSidebar ? nil : 0, alignment: .trailing)
                .clipped()
                .disabled(!showsSidebar)
                .allowsHitTesting(showsSidebar)
                .accessibilityHidden(!showsSidebar)
            // The overlays dim and centre on the main pane; the sidebar stays clear.
            NXPageRoomReader(source: room, showsSidebar: showsSidebar, content: NextMain())
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
            room.windowWidth = $0
            adaptSidebar()
        }
        .onChange(of: env.navigator.openTaskID) { _, id in
            if id == nil { env.workbench.isTaskPageOpen = false }
            adaptSidebar()
        }
        .onChange(of: env.workbench.isTaskPageOpen) { adaptSidebar() }
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

    /// A narrow window gives the page the sidebar's room while the inspector
    /// takes its right, and gets the sidebar back once the inspector closes
    /// or there's room again; a native extra. The inspector squeezes the page
    /// rather than covering it, so what folding helps is the page's width
    /// beside the sidebar and the 360pt inspector. It folds only while the
    /// page would be narrower than the inspector, under 956pt, where past its
    /// 40pt margins rows show less than 280pt, and comes back 120pt wider,
    /// so a resize doesn't flip it. View ▸ Hide Sidebar is separate, so this
    /// never shows a sidebar the user hid. The task opened out as a page
    /// takes the pane's room rather than squeezing it.
    private func adaptSidebar() {
        let workbench = env.workbench
        let inspecting = !workbench.isTaskPageOpen && env.navigator.openTaskID.flatMap { env.store.block(id: $0) }
            .map { $0.isTask && $0.trashID == nil } ?? false
        let page = width - 236 - 360
        var folded = workbench.isSidebarFoldedForRoom
        if inspecting && page < 360 { folded = true }
        else if !inspecting || page >= 480 { folded = false }
        guard folded != workbench.isSidebarFoldedForRoom else { return }
        if folded { endSidebarEditing() }
        withAnimation(workbench.style.ease(280)) { workbench.isSidebarFoldedForRoom = folded }
    }

    /// Ends a rename in the sidebar as it folds, so the name is saved rather
    /// than left in a field nobody can see.
    private func endSidebarEditing() {
        if overlays.editsSidebarField() { overlays.host?.window?.makeFirstResponder(nil) }
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
        let paged = inspected != nil && workbench.isTaskPageOpen
        VStack(spacing: 0) {
            // The page ends the crumb with the task it shows.
            NextToolbar(crumb: paged ? crumb + " › " + (inspected?.displayTitle ?? "") : crumb)
            // The inspector takes the right of the window under the toolbar,
            // and the page gives it the room instead of going under it.
            HStack(spacing: 0) {
                ZStack {
                    VStack(spacing: 0) {
                        NextNotices()
                        ZStack {
                            // Opened out, the task takes the screen's place, which
                            // stays laid out and scrolled underneath for its return.
                            NextRoutedScreen()
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .clipped()
                                .opacity(paged ? 0 : 1)
                                .allowsHitTesting(!paged)
                                .accessibilityHidden(paged)
                            if paged, let inspected {
                                NextInspector(task: inspected, isPage: true)
                            }
                        }
                    }
                    NXBottomBars()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(workbench.tray != nil || !workbench.selection.isEmpty)
                        .zIndex(35)
                }
                if !paged, let inspected {
                    NextInspector(task: inspected)
                        .transition(style.slide(.move(edge: .trailing)))
                        .zIndex(30)
                }
            }
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

/// The scrolling page every screen sits in: 26/40/120 padding, the full
/// width beside the sidebar and inspector up to a reading measure, past which
/// the column is centred so a row's chips stay in reach of its title on a
/// wide display (Calendar, Lists and Activity use every point; see
/// `NXReadingColumn`), a click-to-clear background, scroll-to-focus,
/// scrolling to what a search hit or link reveals in a list document, and,
/// as a native extra, the place Back and Forward return it to.
struct NXPage<Content: View>: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    /// The widest the column gets; nil fills the page.
    var measure: CGFloat? = NXPageMeasure.reading
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
                NXReadingColumnView(measure: measure.map { $0 + 80 }) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id(ContentReveal.Anchor.pageHeader)
                        content()
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.top, 26)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 120)
                }
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

enum NXPageMeasure {
    /// Wide enough that a window of the design's size never reaches it.
    static let reading: CGFloat = 1120
}

/// The window's width, for the page's reading column.
@Observable @MainActor
final class NXPageRoomSource {
    var windowWidth: CGFloat = 0
}

/// Hands the main pane its page's room, the window's width less the
/// sidebar's. Only this reads the width, so a resize updates it and the
/// column, and the sidebar's slide moves a centred column with it.
private struct NXPageRoomReader<Content: View>: View {
    let source: NXPageRoomSource
    let showsSidebar: Bool
    let content: Content

    var body: some View {
        content.environment(\.nxPageRoom, max(0, source.windowWidth - (showsSidebar ? 236 : 0)))
    }
}

/// `NXReadingColumn` with the room read here, so a change of room lays the
/// column out again without drawing the page's content again.
struct NXReadingColumnView<Content: View>: View {
    @Environment(\.nxPageRoom) private var room
    let measure: CGFloat?
    let content: Content

    init(measure: CGFloat?, @ViewBuilder content: () -> Content) {
        self.measure = measure
        self.content = content()
    }

    var body: some View {
        NXReadingColumn(measure: measure, room: room) { content }
    }
}

private struct NXPageRoomKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// The page's width with no inspector docked, which its column centres in.
    var nxPageRoom: CGFloat {
        get { self[NXPageRoomKey.self] }
        set { self[NXPageRoomKey.self] = newValue }
    }
}

/// Lays the page's padded column out at most `measure` wide, centred in the
/// `room` the page has with no inspector. Docking the inspector takes its
/// width from the right: the column narrows where it stands, and moves left
/// only to keep a readable width, so the row just clicked stays under the
/// pointer. A page within the measure fills its width, as before.
private struct NXReadingColumn: Layout {
    let measure: CGFloat?
    let room: CGFloat
    /// The narrowest the column gets before it gives up its centring: 640pt
    /// of rows inside the page's 40pt margins.
    private static let readable: CGFloat = 720

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        guard let width = proposal.width else { return child.sizeThatFits(proposal) }
        let column = column(in: width)
        let size = child.sizeThatFits(ProposedViewSize(width: column.width, height: proposal.height))
        return CGSize(width: width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let column = column(in: bounds.width)
        child.place(at: CGPoint(x: bounds.minX + column.x, y: bounds.minY),
                    proposal: ProposedViewSize(width: column.width, height: bounds.height))
    }

    private func column(in width: CGFloat) -> (x: CGFloat, width: CGFloat) {
        guard let measure else { return (0, width) }
        let centred = max(0, (max(room, width) - measure) / 2)
        let x = min(centred, max(0, width - min(measure, Self.readable)))
        return (x, max(0, min(measure, width - x)))
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
/// Inbox's triage card: the design's 600 10.5/1, on exact 10.5pt lines,
/// which trim SwiftUI's 13 from below, so a title that wraps stacks at 10.5
/// a line. Raised by half the trim, and by the half point lower an exact
/// line sets a half-point size's baseline, one line inks where it did.
/// VoiceOver reads it as a heading.
struct NXCapsTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .accessibilityAddTraits(.isHeader)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.735)
            .textCase(.uppercase)
            .foregroundStyle(NX.textTertiary)
            .lineHeight(.exact(points: 10.5))
            .offset(y: (10.5 - NX.lineHeight(10.5)) / 2 - 0.5)
    }
}

/// The design's Trash box ("Trash is empty."), for the empty and failed
/// states of a page: 400 13/1.5, 34 pt in from a 1 pt dashed
/// border, radius 14, fading in over 240ms whenever it appears.
struct NXDashedEmpty: View {
    let text: String
    @State private var shown = false

    var body: some View {
        // The extra leading between lines and, halved, above the first and below the last.
        let leading = 13 * 1.5 - NX.lineHeight(13)
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(NX.textQuaternary)
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
