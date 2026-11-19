//
//  PhoneRootView.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI
import UIKit

/// The shell over the live library. The dock and iPad sidebar share the
/// scene's navigation, sheets and covers (`PhoneNavigator.Place`).
struct PhoneRootView: View {
    var body: some View {
        PhoneLibraryHost { PhoneShell() }
    }
}

private struct PhoneShell: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion
    @Environment(\.undoManager) private var undoManager
    @Environment(\.horizontalSizeClass) private var widthClass
    @State private var bottomSafeArea: CGFloat = 34
    @State private var sidebarVisibility = NavigationSplitViewVisibility.all
    /// The keyboard is up: the dock goes behind it, as a tab bar does,
    /// rather than riding above it and taking the rows' room.
    @State private var isKeyboardUp = false
    /// Where the phone was, for the system to put back if it ends the app in
    /// the background.
    @SceneStorage("phone.place") private var savedPlace: Data?

    var body: some View {
        @Bindable var navigator = env.navigator
        Group {
            if usesSidebar {
                PadWorkspace(sidebarVisibility: $sidebarVisibility,
                             trayBottom: trayLift(showsDock: false, screenBar: navigator.showsScreenBar && !isKeyboardUp))
            } else {
                dockWorkspace
            }
        }
        .overlay(alignment: .top) { PhoneNoticeBanner() }
        .background { KeyboardShortcuts(usesSidebar: usesSidebar) }
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
        // Capture and Settings are sheets: a task to finish, and options to
        // set, over the screen they came from. Settings has its own stack and
        // keeps every change as it's made, so a swipe down loses nothing.
        .sheet(item: $navigator.sheet) { sheet in
            PhoneSheetContent(sheet: sheet)
                .environment(env)
                .environment(\.phoneLibrary, library)
                .environment(\.olStyle, style)
                .environment(\.appClock, env.clock)
        }
        .fullScreenCover(item: $navigator.cover) { cover in
            PhoneCoverContent(cover: cover)
                .environment(env)
                .environment(\.phoneLibrary, library)
                .environment(\.olStyle, style)
                .environment(\.appClock, env.clock)
        }
        #if DEBUG
        .modifier(ComponentGalleryPresenter())
        #endif
        .environment(\.olStyle, style)
        .environment(\.appClock, env.clock)
        .environment(\.calendar, env.settings.calendar)
        .environment(\.olDockDrop, dockDrop)
        .tint(OL.accent)
        .preferredColorScheme(env.settings.appearance.colorScheme)
        .onAppear {
            env.actions.sceneUndoManager = undoManager
            env.windowAppeared(restoring: savedPlace)
        }
        .onChange(of: undoManager) { _, manager in env.actions.sceneUndoManager = manager }
        .onChange(of: navigator.place) { _, place in savedPlace = try? JSONEncoder().encode(place) }
    }

    private var usesSidebar: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && widthClass == .regular
    }

    private var dockWorkspace: some View {
        let environment = env
        @Bindable var navigator = environment.navigator
        let showsDock = navigator.showsDock && !isKeyboardUp
        return TabView(selection: $navigator.tab) {
            ForEach(PhoneTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) {
                    PhoneTabStack(tab: tab, env: environment)
                        .toolbarVisibility(.hidden, for: .tabBar)
                        // The inset below doesn't pass through to the tab's scroll view.
                        .environment(\.olDockRoom, showsDock ? OLMetrics.dockHeight - dockDrop : 0)
                        .environment(\.olScrollToTop, navigator.scrollToTopRequests(for: tab))
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsDock {
                DockHost()
                    // Let the dock sit 28 pt above the screen's edge.
                    .offset(y: dockDrop)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(style.fading(.snappy(duration: 0.3)), value: showsDock)
        .overlay(alignment: .bottom) {
            TrayHost(announces: navigator.sheet == nil && navigator.cover == nil)
                .padding(.bottom, trayLift(showsDock: showsDock, screenBar: navigator.showsScreenBar && !isKeyboardUp))
        }
    }

    private var style: OLStyle {
        OLStyle(reduceMotion: env.settings.reducesMotion || systemReducesMotion,
                haptics: env.settings.playsHaptics,
                dwell: Double(min(8, max(2, env.settings.undoDwellSeconds))))
    }

    /// Negative on phones without a home indicator: lift the dock to keep
    /// the same 28-point gap above the physical screen edge on every phone.
    private var dockDrop: CGFloat { usesSidebar ? 0 : bottomSafeArea - OLMetrics.dockBottom }

    /// 12 pt above the dock, or above a screen's own bottom bar, else 32 pt
    /// above the screen's edge.
    private func trayLift(showsDock: Bool, screenBar: Bool) -> CGFloat {
        if showsDock { return OLMetrics.dockHeight + 12 - dockDrop }
        if screenBar { return OLMetrics.trayAboveScreenBar - dockDrop }
        return max(0, 32 - bottomSafeArea)
    }
}

/// A tab's navigation stack. Every pushed route can land on any tab.
struct PhoneTabStack: View {
    let tab: PhoneTab
    let env: PhoneEnvironment
    let acceptsPathChanges: () -> Bool
    @Environment(\.olStyle) private var style
    @Environment(\.showsWorkspaceToolbar) private var showsWorkspaceToolbar

    init(tab: PhoneTab, env: PhoneEnvironment, acceptsPathChanges: @escaping () -> Bool = { true }) {
        self.tab = tab
        self.env = env
        self.acceptsPathChanges = acceptsPathChanges
    }

    var body: some View {
        let navigator = env.navigator
        NavigationStack(path: Binding(get: { navigator.path(for: tab) }, set: {
            guard acceptsPathChanges() else { return }
            navigator.setPath($0, for: tab)
        })) {
            page(root)
                .navigationDestination(for: PhoneRoute.self) { route in
                    page(PhoneScreen(route: route))
                }
        }
    }

    private func page(_ content: some View) -> some View {
        content
            .environment(env)
            .environment(\.showsWorkspaceToolbar, showsWorkspaceToolbar)
            .navigationBarBackButtonHidden(showsWorkspaceToolbar)
            .toolbar {
                if showsWorkspaceToolbar { PadWorkspaceToolbar(navigator: env.navigator) }
            }
    }

    @ViewBuilder private var root: some View {
        switch tab {
        case .today:
            // The list and the timeline cross-fade as the toggle slides.
            Group {
                if env.navigator.todayMode == .timeline { TimelineScreen() } else { TodayScreen() }
            }
            .transition(.opacity)
            .animation(style.fading(.easeInOut(duration: 0.22)), value: env.navigator.todayMode)
        case .inbox: InboxScreen()
        case .lists: ListsScreen()
        case .work: TimelineScreen(forWork: true)
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
        case let .taskHistory(id): TaskHistoryScreen(taskID: id)
        case .inbox: InboxScreen()
        case .triage: TriageScreen()
        case .lists: ListsScreen()
        case .work: TimelineScreen(forWork: true)
        case let .list(id): ListPageScreen(listID: id)
        case let .find(query): FindScreen(query: query)
        case .settings: SettingsScreen()
        case .trash: TrashScreen()
        case .planHours: PlanHoursScreen()
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
            .overlay(alignment: .top) { PhoneNoticeBanner() }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        case let .capture(request):
            CaptureScreen(request: request, draft: env.navigator.captureDraft,
                          spoken: env.navigator.capturedSpoken)
                .olSheet()
        }
    }
}

/// A cover's screen, with its own stack: a task opened from Working pushes
/// over the timer, and Back comes back to it.
private struct PhoneCoverContent: View {
    let cover: PhoneCover
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        @Bindable var navigator = env.navigator
        NavigationStack(path: $navigator.coverPath) {
            Group {
                switch cover {
                case .working: WorkingScreen()
                case .triage: TriageScreen()
                }
            }
            .navigationDestination(for: PhoneRoute.self) { PhoneScreen(route: $0) }
        }
        .overlay(alignment: .bottom) { TrayHost(announces: true).padding(.bottom, OLMetrics.trayAboveScreenBar) }
        .overlay(alignment: .top) { PhoneNoticeBanner() }
    }
}

/// A hardware keyboard's way round: ⌘1–⌘4 for the tabs, ⌘N for a new task,
/// ⌘F for Find and ⌘, for Settings, as the dock and Lists offer them. They
/// stand down while a sheet or cover is up, whose own keys (Esc, ⌘↩) work,
/// and while a mode such as Select has the dock's place.
private struct KeyboardShortcuts: View {
    let usesSidebar: Bool
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let navigator = env.navigator
        ZStack {
            ForEach(Array(PhoneTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { navigator.select(tab) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Button("New task") { navigator.open(.capture(navigator.captureRequest)) }
                .keyboardShortcut("n")
            Button("Find") {
                if usesSidebar { navigator.show(.find("")) } else { navigator.open(.find("")) }
            }
            .keyboardShortcut("f")
            Button("Settings") { navigator.open(.settings) }
                .keyboardShortcut(",")
        }
        .disabled(navigator.sheet != nil || navigator.cover != nil || !navigator.dockHiders.isEmpty)
        .opacity(0)
        .allowsHitTesting(false)
        // Keys only: VoiceOver reaches all of these on screen already.
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
    }
}

/// The dock, with what the Inbox has to triage, as its screen counts it, and
/// the list the + captures into.
private struct DockHost: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library

    var body: some View {
        let navigator = env.navigator
        OLDock(tab: Binding(get: { navigator.tab }, set: { navigator.select($0) }),
               inboxCount: library.inboxQueue(triage: env.triage, closing: env.actions.closing, now: env.now).count,
               captureLabel: captureLabel,
               reselect: { navigator.select($0) },
               captureByVoice: {
                   var request = navigator.captureRequest
                   request.listens = true
                   navigator.open(.capture(request))
               },
               capture: { navigator.open(.capture(navigator.captureRequest)) })
    }

    private var captureLabel: String {
        guard let listID = env.navigator.captureRequest.listID, let list = env.store.list(id: listID),
              !list.isEffectivelyArchived else { return "New task" }
        return "New task in \(list.displayTitle)"
    }
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
        // The outgoing toast crosses the dock while animating away. Once
        // dismissed it must not swallow a tap intended for the tab below.
        .allowsHitTesting(tray.message != nil)
        .animation(style.fading(.snappy(duration: 0.3)), value: tray.message?.id)
    }
}
