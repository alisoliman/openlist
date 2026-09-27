//
//  PhoneRootView.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI
import UIKit

/// The shell every screen sits in: a navigation stack per tab, the floating
/// dock, the tray, and the sheets and covers on top.
struct PhoneRootView: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion
    @Environment(\.undoManager) private var undoManager
    @State private var bottomSafeArea: CGFloat = 34
    /// The keyboard is up: the dock goes behind it, as a tab bar does,
    /// rather than riding above it and taking the rows' room.
    @State private var isKeyboardUp = false

    var body: some View {
        @Bindable var navigator = env.navigator
        let showsDock = navigator.showsDock && !isKeyboardUp
        TabView(selection: $navigator.tab) {
            ForEach(PhoneTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) {
                    PhoneTabStack(tab: tab)
                        .toolbarVisibility(.hidden, for: .tabBar)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsDock {
                DockHost()
                    // The design's dock sits 28 pt above the screen's edge,
                    // a little into the home indicator's safe area.
                    .offset(y: max(0, bottomSafeArea - OLMetrics.dockBottom))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(style.fading(.snappy(duration: 0.3)), value: showsDock)
        .overlay(alignment: .bottom) {
            TrayHost(announces: navigator.sheet == nil && navigator.cover == nil)
                .padding(.bottom, trayLift(showsDock: showsDock, screenBar: navigator.showsScreenBar && !isKeyboardUp))
        }
        .overlay(alignment: .top) { PhoneNoticeBanner() }
        .background {
            // The home indicator's inset, never the keyboard's.
            GeometryReader { proxy in
                Color.clear.onAppear { bottomSafeArea = proxy.safeAreaInsets.bottom }
                    .onChange(of: proxy.safeAreaInsets.bottom) { _, value in bottomSafeArea = value }
            }
            .ignoresSafeArea(.keyboard)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardUp = false
        }
        .sheet(item: $navigator.sheet) { sheet in
            PhoneSheetContent(sheet: sheet)
                .environment(env)
                .environment(\.olStyle, style)
                .environment(\.appClock, env.clock)
        }
        .fullScreenCover(item: $navigator.cover) { cover in
            PhoneCoverContent(cover: cover)
                .environment(env)
                .environment(\.olStyle, style)
                .environment(\.appClock, env.clock)
        }
        #if DEBUG
        .modifier(ComponentGalleryPresenter())
        #endif
        .environment(\.olStyle, style)
        .environment(\.appClock, env.clock)
        .environment(\.calendar, env.settings.calendar)
        .tint(OL.accent)
        .preferredColorScheme(env.settings.appearance.colorScheme)
        .onAppear {
            env.actions.sceneUndoManager = undoManager
            env.links.windowReady(true)
        }
        .onChange(of: undoManager) { _, manager in env.actions.sceneUndoManager = manager }
    }

    private var style: OLStyle {
        OLStyle(reduceMotion: env.settings.reducesMotion || systemReducesMotion,
                haptics: env.settings.playsHaptics,
                dwell: Double(min(8, max(2, env.settings.undoDwellSeconds))))
    }

    /// 12 pt above the dock, or above a screen's own bottom bar, else 32 pt
    /// above the screen's edge.
    private func trayLift(showsDock: Bool, screenBar: Bool) -> CGFloat {
        if showsDock { return OLMetrics.dockHeight + 12 - max(0, bottomSafeArea - OLMetrics.dockBottom) }
        if screenBar { return OLMetrics.trayAboveScreenBar }
        return max(0, 32 - bottomSafeArea)
    }
}

/// A tab's navigation stack. Every pushed route can land on any tab.
struct PhoneTabStack: View {
    let tab: PhoneTab
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let navigator = env.navigator
        NavigationStack(path: Binding(get: { navigator.path(for: tab) }, set: { navigator.setPath($0, for: tab) })) {
            root
                .navigationDestination(for: PhoneRoute.self) { PhoneScreen(route: $0) }
        }
    }

    @ViewBuilder private var root: some View {
        switch tab {
        case .today:
            if env.navigator.todayMode == .timeline { TimelineScreen() } else { TodayScreen() }
        case .inbox: InboxScreen()
        case .lists: ListsScreen()
        }
    }
}

/// The screen for a route, wherever it's shown.
struct PhoneScreen: View {
    let route: PhoneRoute

    var body: some View {
        switch route {
        case .today: TodayScreen()
        case .timeline: TimelineScreen()
        case .activity: ActivityScreen()
        case let .taskDetail(id): TaskDetailScreen(taskID: id)
        case .inbox: InboxScreen()
        case .triage: TriageScreen()
        case .lists: ListsScreen()
        case let .list(id): ListPageScreen(listID: id)
        case let .find(query): FindScreen(query: query)
        case .settings: SettingsScreen()
        case .trash: TrashScreen()
        case .working: WorkingScreen()
        case let .capture(request): CaptureScreen(request: request)
        }
    }
}

private struct PhoneSheetContent: View {
    let sheet: PhoneSheet
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        switch sheet {
        case .settings:
            @Bindable var navigator = env.navigator
            NavigationStack(path: $navigator.settingsPath) {
                SettingsScreen()
                    .navigationDestination(for: PhoneRoute.self) { PhoneScreen(route: $0) }
            }
            .overlay(alignment: .bottom) { TrayHost(announces: true).padding(.bottom, 0) }
        case let .capture(request):
            CaptureScreen(request: request)
                .olSheet()
        }
    }
}

private struct PhoneCoverContent: View {
    let cover: PhoneCover

    var body: some View {
        Group {
            switch cover {
            case .working: WorkingScreen()
            case .triage: TriageScreen()
            }
        }
        .overlay(alignment: .bottom) { TrayHost(announces: true).padding(.bottom, OLMetrics.trayAboveScreenBar) }
    }
}

/// The dock, with the Inbox's count and the list the + captures into.
private struct DockHost: View {
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let navigator = env.navigator
        InboxCount(inboxID: navigator.inboxListID) { count in
            OLDock(tab: Binding(get: { navigator.tab }, set: { navigator.select($0) }),
                   inboxCount: count,
                   captureLabel: captureLabel,
                   reselect: { navigator.select($0) },
                   capture: { navigator.open(.capture(navigator.captureRequest)) })
        }
    }

    private var captureLabel: String {
        guard let listID = env.navigator.captureRequest.listID, let list = env.store.list(id: listID) else { return "New task" }
        return "New task in \(list.displayTitle)"
    }
}

/// Open tasks in the Inbox, live as CloudKit imports and edits land.
private struct InboxCount<Content: View>: View {
    @Query private var tasks: [Block]
    private let content: (Int) -> Content

    init(inboxID: UUID?, @ViewBuilder content: @escaping (Int) -> Content) {
        let id = inboxID ?? UUID()
        let task = BlockKind.task.rawValue
        _tasks = Query(filter: #Predicate<Block> {
            $0.listID == id && $0.kindRaw == task && !$0.isCompleted && $0.trashID == nil
        })
        self.content = content
    }

    var body: some View { content(tasks.count) }
}

/// The app's tray, where the view it's in draws it.
struct TrayHost: View {
    var announces = true
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.olStyle) private var style

    var body: some View {
        let tray = env.tray
        ZStack {
            if let message = tray.message {
                OLTrayView(message: message, action: { tray.performAction() }, dismiss: { tray.dismiss(message.id) },
                           announces: announces)
                    .id(message.id)
                    .padding(.horizontal, OLMetrics.gutter)
                    .transition(style.reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(style.fading(.snappy(duration: 0.3)), value: tray.message?.id)
    }
}
