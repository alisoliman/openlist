//
//  NextSettingsHours.swift
//  openlist
//
//  Work and Personal hours, opened beneath their Calendar rows, and the rest
//  of planning: the minimum session and connected calendars.
//

import AppKit
import SwiftUI

/// One category's weekly hours and breaks, and the dates that replace them.
struct NXHoursEditor: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let category: AvailabilityCategory
    /// The weekday whose windows are open for editing.
    @State private var openDay: Int?
    @State private var draft: NXOverrideDraft?

    var body: some View {
        let profile = env.calendar.preferences.profile(for: category)
        NXSettingDetail {
            NXHoursCaption(title: "Weekly hours", hint: "Lists use either Work or Personal hours, chosen in each list’s options.")
            ForEach(NXHours.weekdays(env.settings.calendar), id: \.self) { weekday in
                day(weekday, windows: profile.weekly[weekday] ?? [])
            }
            NXHoursCaption(title: "Date overrides", hint: "Replace a day’s usual hours, or leave it unavailable.")
                .padding(.top, 8)
            ForEach(profile.overrides.sorted { $0.date < $1.date }) { item in
                override(item)
            }
            if let editing = Binding($draft) {
                NXOverrideEditor(category: category, draft: editing) {
                    save(editing.wrappedValue)
                } cancel: {
                    withAnimation(style.ease(180)) { draft = nil }
                }
            } else {
                Button("Add date override…") {
                    withAnimation(style.ease(180)) { draft = NXOverrideDraft(date: .now, windows: [], breaks: []) }
                }
                .padding(.vertical, 10)
            }
        }
    }

    private func day(_ weekday: Int, windows: [AvailabilityWindow]) -> some View {
        let isOpen = openDay == weekday
        let name = Calendar.current.weekdaySymbols[weekday - 1]
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(style.ease(180)) { openDay = isOpen ? nil : weekday }
            } label: {
                HStack(spacing: 8) {
                    Text(name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(NX.ink)
                    Spacer(minLength: 8)
                    Text(NXWindows.summary(windows))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(NX.ink(0.55))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(NX.ink(0.35))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityValue("\(NXWindows.summary(windows)), \(isOpen ? "expanded" : "collapsed")")
            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    NXWindowsEditor(title: "Available", windows: weekly(weekday, breaks: false))
                    NXWindowsEditor(title: "Breaks", windows: weekly(weekday, breaks: true))
                }
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.06)).frame(height: 0.5) }
    }

    private func override(_ item: AvailabilityOverride) -> some View {
        // Named as the pills name a day, spoken in full.
        let date = item.date.formatted(date: .complete, time: .omitted)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NXFormat.dayLabel(item.date)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(NX.ink)
                Text(NXWindows.summary(item.windows)).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(NX.ink(0.48))
            }
            Spacer(minLength: 8)
            Button("Edit") {
                withAnimation(style.ease(180)) {
                    draft = NXOverrideDraft(id: item.id, date: item.date, windows: item.windows, breaks: item.breaks)
                }
            }
            .accessibilityLabel("Edit override for \(date)")
            NXRemoveButton(label: "Remove override for \(date)") {
                change { $0.overrides.removeAll { $0.id == item.id } }
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.06)).frame(height: 0.5) }
    }

    private func weekly(_ weekday: Int, breaks: Bool) -> Binding<[AvailabilityWindow]> {
        Binding(get: {
            let profile = env.calendar.preferences.profile(for: category)
            return (breaks ? profile.breaks : profile.weekly)[weekday] ?? []
        }, set: { values in
            change { profile in
                if breaks { profile.breaks[weekday] = values } else { profile.weekly[weekday] = values }
            }
        })
    }

    private func save(_ draft: NXOverrideDraft) {
        let day = Calendar.current.startOfDay(for: draft.date)
        change { profile in
            profile.overrides.removeAll { $0.id == draft.id || Calendar.current.isDate($0.date, inSameDayAs: day) }
            profile.overrides.append(AvailabilityOverride(date: day, windows: draft.windows, breaks: draft.breaks))
        }
        withAnimation(style.ease(180)) { self.draft = nil }
    }

    private func change(_ edit: (inout AvailabilityProfile) -> Void) {
        var preferences = env.calendar.preferences
        if category == .work { edit(&preferences.work) } else { edit(&preferences.personal) }
        env.calendar.updatePreferences(preferences)
    }
}

/// A date override while it's being added or edited.
private struct NXOverrideDraft {
    /// The override being edited; nil for a new one.
    var id: UUID?
    var date: Date
    var windows: [AvailabilityWindow]
    var breaks: [AvailabilityWindow]
}

/// Edits a date override in place of the "Add date override…" button.
private struct NXOverrideEditor: View {
    @Environment(AppEnvironment.self) private var env
    let category: AvailabilityCategory
    @Binding var draft: NXOverrideDraft
    let save: () -> Void
    let cancel: () -> Void
    @State private var picksDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(category.title) hours on")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(NX.ink)
                // The shared date pill, which darkens under the pointer as
                // the From and To pills beside it do.
                NXDatePill(label: "Date", date: draft.date, isOpen: picksDate) { picksDate.toggle() }
                    .popover(isPresented: $picksDate, arrowEdge: .bottom) {
                        CalendarMonthPicker(selection: draft.date, calendar: env.settings.calendar) { date in
                            draft.date = date
                            picksDate = false
                        }
                        .frame(width: 260)
                        .padding(12)
                    }
            }
            NXWindowsEditor(title: "Available", windows: $draft.windows)
            NXWindowsEditor(title: "Breaks", windows: $draft.breaks)
            Text(draft.windows.isEmpty ? "This day will be unavailable." : "These hours replace the weekly schedule for this date.")
                .font(.system(size: 11.5))
                .foregroundStyle(NX.ink(0.48))
            HStack(spacing: 6) {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary))
                Button("Save override", action: save)
                    .buttonStyle(NXPanelButtonStyle(kind: .primary))
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.06)).frame(height: 0.5) }
        // Return saves and Escape cancels.
        .background { NXEditorKeys(onReturn: save, onEscape: cancel) }
    }
}

/// Gives an inline editor Return and Escape. The window's key handler takes
/// them for its rows unless a view of its own has the keys, so this view
/// takes first responder as the editor opens and keeps it while clicks land
/// inside the editor. Other keys travel on as usual.
private struct NXEditorKeys: NSViewRepresentable {
    let onReturn: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> Keys {
        let view = Keys()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: Keys, context: Context) {
        nsView.onReturn = onReturn
        nsView.onEscape = onEscape
    }

    final class Keys: NSView {
        var onReturn: (() -> Void)?
        var onEscape: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }
        // Not a stop of its own when Tab moves through the window.
        override var canBecomeKeyView: Bool { false }
        // Clicks reach the editor's controls.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
                return super.keyDown(with: event)
            }
            switch event.keyCode {
            case 36, 76: onReturn?()
            case 53: onEscape?()
            default: super.keyDown(with: event)
            }
        }
    }
}

/// A day's available or break windows, each a pair of times.
private struct NXWindowsEditor: View {
    let title: String
    @Binding var windows: [AvailabilityWindow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                NXCapsTitle(text: title)
                Spacer()
                Button {
                    windows.append(AvailabilityWindow(startMinute: title == "Breaks" ? 720 : 540, endMinute: title == "Breaks" ? 780 : 1020))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 9.5, weight: .semibold))
                        Text("Add").font(.system(size: 11.5, weight: .medium))
                    }
                }
                .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 6,
                                                padding: EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6),
                                                foreground: NX.ink(0.5), hoverForeground: NX.ink))
                .accessibilityLabel("Add \(title.lowercased()) time")
            }
            ForEach(windows.indices, id: \.self) { index in
                HStack(spacing: 6) {
                    NXPopUpPill(value: NXHours.clock(windows[index].startMinute), label: "From", monospacedDigits: true,
                                custom: customTime("From", index, end: false), entries: startEntries(index))
                    Text("–").font(.system(size: 12)).foregroundStyle(NX.ink(0.4))
                    NXPopUpPill(value: NXHours.clock(windows[index].endMinute), label: "To", monospacedDigits: true,
                                custom: customTime("To", index, end: true), entries: endEntries(index))
                    NXRemoveButton(label: "Remove \(title.lowercased()) time") { windows.remove(at: index) }
                }
            }
            if windows.isEmpty {
                Text(title == "Breaks" ? "No breaks" : "Unavailable")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NX.ink(0.42))
            }
        }
    }

    /// Every quarter hour, and the current start when it's between them.
    private func startEntries(_ index: Int) -> [NXMenuEntry] {
        let current = windows[index].startMinute
        return nxPresets(Array(stride(from: 0, to: 1440, by: 15)), including: current).map { minute in
            .choice(NXHours.clock(minute), isSelected: minute == current) { setStart(index, minute) }
        }
    }

    /// Every quarter hour after the start, through the end of the day.
    private func endEntries(_ index: Int) -> [NXMenuEntry] {
        let window = windows[index]
        let times = Array(stride(from: 15, through: 1440, by: 15)).filter { $0 > window.startMinute }
        return nxPresets(times, including: window.endMinute).map { minute in
            .choice(NXHours.clock(minute), isSelected: minute == window.endMinute) { setEnd(index, minute) }
        }
    }

    /// Any minute, typed, for a time between the quarter hours. An end must
    /// come after the start; "00:00" ends at midnight.
    private func customTime(_ label: String, _ index: Int, end: Bool) -> NXCustomValue {
        let window = windows[index]
        return NXCustomValue(label: label, placeholder: "HH:MM", initial: NXHours.clock(end ? window.endMinute : window.startMinute),
                             width: 58, monospaced: true) { text in
            guard windows.indices.contains(index), let minute = NXHours.minute(from: text) else { return false }
            if end {
                guard minute == 0 || minute > windows[index].startMinute else { return false }
                setEnd(index, minute)
            } else {
                guard minute < 1440 else { return false }
                setStart(index, minute)
            }
            return true
        }
    }

    private func setStart(_ index: Int, _ minute: Int) {
        guard windows.indices.contains(index) else { return }
        windows[index].startMinute = min(minute, 1439)
        windows[index].endMinute = max(windows[index].endMinute, windows[index].startMinute + 1)
    }

    private func setEnd(_ index: Int, _ minute: Int) {
        guard windows.indices.contains(index) else { return }
        windows[index].endMinute = minute == 0 ? 1440 : max(windows[index].startMinute + 1, minute)
    }
}

enum NXWindows {
    /// "09:00–12:00, 13:00–17:00", or "Unavailable".
    static func summary(_ windows: [AvailabilityWindow]) -> String {
        if windows.isEmpty { return "Unavailable" }
        return windows.map { "\(NXHours.clock($0.startMinute))–\(NXHours.clock($0.endMinute))" }.joined(separator: ", ")
    }
}

/// A caps caption and its hint, heading a part of the hours editor.
private struct NXHoursCaption: View {
    let title: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            NXCapsTitle(text: title)
            Text(hint).font(.system(size: 11.5)).foregroundStyle(NX.ink(0.48)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

/// A small × that removes a time or an override, red on hover.
private struct NXRemoveButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.red.opacity(0.1), radius: 6,
                                        padding: EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5),
                                        foreground: NX.ink(0.4), hoverForeground: NX.redText))
        .accessibilityLabel(label)
        .help(label)
    }
}

// MARK: - Planning

/// The minimum session and the macOS calendars planning works around.
struct NXPlanningSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isConnecting = false

    var body: some View {
        let external = env.calendar.externalCalendars
        let minimum = env.calendar.preferences.minimumSessionMinutes
        NXSettingsGroup(title: "Planning",
                        footer: "A rolling four-week plan. Work that runs past its slot moves the tasks after it; Undo moves them back. Connected calendars are read-only busy time; your events are never changed.") {
            NXSettingMenu(label: "Minimum session", hint: "Tasks shorter than this can still use shorter slots",
                          value: "\(minimum) min",
                          // Every 5 minutes up to 2 hours.
                          entries: nxChoices(nxPresets(Array(stride(from: 5, through: 120, by: 5)), including: minimum),
                                             selection: minimumSession) { "\($0) minutes" })
            NXSettingRow(label: "Connected calendars", hint: external.error ?? external.authorizationDescription,
                         hintColor: external.error == nil ? NX.ink(0.48) : NX.amberText) {
                if external.isConnected {
                    HStack(spacing: 6) {
                        Button("Refresh") { env.calendar.refreshCalendars() }
                            .accessibilityLabel("Refresh calendars")
                        Button("Disconnect") { external.disconnect() }
                    }
                } else {
                    Button(isConnecting ? "Connecting…" : "Connect macOS calendars") {
                        isConnecting = true
                        Task {
                            await external.requestAccess()
                            env.calendar.refreshCalendars()
                            isConnecting = false
                        }
                    }
                    .disabled(isConnecting)
                }
            }
            if external.isConnected {
                ForEach(external.calendars) { source in
                    NXSettingToggle(label: source.title, hint: source.source, isOn: Binding(get: {
                        external.selectedCalendarIDs.contains(source.id)
                    }, set: { enabled in
                        external.setCalendarEnabled(source.id, enabled: enabled)
                        env.calendar.refreshCalendars()
                    }))
                }
                if external.calendars.isEmpty {
                    NXSettingRow(label: "No calendars found", hint: "Add an account in macOS Calendar, then refresh.")
                }
            }
        }
    }

    private var minimumSession: Binding<Int> {
        Binding(get: { env.calendar.preferences.minimumSessionMinutes }, set: { minutes in
            var updated = env.calendar.preferences
            updated.minimumSessionMinutes = minutes
            env.calendar.updatePreferences(updated)
        })
    }
}
