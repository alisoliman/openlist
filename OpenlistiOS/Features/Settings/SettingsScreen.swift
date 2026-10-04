//
//  SettingsScreen.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI
import UIKit

/// Settings (mockup 15), a full page over everything, with its own stack: the task, motion and
/// calendar settings this device keeps, Activity and Trash, and how iCloud
/// sync stands. The rest of the options live on the Mac.
struct SettingsScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @Query(filter: #Predicate<Block> { $0.trashID != nil }) private var trashedBlocks: [Block]
    @Query(filter: #Predicate<TaskList> { $0.trashID != nil }) private var trashedLists: [TaskList]
    @State private var editsHours = false
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
                    .accessibilityIdentifier("settings.done")
            }
        } content: {
            OLHeader("Settings")
            OLGroup("Tasks") {
                VStack(spacing: 0) {
                    OLSettingsRow("Show done in lists", tile: .accent("checkmark")) {
                        Toggle("Show done in lists", isOn: $settings.showsCompletedTasks).labelsHidden().olToggle()
                            .accessibilityIdentifier("settings.showDone")
                    }
                    Menu {
                        Picker("Week starts on", selection: $settings.firstWeekday) {
                            ForEach([0, 2, 1, 7], id: \.self) { Text(weekdayTitle($0)).tag($0) }
                        }
                    } label: {
                        OLSettingsRow("Week starts on", tile: .today(icon: .calendar), separator: .settings) {
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
                        OLSettingsRow("Undo window", tile: .accent("arrow.uturn.backward"), separator: .settings) {
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
                        OLSettingsRow("After voice capture", tile: .accent("mic"), separator: .settings) {
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
            OLGroup("Motion") {
                VStack(spacing: 0) {
                    OLSettingsRow("Reduce motion", tile: .teal(icon: .wave)) {
                        Toggle("Reduce motion", isOn: $settings.reducesMotion).labelsHidden().olToggle()
                            .accessibilityIdentifier("settings.reduceMotion")
                    }
                    OLSettingsRow("Haptics", tile: .teal("iphone.radiowaves.left.and.right"), separator: .settings) {
                        Toggle("Haptics", isOn: $settings.playsHaptics).labelsHidden().olToggle()
                            .accessibilityIdentifier("settings.haptics")
                    }
                }
                .olCard()
            }
            OLGroup("Calendar") {
                VStack(spacing: 0) {
                    Button(action: connectCalendar) {
                        OLSettingsRow("Calendar access", tile: .info(icon: .calendar)) {
                            OLRowValue(calendarAccess ? "On" : "Off", color: calendarAccess ? OL.successText : OL.muted,
                                       showsChevron: !calendarAccess)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    .accessibilityIdentifier("settings.calendarAccess")
                    Button { editsHours = true } label: {
                        OLSettingsRow("Plan hours", tile: .info(icon: .stopwatch), separator: .settings) {
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
                        OLSettingsRow("Activity", tile: .accent("waveform.path.ecg")) { OLRowValue(nil) }
                            .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    Button { navigator.open(.trash) } label: {
                        OLSettingsRow("Trash", tile: .danger("trash"), separator: .settings) {
                            OLRowValue(trashCount == 0 ? nil : "\(trashCount)")
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    .accessibilityLabel("Trash")
                    .accessibilityValue(trashCount == 0 ? "Empty" : "\(trashCount) \(trashCount == 1 ? "item" : "items")")
                    Button { syncDetail = true } label: {
                        OLSettingsRow("iCloud sync", tile: .info("icloud"), separator: .settings) {
                            let sync = syncStatus
                            OLRowValue(sync.text, color: sync.color, showsChevron: false)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(OLRowPressStyle())
                    .accessibilityIdentifier("settings.sync")
                    #if DEBUG
                    Button { navigator.showComponentGallery() } label: {
                        OLSettingsRow("Component gallery", tile: .accent("square.grid.3x3"), separator: .settings) {
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
        .sheet(isPresented: $editsHours) { PlanHoursSheet() }
        .alert(env.sync.state.title, isPresented: $syncDetail) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(env.sync.state.isEnabled ? env.sync.state.detail
                 : env.sync.state.unavailableReason ?? "iCloud sync is off on this iPhone.")
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
        let source = env.calendar.externalCalendars
        Task {
            await source.requestAccess()
            if source.isAuthorized {
                env.calendar.refreshCalendars(now: env.now)
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
        }
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
/// plans. Saved per device, as the Mac keeps its own. It edits each profile's
/// usual hours, the ones most of its days have; days with hours of their own,
/// and breaks, stay as they are, and a time left alone is saved as it was.
struct PlanHoursSheet: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var work = PlanHoursDraft()
    @State private var personal = PlanHoursDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OLSheetHeader(confirmTitle: "Save", cancel: { dismiss() }, confirm: save)
            Text("Plan hours").font(OLFont.linkStrong).padding(.top, 10)
            Text("Planning puts work tasks in work hours on weekdays, and personal ones in personal hours.")
                .font(OLFont.meta)
                .foregroundStyle(OL.muted)
                .padding(.top, 4)
            section("Work", hours: $work)
            section("Personal", hours: $personal)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OLMetrics.gutter)
        .padding(.top, 8)
        .presentationDetents([.medium])
        .olSheet()
        .onAppear {
            let preferences = env.calendar.preferences
            work = PlanHoursDraft(preferences.work, default: AvailabilityWindow(startMinute: 9 * 60, endMinute: 17 * 60))
            personal = PlanHoursDraft(preferences.personal, default: AvailabilityWindow(startMinute: 18 * 60, endMinute: 21 * 60))
        }
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
        var preferences = env.calendar.preferences
        preferences.work = work.applied(to: preferences.work, days: Array(2...6))
        preferences.personal = personal.applied(to: preferences.personal, days: Array(1...7))
        if preferences != env.calendar.preferences {
            env.calendar.updatePreferences(preferences, now: env.now)
            env.tray.show("Plan hours saved", icon: "timer", tone: .accent, seconds: 3)
        }
        dismiss()
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
