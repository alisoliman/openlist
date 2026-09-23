//
//  NextSettingsScreen.swift
//  openlist
//
//  In-window preferences. The Settings window keeps the full set.
//

import AppKit
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
                    NXSettingMenu(label: "Week starts on", hint: "Used by Calendar and Activity", value: weekStartTitle,
                                  entries: choices([0, 1, 2, 7], selection: $settings.firstWeekday) { weekday in
                                      switch weekday {
                                      case 1: "Sunday"
                                      case 2: "Monday"
                                      case 7: "Saturday"
                                      default: "System default"
                                      }
                                  })
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
                                  value: "\(settings.undoDwellSeconds) s",
                                  entries: choices([2, 3, 5, 8], selection: $settings.undoDwellSeconds) { "\($0) seconds" })
                    NXSettingMenu(label: "Motion", hint: "How lively completions, triage and transitions feel",
                                  value: settings.motion.title,
                                  entries: choices(NextMotion.allCases, selection: $settings.motion, title: \.title))
                }
                NXSettingsGroup(title: "Appearance") {
                    NXSettingMenu(label: "Appearance", hint: "Light, dark or follow the system", value: settings.appearance.title,
                                  entries: choices(AppSettings.Appearance.allCases, selection: $settings.appearance, title: \.title))
                    NXSettingMenu(label: "Accent", hint: "Selection, focus and today’s highlights", value: settings.accent.title,
                                  swatch: settings.accent.color,
                                  entries: choices(NextAccent.allCases, selection: $settings.accent, title: \.title))
                    NXSettingMenu(label: "Density", hint: "Row spacing in lists", value: settings.density.title,
                                  entries: choices(NextDensity.allCases, selection: $settings.density, title: \.title))
                    NXSettingToggle(label: "Serif titles", hint: "Screen titles in Instrument Serif", isOn: $settings.serifTitles)
                    NXSettingMenu(label: "Tasks filter", hint: "Type a query, or build a sentence from pills",
                                  value: settings.tasksFilterStyle.title,
                                  entries: choices(TasksFilterStyle.allCases, selection: $settings.tasksFilterStyle, title: \.title))
                }
                NXSettingsGroup(title: "Calendar") {
                    let preferences = env.calendar.preferences
                    NXSettingValue(label: "Work hours", hint: "Planning uses these for Work lists",
                                   value: NXHours.summary(preferences.work, calendar: settings.calendar)) { openSettings() }
                    NXSettingValue(label: "Personal hours", hint: "Planning uses these for Personal lists",
                                   value: NXHours.summary(preferences.personal, calendar: settings.calendar)) { openSettings() }
                    NXSettingMenu(label: "Default estimate", hint: "For tasks without their own",
                                  value: Self.estimate(env.workbench.defaultEstimate),
                                  entries: choices([15, 30, 45, 60, 90], selection: defaultEstimate, title: Self.estimate))
                }
                NXSettingsGroup(title: "Library") {
                    let sync = env.sync.state
                    NXSettingValue(label: "iCloud sync", hint: syncHint(sync), value: syncValue(sync)) { openSettings() }
                    if let maintenance = env.libraryMaintenance {
                        let failure = maintenance.error ?? maintenance.pendingQuitError ?? maintenance.snapshotError
                        let daily = settings.takesDailySnapshots
                        NXSettingMenu(label: "Back up library",
                                      hint: failure ?? maintenance.status
                                          ?? (daily ? "Keeps \(LibrarySnapshots.retained) daily snapshots" : "Daily snapshots are off"),
                                      isError: failure != nil,
                                      value: maintenance.isBusy ? "Working…" : daily ? "Daily" : "Off",
                                      entries: choices([true, false], selection: $settings.takesDailySnapshots) { $0 ? "Daily" : "Off" } + [
                                          .divider,
                                          .command("Back up now…", isEnabled: !maintenance.isBusy && !maintenance.hasPendingRestore) {
                                              Task { await maintenance.exportBackup() }
                                          },
                                          .command("Show Snapshots in Finder") { maintenance.showSnapshots() },
                                      ])
                            .onChange(of: settings.takesDailySnapshots) { _, daily in
                                if daily { Task { await maintenance.snapshotIfDue() } }
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

    /// Planning's estimate for tasks without their own.
    private var defaultEstimate: Binding<Int> {
        Binding(get: { env.workbench.defaultEstimate }, set: { minutes in
            var updated = env.calendar.preferences
            updated.defaultEstimateMinutes = Double(minutes)
            env.calendar.updatePreferences(updated)
        })
    }

    /// "30 min", "1 h", "1 h 30 min": the design's roomy form for an estimate.
    private static func estimate(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        guard hours > 0 else { return "\(minutes) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
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
                // The design's `background 180ms ease` (CSS `ease`).
                .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: style.ms(180) / 1000), value: isOn)
        }
        .onTapGesture { isOn.toggle() }
        .accessibilityRepresentation { Toggle(label, isOn: $isOn) }
    }
}

private struct NXValuePill: View {
    let text: String
    var swatch: Color?

    /// Where the text starts, from the pill's leading edge: its padding, then
    /// the swatch and its gap.
    static func textInset(hasSwatch: Bool) -> CGFloat { hasSwatch ? 9 + 9 + 6 : 9 }

    var body: some View {
        HStack(spacing: 6) {
            if let swatch { Circle().fill(swatch).frame(width: 9, height: 9) }
            Text(text)
        }
        // The design's `12px/1` line box, so the pill is 24pt tall.
        .frame(height: 12)
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
    let value: String
    let action: () -> Void

    var body: some View {
        NXSettingRow(label: label, hint: hint) {
            NXValuePill(text: value)
        }
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

/// One line in a setting's pop-up menu.
private enum NXMenuEntry {
    /// A value to pick; the current one is checked and opens over the pill.
    case choice(String, isSelected: Bool, action: () -> Void)
    case command(String, isEnabled: Bool = true, action: () -> Void)
    case divider
}

/// A choice for each value, checked for the one `selection` holds.
private func choices<Value: Hashable>(_ values: [Value], selection: Binding<Value>,
                                      title: (Value) -> String) -> [NXMenuEntry] {
    values.map { value in
        .choice(title(value), isSelected: selection.wrappedValue == value) { selection.wrappedValue = value }
    }
}

/// A row whose value pill pops up a menu, the way a pop-up button does:
/// the current choice opens over the pill. Pressing anywhere on the row opens it.
private struct NXSettingMenu: View {
    let label: String
    let hint: String
    /// Shows the hint as a failure, like a backup that could not be written.
    var isError = false
    let value: String
    var swatch: Color?
    let entries: [NXMenuEntry]
    @State private var anchor = NXMenuAnchor()

    var body: some View {
        NXSettingRow(label: label, hint: hint, hintColor: isError ? NX.redText : NX.ink(0.48)) {
            NXValuePill(text: value, swatch: swatch)
                .background { NXMenuAnchorView(anchor: anchor) }
        }
        .overlay { NXMenuPress(action: popUp) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { popUp() }
    }

    private func popUp() {
        anchor.popUp(entries, titleInset: NXValuePill.textInset(hasSwatch: swatch != nil))
    }
}

/// Pops an AppKit menu from the pill it's attached to.
@MainActor
private final class NXMenuAnchor: NSObject {
    weak var view: NSView?
    /// The open menu's actions, by item tag.
    private var actions: [() -> Void] = []

    /// `titleInset` is where the pill's text starts, from its leading edge.
    func popUp(_ entries: [NXMenuEntry], titleInset: CGFloat) {
        guard let view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.appearance = view.effectiveAppearance
        actions = []
        var current: NSMenuItem?
        func add(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: #selector(run(_:)), keyEquivalent: "")
            item.target = self
            item.tag = actions.count
            actions.append(action)
            return item
        }
        for entry in entries {
            switch entry {
            case let .choice(title, isSelected, action):
                let item = add(title, action)
                item.state = isSelected ? .on : .off
                if isSelected { current = item }
            case let .command(title, isEnabled, action):
                add(title, action).isEnabled = isEnabled
            case .divider:
                menu.addItem(.separator())
            }
        }
        guard let current else {
            // With no current choice, the menu drops from the pill's bottom edge.
            menu.minimumWidth = view.bounds.width
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.height : 0), in: view)
            return
        }
        // A pop-up button's cell opens the menu with the current choice's title
        // over its own and at least as wide as the button. Its frame is moved so
        // that title sits where the pill's text does.
        let cell = NSPopUpButtonCell(textCell: "", pullsDown: false)
        cell.menu = menu
        cell.select(current)
        var frame = view.bounds
        frame.origin.x += titleInset - cell.titleRect(forBounds: frame).minX
        cell.performClick(withFrame: frame, in: view)
    }

    @objc private func run(_ item: NSMenuItem) {
        guard actions.indices.contains(item.tag) else { return }
        actions[item.tag]()
    }
}

/// Gives the anchor the pill's frame in AppKit; clicks pass through to the row.
private struct NXMenuAnchorView: NSViewRepresentable {
    let anchor: NXMenuAnchor

    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: Anchor, context: Context) {
        anchor.view = nsView
    }

    final class Anchor: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Opens the row's menu on mouse-down, as a pop-up button does, so a press
/// can drag to a choice and release on it.
private struct NXMenuPress: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> Press {
        let view = Press()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: Press, context: Context) {
        nsView.action = action
    }

    final class Press: NSView {
        var action: (() -> Void)?

        override func mouseDown(with event: NSEvent) { action?() }
    }
}
