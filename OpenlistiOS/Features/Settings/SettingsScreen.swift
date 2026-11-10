//
//  SettingsScreen.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI
import UIKit

/// Settings (mockup 15), a sheet over everything, with its own stack: the
/// task, motion and calendar settings this device keeps (each kept as it's
/// changed), Plan hours, Activity and Trash, and how iCloud sync stands. The
/// rest of the options live on the Mac.
struct SettingsScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @Query(filter: #Predicate<Block> { $0.trashID != nil }) private var trashedBlocks: [Block]
    @Query(filter: #Predicate<TaskList> { $0.trashID != nil }) private var trashedLists: [TaskList]
    @State private var syncDetail = false

    var body: some View {
        @Bindable var settings = env.settings
        let navigator = env.navigator
        OLScreen(identifier: PhoneRoute.settings.screenIdentifier) {
            OLTopBar {
                EmptyView()
            } trailing: {
                Button("Done") { navigator.dismissSheet() }
                    .buttonStyle(.olLink(strong: true))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("settings.done")
            }
        } content: {
            OLHeader("Settings")
            OLGroup("Tasks") {
                VStack(spacing: 0) {
                    OLSettingsRow("Show done in lists", tile: .symbol("checkmark")) {
                        Toggle("Show done in lists", isOn: $settings.showsCompletedTasks).labelsHidden().olToggle()
                            .accessibilityIdentifier("settings.showDone")
                    }
                    Menu {
                        Picker("Week starts on", selection: $settings.firstWeekday) {
                            ForEach([0, 2, 1, 7], id: \.self) { Text(weekdayTitle($0)).tag($0) }
                        }
                    } label: {
                        OLSettingsRow("Week starts on", tile: .icon(.calendar), separator: .settings) {
                            OLRowValue(weekdayTitle(settings.firstWeekday))
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    .accessibilityIdentifier("settings.weekStart")
                    Menu {
                        Picker("Undo window", selection: $settings.undoDwellSeconds) {
                            ForEach([2, 3, 5, 8], id: \.self) { Text("\($0) seconds").tag($0) }
                        }
                    } label: {
                        OLSettingsRow("Undo window", tile: .symbol("arrow.uturn.backward"), separator: .settings) {
                            OLRowValue("\(settings.undoDwellSeconds) s")
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    .accessibilityIdentifier("settings.undoWindow")
                    Menu {
                        Picker("After voice capture", selection: $settings.afterVoiceCapture) {
                            ForEach(AppSettings.AfterVoiceCapture.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        OLSettingsRow("After voice capture", tile: .symbol("mic"), separator: .settings) {
                            OLRowValue(settings.afterVoiceCapture.title)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    .accessibilityHint("On this iPhone only. Existing drafts always stay for review.")
                    .accessibilityIdentifier("settings.afterVoiceCapture")
                }
                .olCard()
            }
            TaskSwipeSettingsSection()
            notificationSettings
            OLGroup("Motion") {
                VStack(spacing: 0) {
                    OLSettingsRow("Reduce motion", tile: .icon(.wave)) {
                        Toggle("Reduce motion", isOn: $settings.reducesMotion).labelsHidden().olToggle()
                            .accessibilityIdentifier("settings.reduceMotion")
                    }
                    OLSettingsRow("Haptics", tile: .symbol("iphone.radiowaves.left.and.right"), separator: .settings) {
                        Toggle("Haptics", isOn: $settings.playsHaptics).labelsHidden().olToggle()
                            .accessibilityIdentifier("settings.haptics")
                    }
                }
                .olCard()
            }
            OLGroup("Calendar") {
                VStack(spacing: 0) {
                    Button(action: connectCalendar) {
                        OLSettingsRow("Calendar access", tile: .icon(.calendar)) {
                            OLRowValue(calendarAccess ? "On" : "Off", color: calendarAccess ? OL.successText : OL.muted,
                                       showsChevron: !calendarAccess)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    .accessibilityIdentifier("settings.calendarAccess")
                    Button { navigator.open(.planHours) } label: {
                        OLSettingsRow("Plan hours", tile: .icon(.stopwatch), separator: .settings) {
                            OLRowValue(PlanHours.summary(env.calendar.preferences))
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    .accessibilityIdentifier("settings.planHours")
                }
                .olCard()
            }
            OLGroup("Library") {
                VStack(spacing: 0) {
                    Button { navigator.open(.activity) } label: {
                        OLSettingsRow("Activity", tile: .symbol("waveform.path.ecg")) { OLRowValue(nil) }
                            .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    Button { navigator.open(.trash) } label: {
                        OLSettingsRow("Trash", tile: .symbol("trash"), separator: .settings) {
                            OLRowValue(trashCount == 0 ? nil : "\(trashCount)")
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    .accessibilityLabel("Trash")
                    .accessibilityValue(trashCount == 0 ? "Empty" : "\(trashCount) \(trashCount == 1 ? "item" : "items")")
                    Button { syncDetail = true } label: {
                        OLSettingsRow("iCloud sync", tile: .symbol("icloud"), separator: .settings) {
                            let sync = syncStatus
                            OLRowValue(sync.text, color: sync.color, showsChevron: false)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    .accessibilityIdentifier("settings.sync")
                    #if DEBUG
                    Button { navigator.showComponentGallery() } label: {
                        OLSettingsRow("Component gallery", tile: .symbol("square.grid.3x3"), separator: .settings) {
                            OLRowValue(nil)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    #endif
                }
                .olCard()
            }
            AppInformationSection()
            Text("More on your Mac: MCP, Calendar and advanced options.\n\(Self.version)")
                .font(OLFont.meta)
                .foregroundStyle(OL.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, OLMetrics.groupGap)
        }
        .alert(env.sync.state.title, isPresented: $syncDetail) {
            // A check that failed, or iCloud away for now, can be tried again.
            switch env.sync.state.account {
            case .failed, .temporarilyUnavailable:
                Button("Check Again") { env.sync.checkAccount() }
            default:
                EmptyView()
            }
            Button("Done", role: .cancel) {}
        } message: {
            Text(env.sync.state.isEnabled ? env.sync.state.detail
                 : env.sync.state.unavailableReason ?? "iCloud sync is off on this iPhone.")
        }
        .task {
            env.store.refreshAllReminders()
            NotificationService.shared.reminders.refresh()
        }
    }

    private var notificationSettings: some View {
        let recovery = NotificationService.shared.reminders
        let pending = recovery.statuses.values.filter { $0 == .accepted }.count
        let queued = recovery.statuses.values.filter { $0 == .queued }.count
        let failed = recovery.statuses.values.filter {
            if case .failed = $0 { return true }
            return false
        }.count
        return OLGroup("Notifications") {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    switch recovery.authorization {
                    case .notDetermined:
                        Task { _ = await NotificationService.shared.requestAuthorization() }
                    case .denied, .authorized:
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    case .unknown, .unavailable: break
                    }
                } label: {
                    OLSettingsRow("Notifications", tile: .symbol("bell")) {
                        OLRowValue(notificationPermissionTitle, showsChevron: recovery.authorization != .unknown && recovery.authorization != .unavailable)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(OLRowPressStyle())
                .disabled(recovery.isSimulated || recovery.isRequestingAuthorization || recovery.authorization == .unknown || recovery.authorization == .unavailable)
                .accessibilityIdentifier("settings.notifications")
                Button {
                    env.store.refreshAllReminders()
                    recovery.refresh(retryFailures: true)
                } label: {
                    OLSettingsRow("Reminders", tile: .symbol("clock"), separator: .settings) {
                        OLRowValue(recovery.isRefreshing ? "Checking…" : "\(pending) pending", showsChevron: false)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(OLRowPressStyle())
                .disabled(recovery.isRefreshing)
                .accessibilityHint("Checks and retries future reminders")
                .accessibilityIdentifier("settings.retryReminders")
            }
            .olCard()
            if recovery.isSimulated || queued > 0 || failed > 0 || recovery.recoveryError != nil || recovery.libraryReadError != nil || recovery.authorizationError != nil {
                Text(recovery.authorizationError ?? recovery.libraryReadError ?? recovery.recoveryError
                     ?? (recovery.isSimulated ? "Review simulation only. No notifications are scheduled."
                         : [failed > 0 ? "\(failed) couldn’t be scheduled." : nil,
                            queued > 0 ? "\(queued) waiting for earlier reminders." : nil].compactMap { $0 }.joined(separator: " ")))
                    .font(OLFont.meta)
                    .foregroundStyle(OL.muted)
                    .padding(.top, 8)
            }
        }
    }

    private var notificationPermissionTitle: String {
        let recovery = NotificationService.shared.reminders
        if recovery.isSimulated { return "Simulated" }
        return switch recovery.authorization {
        case .unknown: "Checking…"
        case .notDetermined: "Allow"
        case .denied: "Off"
        case .authorized: "On"
        case .unavailable: "Unavailable"
        }
    }

    private var trashCount: Int {
        trashedBlocks.count { $0.trashID == $0.id } + trashedLists.count { $0.trashID == $0.id }
    }

    private func weekdayTitle(_ weekday: Int) -> String {
        switch weekday {
        case 1: "Sunday"
        case 2: "Monday"
        case 7: "Saturday"
        default:
            "System (\(Calendar.current.weekdaySymbols[Calendar.current.firstWeekday - 1]))"
        }
    }

    // MARK: Calendar

    /// On once calendars are connected and allowed, or a review session's
    /// fixture stands in for them.
    private var calendarAccess: Bool {
        let source = env.calendar.externalCalendars
        return source.isAuthorized || !source.busyTimes.isEmpty
    }

    private func connectCalendar() {
        guard !calendarAccess else { return }
        PhoneSchedule.connect(env)
    }

    // MARK: Sync

    private var syncStatus: (text: String, color: Color) {
        let state = env.sync.state
        guard state.isEnabled else { return ("Off", OL.muted) }
        if state.hasProblem { return ("Needs attention", OL.danger) }
        if !state.activeOperations.isEmpty { return ("Syncing…", OL.muted) }
        let last = [state.lastUpload, state.lastDownload].compactMap(\.self).max()
        if let last { return ("Synced \(CompactText.ago(last, now: env.now))", OL.successText) }
        return (state.account == .available ? "On" : state.title, state.account == .available ? OL.successText : OL.muted)
    }

    /// "Openlist 2.0 (214)".
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "–"
        let build = info["CFBundleVersion"] as? String ?? "–"
        return "Openlist \(version) (\(build))"
    }
}

/// The hours the calendar plans work and personal tasks into.
enum PlanHours {
    /// "09–17 · 18–21": each profile's hours when every day it plans shares
    /// them, "varies" when they don't.
    static func summary(_ preferences: CalendarPreferences) -> String {
        [preferences.work, preferences.personal].map(summary).joined(separator: " · ")
    }

    static func summary(_ profile: AvailabilityProfile) -> String {
        let windows = Set(profile.weekly.values.flatMap(\.self))
        guard let window = windows.first else { return "Off" }
        guard windows.count == 1 else { return "Varies" }
        return "\(clock(window.startMinute))–\(clock(window.endMinute))"
    }

    /// "09", or "09:30" off the hour.
    static func clock(_ minute: Int) -> String {
        minute % 60 == 0 ? String(format: "%02d", minute / 60) : String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

/// Plan hours: when work and personal tasks may be planned, on the days each
/// plans, pushed inside Settings and kept as it's changed, as Settings' other
/// options are. Saved per device, as the Mac keeps its own. It edits each
/// profile's usual hours, the ones most of its days have; days with hours of
/// their own, and breaks, stay as they are, and a time left alone is saved as
/// it was.
struct PlanHoursScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @State private var work = PlanHoursDraft()
    @State private var personal = PlanHoursDraft()
    /// The hours as the page found them, which every change is made from.
    @State private var original: CalendarPreferences?

    var body: some View {
        OLScreen(identifier: PhoneRoute.planHours.screenIdentifier) {
            OLTopBar { OLBackButton(env.backTitle(for: .planHours)) { env.navigator.pop() } }
        } content: {
            OLHeader("Plan hours",
                     sub: "Planning puts work tasks in work hours on weekdays, and personal ones in personal hours.")
            section("Work", hours: $work)
            section("Personal", hours: $personal)
        }
        .onAppear {
            guard original == nil else { return }
            let preferences = env.calendar.preferences
            original = preferences
            work = PlanHoursDraft(preferences.work, default: AvailabilityWindow(startMinute: 9 * 60, endMinute: 17 * 60))
            personal = PlanHoursDraft(preferences.personal, default: AvailabilityWindow(startMinute: 18 * 60, endMinute: 21 * 60))
        }
        .onChange(of: [work.start, work.end, personal.start, personal.end]) { save() }
    }

    private func section(_ title: String, hours: Binding<PlanHoursDraft>) -> some View {
        OLGroup(title, topSpacing: 20) {
            VStack(spacing: 0) {
                OLSettingsRow("From") {
                    DatePicker("From", selection: hours.start, displayedComponents: .hourAndMinute).labelsHidden()
                }
                OLSettingsRow("To", separator: .inset(16)) {
                    DatePicker("To", selection: hours.end, displayedComponents: .hourAndMinute).labelsHidden()
                }
            }
            .olCard()
        }
    }

    private func save() {
        guard let original else { return }
        var preferences = env.calendar.preferences
        preferences.work = work.applied(to: original.work, days: Array(2...6))
        preferences.personal = personal.applied(to: original.personal, days: Array(1...7))
        if preferences != env.calendar.preferences {
            env.calendar.updatePreferences(preferences, now: env.now)
        }
    }
}

/// One profile's usual hours as the sheet edits them.
struct PlanHoursDraft {
    /// The hours most of the profile's days have, or the default when none do.
    private(set) var usual = AvailabilityWindow(startMinute: 9 * 60, endMinute: 17 * 60)
    /// Whether any day plans at all.
    private(set) var plans = false
    var start = Date.now
    var end = Date.now

    init() {}

    init(_ profile: AvailabilityProfile, default fallback: AvailabilityWindow) {
        let windows = profile.weekly.keys.sorted().flatMap { profile.weekly[$0] ?? [] }
        let counts = Dictionary(windows.map { ($0, 1) }, uniquingKeysWith: +)
        // The most common, the earliest in the week on a tie.
        usual = windows.max { counts[$0]! < counts[$1]! || counts[$0]! == counts[$1]! && windows.firstIndex(of: $0)! > windows.firstIndex(of: $1)! }
            ?? fallback
        plans = !windows.isEmpty
        start = Self.date(usual.startMinute)
        // 24:00 shows as the last minute of the day.
        end = Self.date(min(usual.endMinute, 24 * 60 - 1))
    }

    /// The profile with the usual hours changed where it had them, or on
    /// `days` if it planned none. A time left alone keeps its minute, 24:00
    /// included.
    func applied(to profile: AvailabilityProfile, days: [Int]) -> AvailabilityProfile {
        let startChanged = Self.minute(start) != usual.startMinute
        let endChanged = Self.minute(end) != min(usual.endMinute, 24 * 60 - 1)
        guard startChanged || endChanged || !plans else { return profile }
        let startMinute = startChanged ? Self.minute(start) : usual.startMinute
        var endMinute = endChanged ? Self.minute(end) : usual.endMinute
        if endMinute <= startMinute { endMinute = min(24 * 60, startMinute + 15) }
        let window = AvailabilityWindow(startMinute: startMinute, endMinute: endMinute)
        var profile = profile
        if plans {
            for (day, windows) in profile.weekly {
                profile.weekly[day] = windows.map { $0 == usual ? window : $0 }
            }
        } else {
            for day in days { profile.weekly[day] = [window] }
        }
        return profile
    }

    private static func date(_ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0,
                              of: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    private static func minute(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
