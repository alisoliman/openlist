//
//  NextSettingsScreen.swift
//  openlist
//
//  In-window preferences. The Settings window keeps the full set.
//

import SwiftUI

struct NextSettingsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var settings = env.settings
        NXPage {
            NXScreenHeader(tile: .icon("gearshape"), color: NX.grey, title: "Settings", subtitle: "Preferences for this Mac")
            VStack(alignment: .leading, spacing: 18) {
                NXSettingsGroup(title: "Tasks") {
                    NXSettingToggle(label: "Show completed tasks", hint: "Lists and Today expand their Completed section by default",
                                    isOn: $settings.showsCompletedTasks)
                    NXSettingMenu(label: "Week starts on", hint: "Used by Calendar and Activity", value: weekStartTitle) {
                        Picker("Week starts on", selection: $settings.firstWeekday) {
                            Text("System default").tag(0)
                            Text("Sunday").tag(1)
                            Text("Monday").tag(2)
                            Text("Saturday").tag(7)
                        }
                        .pickerStyle(.inline)
                    }
                    NXSettingToggle(label: "Quick Add from anywhere", hint: "⇧⌥Space opens capture over any app",
                                    isOn: $settings.quickCaptureHotKeyEnabled)
                        .onChange(of: settings.quickCaptureHotKeyEnabled) { _, enabled in
                            if enabled {
                                QuickCaptureHotKey.shared.register()
                            } else {
                                QuickCaptureHotKey.shared.unregister()
                            }
                        }
                }
                NXSettingsGroup(title: "Motion & feedback") {
                    NXSettingToggle(label: "Reduce motion", hint: "Keeps state changes, drops the bounce, ring and slides",
                                    isOn: $settings.reducesMotion)
                    NXSettingMenu(label: "Undo window", hint: "How long a finished task stays in place",
                                  value: "\(settings.undoDwellSeconds) s") {
                        Picker("Undo window", selection: $settings.undoDwellSeconds) {
                            ForEach([2, 3, 5, 8], id: \.self) { Text("\($0) seconds").tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                    NXSettingMenu(label: "Motion", hint: "How lively completions, triage and transitions feel",
                                  value: settings.motion.title) {
                        Picker("Motion", selection: $settings.motion) {
                            ForEach(NextMotion.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                }
                NXSettingsGroup(title: "Appearance") {
                    NXSettingMenu(label: "Appearance", hint: "Light, dark or follow the system", value: settings.appearance.title) {
                        Picker("Appearance", selection: $settings.appearance) {
                            ForEach(AppSettings.Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                    NXSettingMenu(label: "Accent", hint: "Selection, focus and today’s highlights", value: settings.accent.title,
                                  swatch: settings.accent.color) {
                        Picker("Accent", selection: $settings.accent) {
                            ForEach(NextAccent.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                    NXSettingMenu(label: "Density", hint: "Row spacing in lists", value: settings.density.title) {
                        Picker("Density", selection: $settings.density) {
                            ForEach(NextDensity.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                    NXSettingToggle(label: "Serif titles", hint: "Screen titles in Instrument Serif", isOn: $settings.serifTitles)
                    NXSettingMenu(label: "Tasks filter", hint: "Type a query, or build a sentence from pills",
                                  value: settings.tasksFilterStyle.title) {
                        Picker("Tasks filter", selection: $settings.tasksFilterStyle) {
                            ForEach(TasksFilterStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                    }
                }
                NXSettingsGroup(title: "Calendar") {
                    let preferences = env.calendar.preferences
                    NXSettingValue(label: "Work hours", hint: "Planning uses these for Work lists",
                                   value: NXHours.summary(preferences.work, calendar: settings.calendar)) { openSettings() }
                    NXSettingValue(label: "Personal hours", hint: "Planning uses these for Personal lists",
                                   value: NXHours.summary(preferences.personal, calendar: settings.calendar)) { openSettings() }
                    NXSettingMenu(label: "Default estimate", hint: "For tasks without their own",
                                  value: NXFormat.minutes(env.workbench.defaultEstimate)) {
                        ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                            Button {
                                var updated = env.calendar.preferences
                                updated.defaultEstimateMinutes = Double(minutes)
                                env.calendar.updatePreferences(updated)
                            } label: {
                                if minutes == env.workbench.defaultEstimate {
                                    Label(NXFormat.minutes(minutes), systemImage: "checkmark")
                                } else {
                                    Text(NXFormat.minutes(minutes))
                                }
                            }
                        }
                    }
                }
                NXSettingsGroup(title: "Library") {
                    let sync = env.sync.state
                    NXSettingValue(label: "iCloud sync", hint: syncHint(sync), value: syncValue(sync)) { openSettings() }
                    if let maintenance = env.libraryMaintenance {
                        let failure = maintenance.error ?? maintenance.pendingQuitError
                        NXSettingValue(label: "Back up library",
                                       hint: failure ?? maintenance.status ?? "A complete package of your library, history and files",
                                       isError: failure != nil,
                                       value: maintenance.isBusy ? "Working…" : "Back up now…",
                                       isEnabled: !maintenance.isBusy && !maintenance.hasPendingRestore) {
                            Task { await maintenance.exportBackup() }
                        }
                    }
                    NXSettingValue(label: "All settings", hint: "Menu bar, notifications, integrations and more", value: "Open…") {
                        openSettings()
                    }
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.top, 20)
        }
    }

    private var weekStartTitle: String {
        switch env.settings.firstWeekday {
        case 1: "Sunday"
        case 2: "Monday"
        case 7: "Saturday"
        default: "System (\(Calendar.current.weekdaySymbols[Calendar.current.firstWeekday - 1]))"
        }
    }

    private func syncValue(_ state: ICloudSyncState) -> String {
        guard state.isEnabled else { return "Off" }
        if state.hasProblem { return "Needs attention" }
        if case .available = state.account {
            return state.title == "Syncing with iCloud" ? "Syncing…" : "Up to date"
        }
        return state.title
    }

    private func syncHint(_ state: ICloudSyncState) -> String {
        guard state.isEnabled, case .available = state.account, !state.hasProblem else { return state.title }
        let last = [state.lastUpload, state.lastDownload].compactMap { $0 }.max()
        return last.map { "Last synced \(NXFormat.relative($0))" } ?? "Syncs privately through your Apple Account"
    }
}

/// "Mon–Fri 09:00–17:00" for a weekly availability profile.
enum NXHours {
    static func summary(_ profile: AvailabilityProfile, calendar: Calendar) -> String {
        let days = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        let active = days.filter { !(profile.weekly[$0] ?? []).isEmpty }
        guard let first = active.first, let windows = profile.weekly[first] else { return "Off" }
        let times = windows.map { "\(clock($0.startMinute))–\(clock($0.endMinute))" }.joined(separator: ", ")
        guard active.allSatisfy({ profile.weekly[$0] == windows }) else { return "Varies by day" }
        let symbols = calendar.shortWeekdaySymbols
        let positions = active.compactMap { days.firstIndex(of: $0) }
        let span: String
        if active.count == 7 {
            span = "Every day"
        } else if let low = positions.first, let high = positions.last, high - low + 1 == positions.count, positions.count > 2 {
            span = "\(symbols[days[low] - 1])–\(symbols[days[high] - 1])"
        } else {
            span = active.map { symbols[$0 - 1] }.joined(separator: ", ")
        }
        return "\(span) \(times)"
    }

    private static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60 % 24 + (minute == 1440 ? 24 : 0), minute % 60)
    }
}

// MARK: Rows

private struct NXSettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NXCapsTitle(text: title).padding(.horizontal, 4).padding(.bottom, 8)
            VStack(spacing: 0) { content }
                .background(NX.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NX.ink(0.12), lineWidth: 0.5))
        }
    }
}

private struct NXSettingRow<Accessory: View>: View {
    let label: String
    let hint: String
    var hintColor = NX.ink(0.48)
    @ViewBuilder var accessory: Accessory
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(NX.ink)
                Text(hint).font(.system(size: 11.5)).foregroundStyle(hintColor).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(hovering ? NX.ink(0.02) : .clear)
        .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.06)).frame(height: 0.5) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct NXSettingToggle: View {
    @Environment(\.nextStyle) private var style
    let label: String
    let hint: String
    @Binding var isOn: Bool

    var body: some View {
        NXSettingRow(label: label, hint: hint) {
            Capsule()
                .fill(isOn ? style.accent : NX.ink(0.16))
                .frame(width: 34, height: 20)
                .overlay(alignment: .leading) {
                    Circle().fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                        .offset(x: isOn ? 16 : 2)
                        .animation(style.spring(200), value: isOn)
                }
                .animation(.easeOut(duration: 0.18), value: isOn)
        }
        .onTapGesture { isOn.toggle() }
        .accessibilityRepresentation { Toggle(label, isOn: $isOn) }
    }
}

private struct NXValuePill: View {
    let text: String
    var swatch: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let swatch { Circle().fill(swatch).frame(width: 9, height: 9) }
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(NX.ink(0.55))
        .lineLimit(1)
        .padding(.vertical, 6)
        .padding(.horizontal, 9)
        .background(NX.ink(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct NXSettingValue: View {
    let label: String
    let hint: String
    /// Shows the hint as a failure, like a backup that could not be written.
    var isError = false
    let value: String
    /// Off while the action cannot run; the row stays visible and dimmed.
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        NXSettingRow(label: label, hint: hint, hintColor: isError ? NX.redText : NX.ink(0.48)) {
            NXValuePill(text: value).opacity(isEnabled ? 1 : 0.5)
        }
        .onTapGesture { if isEnabled { action() } }
        .disabled(!isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if isEnabled { action() } }
    }
}

private struct NXSettingMenu<Options: View>: View {
    let label: String
    let hint: String
    let value: String
    var swatch: Color?
    @ViewBuilder var options: Options

    var body: some View {
        Menu {
            options
        } label: {
            NXSettingRow(label: label, hint: hint) { NXValuePill(text: value, swatch: swatch) }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("\(label): \(value)")
    }
}
