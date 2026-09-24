//
//  DueDatePicker.swift
//  openlist
//

import SwiftData
import SwiftUI

/// Quick presets plus a calendar and optional time, matching how Superlist
/// lets you type or tap a due date.
struct DueDatePicker: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style

    @State private var selectedDate: Date = .now
    @State private var includesTime = false
    @State private var timeValue: Date = .now
    @State private var typedPhrase = ""

    private var calendar: Calendar { env.settings.calendar }

    var body: some View {
        // SwiftUI may update this child after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { liveContent }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            typeToSchedule

            VStack(alignment: .leading, spacing: 8) {
                NXCapsTitle(text: "Due")
                presets
            }

            CalendarMonthPicker(selection: block.dueDate, calendar: calendar) { date in
                selectedDate = date
                apply()
            }

            Rectangle().fill(NX.ink(0.07)).frame(height: 0.5)

            HStack(spacing: 8) {
                // The switch speaks for the row; its words toggle it too.
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(style.accent)
                    Text("Include a time")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(NX.ink)
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
                .onTapGesture { includesTimeBinding.wrappedValue.toggle() }
                .accessibilityHidden(true)
                if includesTime {
                    DatePicker("Due time", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 90)
                }
                NXToggle(isOn: includesTime, label: "Include a time") { includesTimeBinding.wrappedValue.toggle() }
            }

            if block.dueDate != nil {
                Button("Clear due date") {
                    env.store.setDueDate(nil, for: block)
                    load()
                }
                .buttonStyle(NXPanelButtonStyle(kind: .destructive, size: .small))
            }
        }
        .onAppear(perform: load)
        .onChange(of: block.dueDate) { _, _ in load() }
    }

    // MARK: - Natural language entry

    private var typeToSchedule: some View {
        VStack(alignment: .leading, spacing: 6) {
            NXPanelField(icon: "text.cursor") {
                TextField("Try “next friday at 9am”", text: $typedPhrase)
                    .onSubmit(applyTypedPhrase)
            }

            if !typedPhrase.isEmpty {
                let parsed = DateParser.parse(typedPhrase)
                if let date = parsed.date {
                    // An accent chip, like capture's token previews, that
                    // wraps when a long phrase outgrows the popover.
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(preview(date, includesTime: parsed.includesTime, recurrence: parsed.recurrence))
                            .font(.system(size: 11, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(style.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(style.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Text("Not recognised yet")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(NX.ink(0.4))
                }
            }
        }
    }

    private func preview(_ date: Date, includesTime: Bool, recurrence: Recurrence?) -> String {
        var text = includesTime
            ? date.formatted(date: .abbreviated, time: .shortened)
            : date.formatted(date: .abbreviated, time: .omitted)
        if let recurrence {
            text += " · \(recurrence.displayText)"
        }
        return text
    }

    private func applyTypedPhrase() {
        let parsed = DateParser.parse(typedPhrase)
        guard let date = parsed.date else { return }
        env.store.setDueDate(date, includesTime: parsed.includesTime, for: block)
        if let recurrence = parsed.recurrence {
            env.store.setRecurrence(recurrence, for: block)
        }
        typedPhrase = ""
        load()
    }

    // MARK: - Presets

    private var presets: some View {
        NXFlow(spacing: 4) {
            presetPill("Today", symbol: "sun.max", detail: shortWeekday(0), day: day(0)) {
                env.store.setDueToday(block)
            }
            presetPill("Tomorrow", symbol: "sun.horizon", detail: shortWeekday(1), day: day(1)) {
                env.store.setDueTomorrow(block)
            }
            presetPill("This weekend", symbol: "beach.umbrella", detail: weekendDetail, day: weekendDate) {
                if let date = weekendDate {
                    env.store.setDueDate(date, for: block)
                }
            }
            presetPill("Next week", symbol: "calendar", detail: shortWeekday(NXFormat.nextWeekOffset()),
                       day: day(NXFormat.nextWeekOffset())) {
                env.store.setDueNextWeek(block)
            }
        }
    }

    private func presetPill(_ title: String, symbol: String, detail: String, day: Date?,
                            action: @escaping () -> Void) -> some View {
        let isOn = day.flatMap { day in block.dueDate.map { calendar.isDate($0, inSameDayAs: day) } } ?? false
        return NXInspectorPill(isOn: isOn) {
            action()
            load()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .medium))
                Text(title)
            }
        }
        .help("\(title) · \(detail)")
        .accessibilityValue(detail)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func day(_ offset: Int) -> Date? {
        calendar.date(byAdding: .day, value: offset, to: .now)
    }

    private func shortWeekday(_ offset: Int) -> String {
        guard let date = calendar.date(byAdding: .day, value: offset, to: .now) else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private var weekendDetail: String {
        guard let date = weekendDate else { return "" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private var weekendDate: Date? {
        DateParser.parse("this weekend").date
    }

    // MARK: - State sync

    private func load() {
        selectedDate = block.dueDate ?? calendar.startOfDay(for: .now)
        includesTime = block.includesTime
        timeValue = block.dueDate ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    }

    // Hydration writes only the state above. Bindings persist actual control
    // edits, so opening or dismissing this popover can never assign a date.
    private var includesTimeBinding: Binding<Bool> {
        Binding(get: { includesTime }, set: { includesTime = $0; apply() })
    }

    private var timeBinding: Binding<Date> {
        Binding(get: { timeValue }, set: { timeValue = $0; apply() })
    }

    private func apply() {
        var result = calendar.startOfDay(for: selectedDate)
        if includesTime {
            let time = calendar.dateComponents([.hour, .minute], from: timeValue)
            result = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: result) ?? result
        }
        env.store.setDueDate(result, includesTime: includesTime, for: block)
    }
}
