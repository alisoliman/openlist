//
//  PhoneEnvironment.swift
//  OpenlistiOS
//

import Foundation
import Observation
import SwiftData
import SwiftUI

/// The iPhone's composition root: the Store and everything that keeps it,
/// the widgets, reminders and sync in step, created once at launch.
///
/// It repeats the Mac's startup and sync steps (`AppEnvironment`), because
/// sync correctness comes from running the same Store code the same way:
/// bootstrap from the delegate and the first scene, reconcile after every
/// CloudKit import, and save before the app is suspended. What the Mac does
/// with windows, menus and its Workbench, the phone does with
/// `PhoneNavigator` and `PhoneActions`.
@Observable
@MainActor
final class PhoneEnvironment {
    /// Moments in the app's life a feature can follow (see `on(_:_:)`).
    enum Lifecycle: Hashable {
        /// The library is open and reconciled, the calendar running.
        case bootstrapped
        /// The scene came to the front.
        case becameActive
        /// The scene is about to leave the front; drafts are committed after this.
        case willResignActive
        /// Another device's changes were merged in.
        case remoteChange
    }

    let store: Store
    let settings: AppSettings
    let taskSwipes: TaskSwipePreferences
    /// Only one task's swipe shortcuts stay revealed at a time.
    var openSwipeTaskID: UUID?
    let sync: ICloudSyncMonitor
    let calendar: CalendarCoordinator
    let navigator: PhoneNavigator
    let actions: PhoneActions
    let links: PhoneLinkRouter
    let clock: AppClock
    /// The Inbox's triage pass: what it set aside and how far it's got.
    let triage = TriageSession()
    /// The pass through the lists' tasks with no date, kept the same way.
    let undatedTriage = TriageSession()
    /// This device's library identity, which item links carry.
    let libraryID: UUID?

    var tray: TrayCenter { actions.tray }
    var haptics: PhoneHaptics { actions.haptics }
    /// The environment's time: pass it to the Store's `now:` parameters.
    var now: Date { clock.now }

    private(set) var hasBootstrapped = false
    /// Whether the scene is in front.
    private(set) var isActive = false
    /// Whether the window has shown, its saved place put back: links wait
    /// for it, so one that launched the app lands on top of that place.
    private(set) var hasShownWindow = false
    /// How many remote changes have been merged in, for diagnostics and tests.
    private(set) var remoteChangeCount = 0
    /// How many times the app has saved on its way to the background.
    private(set) var backgroundSaveCount = 0

    @ObservationIgnored private let platform: PhonePlatform
    @ObservationIgnored private let widgetPublisher: WidgetSnapshotPublisher
    @ObservationIgnored private let widgetCommands: WidgetCommandProcessor
    /// Retained so the notification centre keeps a live delegate.
    @ObservationIgnored private let notificationDelegate = NotificationDelegate()
    @ObservationIgnored private let presence: WorkPresenceHook
    @ObservationIgnored private let seedsReviewFixture: Bool
    @ObservationIgnored private var handlers: [Lifecycle: [() -> Void]] = [:]
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// The work Live Activity, for the app's own environment only.
    @ObservationIgnored private var liveActivity: PhoneLiveActivity?

    /// - Parameters:
    ///   - seedsReviewFixture: whether an empty review-session library gets the
    ///     iPhone fixture on bootstrap. Tests that want an empty one say no.
    ///   - calendarDefaults: the calendar's per-device preferences and device ID.
    init(context: ModelContext, sync: ICloudSyncMonitor, libraryID: UUID?,
         settings: AppSettings = AppSettings(), clock: AppClock = .forLaunch(),
         platform: PhonePlatform = .live, seedsReviewFixture: Bool = true,
         calendarDefaults: UserDefaults = ReviewSession.defaults) {
        let store = Store(context: context)
        let presence = WorkPresenceHook()
        self.store = store
        self.settings = settings
        taskSwipes = TaskSwipePreferences(defaults: calendarDefaults)
        self.sync = sync
        self.clock = clock
        self.libraryID = libraryID
        self.platform = platform
        self.presence = presence
        self.seedsReviewFixture = seedsReviewFixture
        // Before any task changes: it gives the Store this device's ID, the
        // day's planned slots and the default estimate, which completions and
        // work sessions record. An iPhone app is suspended while its user
        // works, so a gap in the clock is no reason to pause.
        // A review session's calendar is the fixture's: the mockups' meetings,
        // never the Mac's or the simulator's own calendars.
        let meetings = seedsReviewFixture ? Self.reviewMeetings(defaults: calendarDefaults, now: clock.now) : nil
        calendar = CalendarCoordinator(store: store, defaults: calendarDefaults, externalCalendars: meetings,
                                       presence: WorkPresencePolicy(pausesAfterClockGap: false,
                                                                    adoptsOpenSession: { [presence] session in presence.adopts(session) }))
        navigator = PhoneNavigator()
        actions = PhoneActions(store: store, settings: settings, calendar: calendar, clock: clock)
        links = PhoneLinkRouter(store: store, navigator: navigator, libraryID: libraryID)
        widgetPublisher = WidgetSnapshotPublisher(store: store, sources: .live(
            calendar: calendar, settings: settings, libraryID: libraryID, isAppActive: platform.isAppActive))
        widgetCommands = WidgetCommandProcessor(store: store, calendar: calendar, publisher: widgetPublisher, actions: actions)
        wire()
    }

    /// A review session's calendar: the fixture's meetings, as the Mac's
    /// review copies have theirs. For the empty states, `OpenlistReviewMeetings`
    /// in the launch environment says `NO`, for no calendar connected (the
    /// device's own, which a review session never connects), or `none`, for a
    /// connected calendar with nothing on it; `links` gives the meetings links
    /// for places, as online meetings have. Nil outside review sessions.
    static func reviewMeetings(defaults: UserDefaults, now: Date,
                               environment: [String: String] = ProcessInfo.processInfo.environment) -> ExternalCalendarSource? {
        guard ReviewSession.identifier != nil else { return nil }
        switch environment["OpenlistReviewMeetings"] {
        case "NO": return nil
        case "none": return ExternalCalendarSource(defaults: defaults, fixtureBusyTimes: [])
        case "links": return ExternalCalendarSource(defaults: defaults, fixtureBusyTimes: PhoneFixture.meetings(now: now, links: true))
        default: return ExternalCalendarSource(defaults: defaults, fixtureBusyTimes: PhoneFixture.meetings(now: now))
        }
    }

    /// Whether bootstrap carries on this device's open work session instead of
    /// pausing it at its last heartbeat, as the Mac does: while its Live
    /// Activity still shows, the work went on, and so does the review
    /// fixture's session.
    var adoptsOpenWorkSession: (WorkSession) -> Bool {
        get { presence.adopts }
        set { presence.adopts = newValue }
    }

    /// Runs `handler` at each `moment`, after the environment's own work.
    func on(_ moment: Lifecycle, _ handler: @escaping () -> Void) {
        handlers[moment, default: []].append(handler)
    }

    private func notify(_ moment: Lifecycle) {
        for handler in handlers[moment] ?? [] { handler() }
    }

    // MARK: Wiring

    private func wire() {
        store.onDidSave = { [weak self] in
            guard let self else { return }
            widgetPublisher.scheduleRefresh()
            calendar.storeDidChange(now: clock.now)
            liveActivity?.sync()
        }
        // An Undo can take away the list or task a screen is on, or bring
        // back the task whose page closed as it went to Trash.
        actions.afterUndo = { [weak self] in
            guard let self else { return }
            let taskExists: (UUID) -> Bool = { [store] in store.block(id: $0).map { $0.isTask && $0.trashID == nil } ?? false }
            navigator.repair(list: { [store] in store.list(id: $0)?.id }, taskExists: taskExists)
            navigator.reopenTrashedPage(taskExists: taskExists)
        }
        store.onEditorBlocksRemoved = { [weak self] ids in
            guard let self else { return }
            navigator.repair(list: { [store] in store.list(id: $0)?.id },
                             taskExists: { [store] in !ids.contains($0) && store.block(id: $0) != nil })
        }
        // The plan and the running session change without a save. Debounced,
        // because one Start or Pause reports several times on its way through.
        calendar.onWidgetStateChange = { [weak self] in
            self?.widgetPublisher.scheduleRefresh()
            self?.liveActivity?.sync()
        }
        sync.onRemoteChange = { [weak self] in self?.refreshAfterRemoteChange() }
        links.acceptsOtherLibraries = { [weak sync] in sync?.state.isEnabled == true }
        links.unavailable = { [weak self] message in
            self?.tray.show(message, icon: "link", tone: .danger, seconds: 6)
        }
        if platform.installsProcessHooks {
            installNotificationDelegate()
            installWidgetActions()
            liveActivity = PhoneLiveActivity { [weak self] in self }
            presence.adopts = { PhoneLiveActivity.isShowing($0) }
        }
        watchWidgetInputs()
    }

    /// Widget buttons reach the app through the intents' router, installed
    /// first thing: an intent can be what launched the app, and the processor
    /// bootstraps before applying anything.
    private func installWidgetActions() {
        widgetCommands.prepare = { [weak self] in self?.bootstrap() }
        WidgetCommandRouter.handler = { [weak self] command in
            guard let self else { return }
            widgetCommands.handle(command, now: clock.now)
        }
        // Siri and Shortcuts: Add Tasks saves into the library and says so in
        // the tray, with Undo; Say Tasks opens Capture listening.
        TaskIntentHost.library = { [weak self] in
            self?.bootstrap()
            return self?.store
        }
        TaskIntentHost.didAdd = { [weak self] blocks, _ in self?.actions.reportCapture(blocks) }
        TaskIntentHost.open = { [weak self] link in _ = self?.links.receive(link.url) }
    }

    private func installNotificationDelegate() {
        notificationDelegate.onOpenTask = { [weak self] id in self?.links.openTask(id) }
        notificationDelegate.onCalendarAction = { [weak self] action, _, taskID, occurrenceID in
            self?.handleCalendarAction(action, taskID: taskID, occurrenceID: occurrenceID)
        }
        NotificationService.shared.install(delegate: notificationDelegate)
    }

    /// A work nudge's buttons, for the occurrence it was about.
    private func handleCalendarAction(_ action: String, taskID: UUID, occurrenceID: UUID) {
        bootstrap()
        guard let task = store.block(id: taskID), task.isTask, task.occurrenceID == occurrenceID else {
            return links.openTask(taskID)
        }
        switch action {
        case NotificationService.calendarStartAction:
            if calendar.start(task: task, now: clock.now) { navigator.show(.working) }
        case NotificationService.calendarDoneAction:
            actions.complete([task], settleNow: true)
        default:
            links.openTask(taskID)
        }
    }

    /// Refreshes the widgets when something they show changes without a save:
    /// the accent, serif titles, the first weekday and the calendars.
    private func watchWidgetInputs() {
        withObservationTracking {
            _ = (settings.accent, settings.serifTitles, settings.firstWeekday, calendar.externalCalendars.revision)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.widgetPublisher.scheduleRefresh()
                self?.watchWidgetInputs()
            }
        }
    }

    // MARK: Launch

    /// Opens the library for use. Runs from `didFinishLaunching`, because a
    /// silent push can launch the app with no scene, and again from the first
    /// scene; only the first call does anything.
    func bootstrap() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        store.bootstrap()
        if sync.state.isEnabled {
            store.prepareForSync()
        } else if seedsReviewFixture, Self.mayReceiveFixture(store, syncEnabled: sync.state.isEnabled,
                                                              reviewSession: ReviewSession.identifier,
                                                              hasSeeded: settings.hasSeededSampleData) {
            let seeded = PhoneFixture.seed(into: store, settings: settings, now: clock.now)
            #if DEBUG
            ListDocumentFixture.seedIfRequested(into: store, reviewSession: ReviewSession.identifier)
            #endif
            if store.persistenceError == nil {
                settings.hasSeededSampleData = true
                let fixtureSessions = Set(store.workSessions().filter { $0.endedAt == nil }.map(\.id))
                let adopts = presence.adopts
                presence.adopts = { fixtureSessions.contains($0.id) || adopts($0) }
                if let seeded, let session = seeded.workSession { actions.adoptStart(of: session, task: seeded.draftOKRs) }
            }
        }
        store.refreshAllReminders()
        navigator.inboxListID = store.inboxList()?.id
        sync.checkAccount()
        if sync.state.isEnabled { platform.registerForRemoteNotifications() }
        // A pinned clock stops the calendar's own ticks, which read the system clock.
        calendar.bootstrap(now: clock.now, monitorsEnabled: platform.runsCalendarClock && !clock.isPinned)
        // Only now is the work in hand known: a sync before would end the
        // activity of work still running.
        liveActivity?.isReady = true
        // After the calendar, so the first snapshot has the day's plan.
        widgetPublisher.refreshNow(now: clock.now)
        links.storeReady()
        if platform.installsProcessHooks { TaskIntentHost.listsChanged() }
        if platform.installsProcessHooks {
            // Taps the extension queued while the app wasn't running.
            WidgetCommandProcessor.adoptEarlierQueue()
            widgetCommands.listenForSignals()
        }
        widgetCommands.drainQueue(now: clock.now)
        takeSharedCaptures()
        liveActivity?.sync()
        #if DEBUG
        openLaunchRoute()
        #endif
        notify(.bootstrapped)
    }

    /// The Mac's rule for sample data: only an isolated review session's
    /// library, iCloud off, never seeded before, with nothing in it but the
    /// Inbox. Seeding anywhere CloudKit may still be importing would upload
    /// a copy from every device.
    static func mayReceiveFixture(_ store: Store, syncEnabled: Bool, reviewSession: String?, hasSeeded: Bool) -> Bool {
        guard !syncEnabled, reviewSession != nil, !hasSeeded else { return false }
        return store.allLists(includeArchived: true).allSatisfy(\.isSystemInbox)
            && (try? store.context.fetchCount(FetchDescriptor<Block>())) == 0
    }

    #if DEBUG
    /// A review session's `OpenlistOpenRoute`: the screen to open at launch,
    /// for screenshots and UI tests. A tab ("inbox", "lists", "timeline"),
    /// a modal ("settings", "trash", "capture", "voice", "working", "triage",
    /// "triage:undated"), "activity", "find:#travel", or a list or task by
    /// its title ("list:Weekend in Kyoto", "task:Draft Q3 OKRs").
    /// `OpenlistShowTray` puts its text in the tray, with Undo, for a
    /// screenshot of it.
    private func openLaunchRoute(_ environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard ReviewSession.identifier != nil else { return }
        if let text = environment["OpenlistShowTray"], !text.isEmpty {
            tray.show(text, seconds: 600, action: {})
        }
        guard let value = environment["OpenlistOpenRoute"], !value.isEmpty else { return }
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        let name = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "today": navigator.show(.today)
        case "timeline": navigator.show(.timeline)
        case "work": navigator.show(.work)
        case "activity": navigator.show(.activity)
        case "inbox": navigator.show(.inbox)
        case "triage": navigator.show(.triage(TriageMode(rawValue: name) ?? .inbox))
        case "lists": navigator.show(.lists)
        case "find": navigator.show(.find(name))
        case "settings": navigator.open(.settings)
        case "trash": navigator.open(.trash)
        case "working": navigator.show(.working)
        case "capture": navigator.open(.capture(CaptureRequest()))
        case "voice": navigator.open(.capture(CaptureRequest(listens: true)))
        case "list":
            if let list = store.allLists(includeArchived: true).first(where: { $0.displayTitle == name }) {
                navigator.show(list.isSystemInbox ? .inbox : .list(list.id))
            }
        case "task":
            let kind = BlockKind.task.rawValue
            let tasks = (try? store.context.fetch(FetchDescriptor<Block>(
                predicate: #Predicate { $0.kindRaw == kind && $0.text == name }))) ?? []
            if let task = tasks.first(where: { store.block(id: $0.id) != nil }) {
                navigator.show(.taskDetail(task.id), in: store.resolvedListID(task.listID))
            }
        default: break
        }
    }
    #endif

    // MARK: Sync

    /// Merges another device's changes in, as the Mac does after each import:
    /// system records reconciled (a second Inbox becomes an alias of the
    /// first), reminders, plan and widgets refreshed, and screens on something
    /// that's gone or merged moved on.
    func refreshAfterRemoteChange() {
        guard hasBootstrapped else { return }
        remoteChangeCount += 1
        store.context.processPendingChanges()
        // An account change can empty the local mirror; only bootstrap makes
        // an Inbox, and it's a no-op while one exists.
        if store.inboxList() == nil || store.defaultSection() == nil { store.bootstrap() }
        // Its save refreshes reminders, so they need no second pass here.
        store.prepareForSync()
        // A synced Inbox from another device can win the merge and take over.
        navigator.inboxListID = store.inboxList()?.id
        calendar.storeDidChange(now: clock.now)
        widgetPublisher.refreshNow(now: clock.now)
        let shown = navigator.visibleRoute
        navigator.repair(list: { [store] in store.list(id: $0)?.id },
                         taskExists: { [store] in store.block(id: $0).map { $0.isTask && $0.trashID == nil } ?? false })
        // A page that closed under the user says why, rather than a merged
        // list's, which follows the list it merged into.
        if navigator.visibleRoute != shown, let gone = removedPage(shown) {
            tray.show("The \(gone) you had open was removed on another device.", icon: "icloud", tone: .neutral, seconds: 5)
        }
        notify(.remoteChange)
    }

    /// What `route` showed, if that's gone from the library: "task" or "list".
    private func removedPage(_ route: PhoneRoute) -> String? {
        switch route {
        case let .taskDetail(id), let .taskHistory(id):
            store.block(id: id).map { $0.isTask && $0.trashID == nil } == true ? nil : "task"
        case let .list(id):
            store.list(id: id) == nil ? "list" : nil
        default:
            nil
        }
    }

    // MARK: Scene phases

    /// The scene came to the front: reminders reconciled with the system's,
    /// widget taps made while suspended applied, and the snapshot refreshed.
    /// (The sync monitor checks the account and imports on its own.)
    func sceneBecameActive() {
        isActive = true
        if hasShownWindow { links.windowReady(true) }
        guard hasBootstrapped else { return }
        store.refreshAllReminders()
        NotificationService.shared.reminders.refresh()
        widgetCommands.drainQueue(now: clock.now)
        takeSharedCaptures()
        widgetPublisher.refreshNow(now: clock.now)
        liveActivity?.sync()
        notify(.becameActive)
    }

    /// What the Share sheet's Add to Openlist left while the app was away,
    /// filed as typed capture files it: into the Inbox, or the list an `@`
    /// in the words names, with its day, labels and the rest, and the link
    /// as the note. One tray, with Undo, says it. A share that couldn't be
    /// saved waits for the next time.
    func takeSharedCaptures(container: URL? = AppGroup.containerURL) {
        let shared = SharedCaptures.takeAll(container: container)
        guard !shared.isEmpty else { return }
        let lists = store.allLists().filter { !$0.isEffectivelyArchived }.map { ($0.id, $0.displayTitle) }
        var saved: [Block] = [], unsaved: [SharedCapture] = []
        for capture in shared {
            // A link alone goes by its address.
            let words = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let parse = CaptureParse(words.isEmpty ? capture.note : words, parsesDates: settings.parsesNaturalLanguageDates,
                                     reference: clock.now, lists: lists)
            var snapshot = parse.snapshot()
            if !words.isEmpty { snapshot.note = capture.note }
            guard !snapshot.title.isEmpty else { continue }
            do {
                saved.append(try store.saveCapture(snapshot, destinationID: parse.listID ?? store.inboxList()?.id))
            } catch {
                unsaved.append(capture)
            }
        }
        if !unsaved.isEmpty { try? SharedCaptures.append(unsaved, container: container) }
        actions.reportCapture(saved)
    }

    /// The scene is leaving the front. iOS may suspend or end the app without
    /// asking, so whatever shows as done or edited is saved now: drafts are
    /// committed, dwelling completions written and the store saved, with
    /// background time to finish reminders. Going to the background also
    /// writes the widget snapshot at once.
    func sceneWillResignActive(toBackground: Bool) {
        isActive = false
        notify(.willResignActive)
        commitDrafts()
        actions.settleAll()
        guard hasBootstrapped else { return }
        if toBackground {
            backgroundSaveCount += 1
            saveWithBackgroundTime()
            widgetPublisher.refreshNow(now: clock.now)
        } else if store.context.hasChanges {
            // Only on the way to the background is an empty save worth its
            // reminder and widget refresh.
            store.save()
        }
    }

    private func commitDrafts() {
        NotificationCenter.default.post(name: .commitPendingEditorDrafts, object: nil)
    }

    private func saveWithBackgroundTime() {
        let end = platform.beginBackgroundTask("Openlist save") { [weak self] in self?.pendingSave?.cancel() }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            defer { end() }
            guard let self else { return }
            do {
                try await TerminationDrain.run(
                    commitDrafts: { self.commitDrafts() },
                    persist: { try self.store.persistChanges() },
                    wait: { await NotificationService.shared.reminders.drainForTermination() },
                    hasPendingWork: { NotificationService.shared.reminders.isRefreshing },
                    finish: {})
            } catch {
                store.persistenceError = "Your latest changes could not be saved. \(error.localizedDescription)"
            }
        }
    }

    // MARK: Restoring

    /// The window is on screen: the place its scene saved is put back, unless
    /// something (a launch route) already moved the phone, then links that
    /// came meanwhile open on top of it. Review sessions start where their
    /// launch variables say, unless `OpenlistRestoresPlace=1` asks to check
    /// restoring.
    func windowAppeared(restoring saved: Data?) {
        if !hasShownWindow, let saved, restoresPlaces, navigator.isAtLaunch,
           let place = try? JSONDecoder().decode(PhoneNavigator.Place.self, from: saved) {
            bootstrap()
            navigator.restore(place, today: settings.calendar.startOfDay(for: now),
                              hasWork: PhoneWork(env: self, now: now).task != nil)
            navigator.repair(list: { [store] in store.list(id: $0)?.id },
                             taskExists: { [store] in store.block(id: $0).map { $0.isTask && $0.trashID == nil } ?? false })
        }
        hasShownWindow = true
        links.windowReady(true)
    }

    private var restoresPlaces: Bool {
        guard ReviewSession.identifier != nil else { return true }
        #if DEBUG
        return ProcessInfo.processInfo.environment["OpenlistRestoresPlace"] == "1"
        #else
        return false
        #endif
    }

    /// A screen's name, as its back link and VoiceOver say it.
    func title(of route: PhoneRoute) -> String {
        switch route {
        case .today, .timeline: "Today"
        case .work: "Work"
        case .activity: "Activity"
        case let .taskDetail(id): store.block(id: id)?.displayTitle ?? "Task"
        case .taskHistory: "History"
        case .inbox: "Inbox"
        case .triage: "Triage"
        case .lists: "Lists"
        case let .list(id): store.list(id: id)?.displayTitle ?? "List"
        case .find: "Find"
        case .settings: "Settings"
        case .trash: "Trash"
        case .planHours: "Plan hours"
        case .working: "Working"
        case .capture: "New task"
        }
    }

    /// What `route`'s back link says: the screen under it.
    func backTitle(for route: PhoneRoute) -> String { title(of: navigator.screen(below: route)) }

    // MARK: Links

    /// Opens an openlist:// URL, and returns whether it was one.
    @discardableResult
    func openLink(_ url: URL) -> Bool { links.receive(url) }
}

/// The work-presence answer the calendar asks at bootstrap, which the
/// environment can change after the coordinator is made.
@MainActor
private final class WorkPresenceHook {
    var adopts: (WorkSession) -> Bool = { _ in false }
}
