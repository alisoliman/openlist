//
//  NextSettingsScreen.swift
//  openlist
//
//  Preferences, in the window: the design's groups first, then everything
//  else this Mac keeps. Openlist has no separate Settings window.
//

import AppKit
import SwiftUI

struct NextSettingsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    /// The row whose details are open beneath it.
    @State private var expanded: NXSettingsDetail?

    var body: some View {
        @Bindable var settings = env.settings
        NXPage {
            NXScreenHeader(tile: .icon("gearshape"), color: NX.grey, title: "Settings", subtitle: "Preferences for this Mac")
            VStack(alignment: .leading, spacing: 18) {
                NXSettingsGroup(title: "Tasks") {
                    NXSettingToggle(label: "Show completed tasks", hint: "Lists and Today expand their Completed section by default",
                                    isOn: $settings.showsCompletedTasks)
                    NXSettingMenu(label: "Week starts on", hint: "Used by Calendar and Activity", value: weekStartTitle,
                                  entries: nxChoices([0, 1, 2, 7], selection: $settings.firstWeekday) { weekday in
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
                                  entries: nxChoices([2, 3, 5, 8], selection: $settings.undoDwellSeconds) { "\($0) seconds" })
                }
                NXSettingsGroup(title: "Calendar") {
                    let preferences = env.calendar.preferences
                    ForEach(AvailabilityCategory.allCases) { category in
                        let detail = NXSettingsDetail.hours(category)
                        NXSettingValue(label: "\(category.title) hours", hint: "Planning uses these for \(category.title) lists",
                                       value: NXHours.summary(preferences.profile(for: category), calendar: settings.calendar),
                                       isExpanded: expanded == detail) { toggle(detail) }
                        if expanded == detail { NXHoursEditor(category: category) }
                    }
                    NXSettingMenu(label: "Default estimate", hint: "For tasks without their own",
                                  value: Self.estimate(env.workbench.defaultEstimate),
                                  entries: nxChoices(nxPresets([15, 30, 45, 60, 90], including: env.workbench.defaultEstimate),
                                                     selection: defaultEstimate, title: Self.estimate),
                                  custom: customEstimate)
                }
                NXSettingsGroup(title: "Library") {
                    let sync = env.sync.state
                    NXSettingValue(label: "iCloud sync", hint: syncHint(sync), value: syncValue(sync),
                                   isExpanded: expanded == .iCloud) { toggle(.iCloud) }
                    if expanded == .iCloud { NXICloudDetails() }
                    if let maintenance = env.libraryMaintenance {
                        let failure = maintenance.error ?? maintenance.pendingQuitError ?? maintenance.snapshotError
                        let daily = settings.takesDailySnapshots
                        NXSettingMenu(label: "Back up library",
                                      hint: failure ?? maintenance.status
                                          ?? (daily ? "Keeps \(LibrarySnapshots.retained) daily snapshots" : "Daily snapshots are off"),
                                      isError: failure != nil,
                                      value: maintenance.isBusy ? "Working…" : daily ? "Daily" : "Off",
                                      entries: nxChoices([true, false], selection: $settings.takesDailySnapshots) { $0 ? "Daily" : "Off" } + [
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
                }
                // Native additions follow the design's groups.
                NXSettingsGroup(title: "Appearance") {
                    NXSettingMenu(label: "Appearance", hint: "Light, dark or follow the system", value: settings.appearance.title,
                                  entries: nxChoices(AppSettings.Appearance.allCases, selection: $settings.appearance, title: \.title))
                    NXSettingMenu(label: "Motion", hint: "How lively completions, triage and transitions feel",
                                  value: settings.motion.title,
                                  entries: nxChoices(NextMotion.allCases, selection: $settings.motion, title: \.title))
                    NXSettingMenu(label: "Accent", hint: "Selection, focus and today’s highlights", value: settings.accent.title,
                                  swatch: settings.accent.color,
                                  entries: nxChoices(NextAccent.allCases, selection: $settings.accent, title: \.title))
                    NXSettingMenu(label: "Density", hint: "Row spacing in lists", value: settings.density.title,
                                  entries: nxChoices(NextDensity.allCases, selection: $settings.density, title: \.title))
                    NXSettingToggle(label: "Serif titles", hint: "Screen titles in Instrument Serif", isOn: $settings.serifTitles)
                    NXSettingMenu(label: "Tasks filter", hint: "Type a query, or build a sentence from pills",
                                  value: settings.tasksFilterStyle.title,
                                  entries: nxChoices(TasksFilterStyle.allCases, selection: $settings.tasksFilterStyle, title: \.title))
                }
                NXSettingsGroup(title: "General") {
                    NXSettingToggle(label: "Show in the menu bar", hint: "Capture a task and see what’s due from the menu bar",
                                    isOn: $settings.showsMenuBarExtra)
                    NXSettingToggle(label: "Dock badge", hint: "Shows the unfinished count on the Dock icon",
                                    isOn: $settings.showsDockBadge)
                    NXSettingToggle(label: "Confirm before deleting a list", hint: "Asks before a list and everything in it is deleted",
                                    isOn: $settings.confirmsBeforeDeletingLists)
                }
                NXSettingsGroup(title: "Capture") {
                    NXSettingMenu(label: "New tasks go to", hint: "Today makes an undated capture due today",
                                  value: settings.defaultDestination.title,
                                  entries: nxChoices(AppSettings.DefaultDestination.allCases, selection: $settings.defaultDestination,
                                                     title: \.title))
                    NXSettingToggle(label: "Read dates from what you type",
                                    hint: "“call mum tomorrow at 6pm” sets a due date and trims the phrase from the task",
                                    isOn: $settings.parsesNaturalLanguageDates)
                }
                NXNotificationSettings()
                NXPlanningSettings()
                NXLabelSettings()
                NXAgentSettings()
                NXDataSettings()
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.top, 20)
        }
    }

    private func toggle(_ detail: NXSettingsDetail) {
        withAnimation(style.ease(200)) { expanded = expanded == detail ? nil : detail }
    }

    /// Planning's estimate for tasks without their own.
    private var defaultEstimate: Binding<Int> {
        Binding(get: { env.workbench.defaultEstimate }, set: { minutes in
            var updated = env.calendar.preferences
            updated.defaultEstimateMinutes = Double(minutes)
            env.calendar.updatePreferences(updated)
        })
    }

    /// Any whole number of minutes up to a day. Planning in the window treats
    /// less than 5 as 5, so that's the least that can be typed.
    private var customEstimate: NXCustomValue {
        NXCustomValue(label: "Default estimate in minutes", placeholder: "Minutes",
                      initial: "\(env.workbench.defaultEstimate)", unit: "min") { text in
            guard let minutes = Int(text.trimmingCharacters(in: .whitespaces)), (5...1440).contains(minutes) else { return false }
            defaultEstimate.wrappedValue = minutes
            return true
        }
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

/// Rows whose details open beneath them.
private enum NXSettingsDetail: Hashable {
    case hours(AvailabilityCategory)
    case iCloud
}

/// "Mon–Fri 09:00–17:00" for a weekly availability profile.
enum NXHours {
    static func summary(_ profile: AvailabilityProfile, calendar: Calendar) -> String {
        let days = weekdays(calendar)
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

    /// "09:00", and "24:00" for the end of the day.
    static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60 % 24 + (minute == 1440 ? 24 : 0), minute % 60)
    }

    /// The days of the week in the order `calendar` starts them, as weekday numbers.
    static func weekdays(_ calendar: Calendar) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// A typed time as minutes after midnight: "8:50", "08.50", "0850" or
    /// "8". "24:00" is the end of the day.
    static func minute(from text: String) -> Int? {
        let typed = text.trimmingCharacters(in: .whitespaces)
        let parts = typed.split { $0 == ":" || $0 == "." }.map(String.init)
        let hour: Int?, minute: Int?
        if parts.count == 2, parts[1].count == 2 {
            (hour, minute) = (Int(parts[0]), Int(parts[1]))
        } else if (1...4).contains(typed.count), typed.allSatisfy({ $0.isASCII && $0.isNumber }) {
            (hour, minute) = typed.count <= 2 ? (Int(typed), 0) : (Int(typed.dropLast(2)), Int(typed.suffix(2)))
        } else {
            return nil
        }
        guard let hour, let minute, (0...24).contains(hour), (0...59).contains(minute), hour * 60 + minute <= 1440 else { return nil }
        return hour * 60 + minute
    }
}

/// The presets, with `value` among them in order when it isn't one, so a
/// value set elsewhere still shows as the current choice.
func nxPresets(_ presets: [Int], including value: Int) -> [Int] {
    presets.contains(value) ? presets : (presets + [value]).sorted()
}

// MARK: - Groups and rows

/// The design's settings card: a caps title over rows on a white card. Its
/// buttons are value pills unless they choose their own style.
struct NXSettingsGroup<Content: View>: View {
    let title: String
    /// A note under the card, in the rows' hint type.
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NXCapsTitle(text: title).padding(.horizontal, 4).padding(.bottom, 8)
            VStack(spacing: 0) { content }
                .buttonStyle(NXSettingButtonStyle())
                .background(NX.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NX.ink(0.12), lineWidth: 0.5))
            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(NX.ink(0.48))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
            }
        }
    }
}

/// One line of a settings card: the design's padding, top hairline and hover.
struct NXSettingLine<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? NX.ink(0.02) : .clear)
            .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.06)).frame(height: 0.5) }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// A label and its hint, with the row's control on the trailing edge.
struct NXSettingRow<Accessory: View>: View {
    let label: String
    let hint: String
    var hintColor = NX.ink(0.48)
    /// Lets the hint be selected and copied, for errors and addresses.
    var selectable = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        NXSettingLine {
            NXSettingRowLayout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(NX.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !hint.isEmpty {
                        let text = Text(hint).font(.system(size: 11.5)).foregroundStyle(hintColor).fixedSize(horizontal: false, vertical: true)
                        if selectable { text.textSelection(.enabled) } else { text }
                    }
                }
                HStack(spacing: 6) { accessory }
            }
        }
    }
}

/// The label beside its control, as the design lays a row out, or the
/// control beneath the label when a narrow window leaves the label too little
/// room beside a wide control.
private struct NXSettingRowLayout: Layout {
    var spacing: CGFloat = 12
    var minimumTextWidth: CGFloat = 170

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (text, accessory, sideBySide) = measure(proposal.width, subviews)
        let width = proposal.width ?? (text.width + (sideBySide ? spacing + accessory.width : 0))
        let height = sideBySide ? max(text.height, accessory.height) : text.height + (accessory == .zero ? 0 : 8 + accessory.height)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let first = subviews.first else { return }
        let (text, accessory, sideBySide) = measure(bounds.width, subviews)
        if sideBySide {
            first.place(at: CGPoint(x: bounds.minX, y: bounds.midY - text.height / 2),
                        proposal: ProposedViewSize(width: text.width, height: text.height))
            if subviews.count > 1 {
                subviews[1].place(at: CGPoint(x: bounds.maxX - accessory.width, y: bounds.midY - accessory.height / 2),
                                  proposal: ProposedViewSize(accessory))
            }
        } else {
            first.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: text.height))
            if subviews.count > 1 {
                subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + text.height + 8), proposal: ProposedViewSize(accessory))
            }
        }
    }

    /// The text's and control's sizes, and whether they share the line.
    private func measure(_ width: CGFloat?, _ subviews: Subviews) -> (CGSize, CGSize, Bool) {
        guard let first = subviews.first else { return (.zero, .zero, true) }
        let accessory = subviews.count > 1 ? subviews[1].sizeThatFits(.unspecified) : .zero
        let gap = accessory.width > 0 ? spacing : 0
        guard let width, width.isFinite else {
            return (first.sizeThatFits(.unspecified), accessory, true)
        }
        let textWidth = width - accessory.width - gap
        if textWidth >= min(minimumTextWidth, first.sizeThatFits(.unspecified).width) {
            return (first.sizeThatFits(ProposedViewSize(width: max(0, textWidth), height: nil)), accessory, true)
        }
        return (first.sizeThatFits(ProposedViewSize(width: width, height: nil)), accessory, false)
    }
}

extension NXSettingRow where Accessory == EmptyView {
    init(label: String, hint: String, hintColor: Color = NX.ink(0.48), selectable: Bool = false) {
        self.init(label: label, hint: hint, hintColor: hintColor, selectable: selectable) { EmptyView() }
    }
}

struct NXSettingToggle: View {
    @Environment(\.nextStyle) private var style
    @Environment(\.isEnabled) private var isEnabled
    let label: String
    let hint: String
    @Binding var isOn: Bool

    var body: some View {
        NXSettingRow(label: label, hint: hint) {
            // A button, so Tab reaches the switch and Space flips it.
            Button { isOn.toggle() } label: {
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
            .buttonStyle(NXBareButtonStyle(radius: 10))
        }
        .opacity(isEnabled ? 1 : 0.45)
        .onTapGesture { if isEnabled { isOn.toggle() } }
        .accessibilityRepresentation { Toggle(label, isOn: $isOn).accessibilityHint(hint) }
    }
}

/// The design's value pill: `500 12px/1`, `6px 9px`, radius 7 on ink 0.05.
struct NXValuePill: View {
    let text: String
    var swatch: Color?
    /// Shows a chevron that turns up while the row's details are open.
    var isExpanded: Bool?
    var monospacedDigits = false
    var hovering = false

    /// Where the text starts, from the pill's leading edge: its padding, then
    /// the swatch and its gap.
    static func textInset(hasSwatch: Bool) -> CGFloat { hasSwatch ? 9 + 9 + 6 : 9 }

    var body: some View {
        HStack(spacing: 6) {
            if let swatch { Circle().fill(swatch).frame(width: 9, height: 9) }
            Text(text).monospacedDigit(monospacedDigits)
            if let isExpanded {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(NX.ink(0.4))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        // The design's `12px/1` line box, so the pill is 24pt tall.
        .frame(height: 12)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(NX.ink(0.55))
        .lineLimit(1)
        .padding(.vertical, 6)
        .padding(.horizontal, 9)
        .background(NX.ink(hovering ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private extension Text {
    func monospacedDigit(_ enabled: Bool) -> Text { enabled ? monospacedDigit() : self }
}

struct NXSettingValue: View {
    let label: String
    let hint: String
    let value: String
    /// Set when the row opens details beneath it rather than acting.
    var isExpanded: Bool?
    let action: () -> Void

    var body: some View {
        NXSettingRow(label: label, hint: hint) {
            Button(action: action) { NXValuePill(text: value, isExpanded: isExpanded) }
                .buttonStyle(NXBareButtonStyle())
        }
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isExpanded.map { "\(value), \($0 ? "expanded" : "collapsed")" } ?? value)
        .accessibilityAction { action() }
    }
}

/// Details that open beneath a row, on the design's inset panel.
struct NXSettingDetail<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.vertical, 4)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NX.inspector, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NX.ink(0.08), lineWidth: 0.5))
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .transition(.opacity)
    }
}

// MARK: - Buttons and fields

/// A settings action drawn as the row's value pill, darker on hover. A
/// destructive button is red.
struct NXSettingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration)
    }

    private struct Pill: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            let destructive = configuration.role == .destructive
            let active = hovering && isEnabled
            configuration.label
                .frame(height: 12)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(destructive ? NX.redText : NX.ink(active ? 0.75 : 0.6))
                .padding(.vertical, 6)
                .padding(.horizontal, 9)
                .background(destructive ? NX.red.opacity(active ? 0.16 : 0.1) : NX.ink(active ? 0.09 : 0.05),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .opacity(isEnabled ? configuration.isPressed ? 0.8 : 1 : 0.45)
                .fixedSize()
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.14), value: hovering)
        }
    }
}

/// The design's dialog buttons: `600 12px/1`, `8px 12px`, radius 8. Primary
/// is the triage card's dark "Keep for later", secondary its grey "Review
/// kept tasks", destructive the Trash's red.
struct NXDialogButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        Chrome(configuration: configuration, kind: kind)
    }

    private struct Chrome: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let kind: Kind
        @State private var hovering = false

        var body: some View {
            let active = hovering && isEnabled
            configuration.label
                // The design's `12px/1` line box, so the button is 28pt tall.
                .frame(height: 12)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(fill(active), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(isEnabled ? configuration.isPressed ? 0.8 : 1 : 0.45)
                .fixedSize()
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.14), value: hovering)
        }

        private var foreground: Color {
            switch kind {
            case .primary: .white
            case .secondary: NX.ink(0.7)
            case .destructive: NX.redText
            }
        }

        private func fill(_ active: Bool) -> Color {
            switch kind {
            case .primary: active ? NX.primaryButtonHover : NX.primaryButton
            case .secondary: NX.ink(active ? 0.1 : 0.06)
            case .destructive: NX.red.opacity(active ? 0.18 : 0.1)
            }
        }
    }
}

/// A control drawn only as its label, like a switch or a value pill, which
/// shows its own hover and disabled look. As a button, Tab reaches it with
/// keyboard navigation on and Space presses it; its focus ring follows `radius`.
struct NXBareButtonStyle: ButtonStyle {
    var radius: CGFloat = 7

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.focusEffect, RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A short value typed into a pill, like a port or a new label's name.
struct NXSettingField: View {
    @Environment(\.nextStyle) private var style
    let placeholder: String
    @Binding var text: String
    var width: CGFloat?
    var monospaced = false
    var onSubmit: () -> Void = {}
    /// What VoiceOver calls the field, when the placeholder says too little.
    var label: String?
    /// Takes focus as it appears, like a value typed in place of a pill.
    var focusesOnAppear = false
    /// Runs when focus leaves the field.
    var onBlur: (() -> Void)?
    /// Runs on Escape.
    var onCancel: (() -> Void)?
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(monospaced ? NX.mono(12, weight: .regular) : .system(size: 12.5))
            .foregroundStyle(NX.ink)
            .focused($focused)
            .onSubmit(onSubmit)
            .onExitCommand(perform: onCancel)
            // Focus once the field is on screen; set as it's inserted, it can miss.
            .onAppear { if focusesOnAppear { DispatchQueue.main.async { focused = true } } }
            .onChange(of: focused) { _, isFocused in if !isFocused { onBlur?() } }
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .frame(width: width)
            .background(NX.ink(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(focused ? style.accent.opacity(0.6) : .clear, lineWidth: 1))
            .accessibilityLabel(label ?? placeholder)
    }
}

/// A value a menu doesn't list, offered as its "Custom…" entry and typed in
/// place of the pill.
struct NXCustomValue {
    /// What VoiceOver calls the field.
    let label: String
    let placeholder: String
    /// The field's text as it opens: the current value.
    let initial: String
    /// Shown after the field, like "min".
    var unit: String?
    var width: CGFloat = 56
    var monospaced = false
    /// Sets the value from the typed text; false when the text isn't one.
    let commit: (String) -> Bool
}

/// The field a "Custom…" entry opens in place of its pill. Return sets the
/// value, or beeps when the text isn't one; leaving the field sets a valid
/// value and closes it; Escape puts the pill back as it was.
private struct NXCustomValueField: View {
    let custom: NXCustomValue
    /// The text being typed; nil puts the pill back.
    @Binding var text: String?

    var body: some View {
        HStack(spacing: 5) {
            NXSettingField(placeholder: custom.placeholder, text: Binding(get: { text ?? "" }, set: { text = $0 }),
                           width: custom.width, monospaced: custom.monospaced, onSubmit: submit, label: custom.label,
                           focusesOnAppear: true, onBlur: finish, onCancel: { text = nil })
            if let unit = custom.unit {
                Text(unit).font(.system(size: 12, weight: .medium)).foregroundStyle(NX.ink(0.48))
            }
        }
    }

    private func submit() {
        guard let typed = text else { return }
        if custom.commit(typed) { text = nil } else { NSSound.beep() }
    }

    private func finish() {
        guard let typed = text else { return }
        _ = custom.commit(typed)
        text = nil
    }
}

// MARK: - Menus

/// One line in a setting's pop-up menu.
enum NXMenuEntry {
    /// A value to pick; the current one is checked and opens over the pill.
    case choice(String, isSelected: Bool, swatch: Color? = nil, action: () -> Void)
    case command(String, isEnabled: Bool = true, action: () -> Void)
    case divider
}

/// A choice for each value, checked for the one `selection` holds.
func nxChoices<Value: Hashable>(_ values: [Value], selection: Binding<Value>,
                                title: (Value) -> String) -> [NXMenuEntry] {
    values.map { value in
        .choice(title(value), isSelected: selection.wrappedValue == value) { selection.wrappedValue = value }
    }
}

/// A row whose value pill pops up a menu, the way a pop-up button does:
/// the current choice opens over the pill. Pressing anywhere on the row opens
/// it, and so does Space once Tab has reached the pill.
struct NXSettingMenu: View {
    let label: String
    let hint: String
    /// Shows the hint as a failure, like a backup that could not be written.
    var isError = false
    let value: String
    var swatch: Color?
    let entries: [NXMenuEntry]
    /// Adds "Custom…", for a value the menu doesn't list.
    var custom: NXCustomValue?
    @State private var anchor = NXMenuAnchor()
    /// The custom value being typed in place of the pill.
    @State private var customText: String?

    var body: some View {
        let hintColor = isError ? NX.redText : NX.ink(0.48)
        if let custom, customText != nil {
            NXSettingRow(label: label, hint: hint, hintColor: hintColor) {
                NXCustomValueField(custom: custom, text: $customText)
            }
        } else {
            NXSettingRow(label: label, hint: hint, hintColor: hintColor) {
                Button(action: popUp) { NXValuePill(text: value, swatch: swatch) }
                    .buttonStyle(NXBareButtonStyle())
                    .background { NXMenuAnchorView(anchor: anchor) }
            }
            .overlay { NXMenuPress(action: popUp) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { popUp() }
        }
    }

    private func popUp() {
        let more: [NXMenuEntry] = custom.map { custom in [.divider, .command("Custom…") { customText = custom.initial }] } ?? []
        anchor.popUp(entries + more, titleInset: NXValuePill.textInset(hasSwatch: swatch != nil))
    }
}

/// A value pill on its own that pops up its menu, like a time in the hours
/// editor. Space opens it too, once Tab has reached it.
struct NXPopUpPill: View {
    @Environment(\.isEnabled) private var isEnabled
    let value: String
    /// What VoiceOver calls the pill; it reads the value after it.
    let label: String
    var swatch: Color?
    var monospacedDigits = false
    /// Lets the pill shrink, truncating its text, rather than overflow a
    /// narrow row.
    var truncates = false
    /// Adds "Custom…", for a value the menu doesn't list.
    var custom: NXCustomValue?
    let entries: [NXMenuEntry]
    @State private var anchor = NXMenuAnchor()
    @State private var hovering = false
    /// The custom value being typed in place of the pill.
    @State private var customText: String?

    var body: some View {
        if let custom, customText != nil {
            NXCustomValueField(custom: custom, text: $customText)
        } else {
            Button(action: popUp) {
                NXValuePill(text: value, swatch: swatch, monospacedDigits: monospacedDigits, hovering: hovering && isEnabled)
            }
            .buttonStyle(NXBareButtonStyle())
            .background { NXMenuAnchorView(anchor: anchor) }
            .overlay { NXMenuPress(action: popUp) }
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 }
            .fixedSize(horizontal: !truncates, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { popUp() }
        }
    }

    private func popUp() {
        guard isEnabled else { return }
        let more: [NXMenuEntry] = custom.map { custom in [.divider, .command("Custom…") { customText = custom.initial }] } ?? []
        anchor.popUp(entries + more, titleInset: NXValuePill.textInset(hasSwatch: swatch != nil))
    }
}

/// Pops an AppKit menu from the view it's attached to.
@MainActor
final class NXMenuAnchor: NSObject {
    weak var view: NSView?
    /// The open menu's actions, by item tag.
    private var actions: [() -> Void] = []

    /// `titleInset` is where the pill's text starts, from its leading edge.
    /// `dropsDown` opens the menu below the view even when it has a current
    /// choice, for anchors with no title to line it up with.
    func popUp(_ entries: [NXMenuEntry], titleInset: CGFloat, dropsDown: Bool = false) {
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
            case let .choice(title, isSelected, swatch, action):
                let item = add(title, action)
                item.state = isSelected ? .on : .off
                if let swatch { item.image = Self.swatchImage(NSColor(swatch)) }
                if isSelected { current = item }
            case let .command(title, isEnabled, action):
                add(title, action).isEnabled = isEnabled
            case .divider:
                menu.addItem(.separator())
            }
        }
        guard let current, !dropsDown else {
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

    /// A colour dot for a menu item, like a label's colour.
    private static func swatchImage(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        return image
    }

    @objc private func run(_ item: NSMenuItem) {
        guard actions.indices.contains(item.tag) else { return }
        actions[item.tag]()
    }
}

/// Gives the anchor the pill's frame in AppKit; clicks pass through to the row.
struct NXMenuAnchorView: NSViewRepresentable {
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
struct NXMenuPress: NSViewRepresentable {
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
