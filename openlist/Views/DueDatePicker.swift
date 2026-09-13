//
//  DueDatePicker.swift
//  openlist
//

import SwiftUI

/// Quick presets plus a calendar and optional time, matching how Superlist
/// lets you type or tap a due date.
struct DueDatePicker: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env

    @State private var selectedDate: Date = .now
    @State private var includesTime = false
    @State private var timeValue: Date = .now
    @State private var typedPhrase = ""

    private var calendar: Calendar { env.settings.calendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            typeToSchedule
            Divider()
            presets
            Divider()

            CalendarMonthPicker(selection: block.dueDate, calendar: calendar) { date in
                selectedDate = date
                apply()
            }

            Divider()

            HStack {
                Toggle("Include a time", isOn: includesTimeBinding)
                    .toggleStyle(.checkbox)
                    .font(Theme.Font.body)

                Spacer()

                if includesTime {
                    DatePicker("Due time", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 90)
                }
            }

            if block.dueDate != nil {
                Divider()
                Button("Clear due date") {
                    env.store.setDueDate(nil, for: block)
                    load()
                }
                .buttonStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(ListAccent.red.color)
            }
        }
        .onAppear(perform: load)
        .onChange(of: block.dueDate) { _, _ in load() }
    }

    // MARK: - Natural language entry

    private var typeToSchedule: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Try “next friday at 9am”", text: $typedPhrase)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Font.body)
                .onSubmit(applyTypedPhrase)

            if !typedPhrase.isEmpty {
                let parsed = DateParser.parse(typedPhrase)
                if let date = parsed.date {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 9))
                        Text(preview(date, includesTime: parsed.includesTime, recurrence: parsed.recurrence))
                    }
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.accent)
                } else {
                    Text("Not recognised yet")
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.tertiaryText)
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
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
            presetRow("Today", symbol: "sun.max", detail: shortWeekday(0)) {
                env.store.setDueToday(block)
            }
            presetRow("Tomorrow", symbol: "sunrise", detail: shortWeekday(1)) {
                env.store.setDueTomorrow(block)
            }
            presetRow("This weekend", symbol: "beach.umbrella", detail: weekendDetail) {
                if let date = weekendDate {
                    env.store.setDueDate(date, for: block)
                }
            }
            presetRow("Next week", symbol: "calendar", detail: shortWeekday(7)) {
                env.store.setDueNextWeek(block)
            }
        }
    }

    private func presetRow(_ title: String, symbol: String, detail: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            load()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(title) · \(detail)")
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
