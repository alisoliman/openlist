//
//  DueDatePicker.swift
//  openlist
//

import AppKit
import SwiftUI
import UserNotifications

/// Quick presets plus a calendar and optional time, matching how Superlist
/// lets you type or tap a due date.
struct DueDatePicker: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

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

            DatePicker("Due date", selection: dateBinding, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(width: 260)

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
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(Theme.Font.body)
                .foregroundStyle(ListAccent.red.color)
            }
        }
        .padding(14)
        .frame(width: 288)
        .onAppear(perform: load)
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
        dismiss()
    }

    // MARK: - Presets

    private var presets: some View {
        VStack(spacing: 2) {
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
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 16)
                Text(title)
                    .font(Theme.Font.body)
                Spacer()
                Text(detail)
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    private var dateBinding: Binding<Date> {
        Binding(get: { selectedDate }, set: { selectedDate = $0; apply() })
    }

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

/// Repeat-rule editor.
struct RecurrencePicker: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var isEnabled = false
    @State private var frequency: Recurrence.Frequency = .weekly
    @State private var interval = 1
    @State private var weekdays: Set<Int> = []
    @State private var anchor: Recurrence.Anchor = .dueDate
    @State private var ending: Ending = .never
    @State private var endDate: Date = .now
    @State private var occurrenceLimit = 10

    /// How a repeat series stops. The model and engine already honour both an
    /// end date and an occurrence count; this is the missing way to set them.
    private enum Ending: String, CaseIterable, Identifiable {
        case never, onDate, afterCount
        var id: String { rawValue }
        var title: String {
            switch self {
            case .never: "Never"
            case .onDate: "On date"
            case .afterCount: "After"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Repeat this task", isOn: enabledBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(Theme.Font.body)

            if isEnabled {
                Divider()
                presets

                Divider()

                HStack(spacing: 6) {
                    Text("Every")
                        .font(Theme.Font.body)

                    Stepper(value: editing($interval), in: 1...52) {
                        Text("\(interval)")
                            .font(Theme.Font.body)
                            .monospacedDigit()
                            .frame(minWidth: 18)
                    }

                    Picker("Repeat frequency", selection: editing($frequency)) {
                        ForEach(Recurrence.Frequency.allCases, id: \.self) { option in
                            Text(interval == 1 ? option.singular : option.plural).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 96)
                }

                if frequency == .weekly {
                    weekdayPicker
                }

                Divider()
                endCondition

                Picker("Count from", selection: editing($anchor)) {
                    ForEach(Recurrence.Anchor.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
                .font(Theme.Font.body)

                if let rule = block.recurrence {
                    Divider()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Next occurrences")
                            .font(Theme.Font.sectionHeader)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.tertiaryText)

                        ForEach(RecurrenceEngine.upcoming(rule: rule, from: block.dueDate), id: \.self) { date in
                            Text(date.formatted(date: .complete, time: .omitted))
                                .font(Theme.Font.metadata)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear(perform: load)
    }

    @ViewBuilder
    private var endCondition: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Ends", selection: editing($ending)) {
                ForEach(Ending.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch ending {
            case .never:
                EmptyView()
            case .onDate:
                DatePicker("Repeat end date", selection: editing($endDate), displayedComponents: .date)
                    .labelsHidden()
            case .afterCount:
                Stepper(value: editing($occurrenceLimit), in: 1...365) {
                    Text("\(occurrenceLimit) times")
                        .font(Theme.Font.body)
                        .monospacedDigit()
                }
            }
        }
    }

    private var presets: some View {
        VStack(spacing: 2) {
            presetRow("Every day", rule: .daily)
            presetRow("Every weekday", rule: .weekdaysOnly)
            presetRow("Every week", rule: .weekly)
            presetRow("Every month", rule: .monthly)
            presetRow("Every year", rule: .yearly)
        }
    }

    private func presetRow(_ title: String, rule: Recurrence) -> some View {
        Button {
            env.store.setRecurrence(rule, for: block)
            load()
        } label: {
            HStack {
                Text(title)
                    .font(Theme.Font.body)
                Spacer()
                if block.recurrence?.displayText == rule.displayText {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekdayPicker: some View {
        HStack(spacing: 3) {
            ForEach(1...7, id: \.self) { day in
                Button {
                    if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                    apply()
                } label: {
                    Text(Recurrence.shortWeekdayName(day).prefix(2))
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 30, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(weekdays.contains(day) ? Theme.accent : Theme.chipFill)
                        )
                        .foregroundStyle(weekdays.contains(day) ? Color.white : Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Recurrence.shortWeekdayName(day))
                .accessibilityValue(weekdays.contains(day) ? "Selected" : "Not selected")
            }
        }
    }

    private func load() {
        if let rule = block.recurrence {
            isEnabled = true
            frequency = rule.frequency
            interval = rule.interval
            weekdays = rule.weekdays
            anchor = rule.anchor
            if let end = rule.endDate {
                ending = .onDate
                endDate = end
            } else if let limit = rule.occurrenceLimit {
                ending = .afterCount
                occurrenceLimit = limit
            } else {
                ending = .never
            }
        } else {
            isEnabled = false
            frequency = .weekly
            interval = 1
            weekdays = []
            anchor = .dueDate
            ending = .never
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { isEnabled }, set: { enabled in
            isEnabled = enabled
            if enabled { apply() } else { env.store.setRecurrence(nil, for: block) }
        })
    }

    private func editing<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(get: { binding.wrappedValue }, set: { value in
            binding.wrappedValue = value
            apply()
        })
    }

    private func apply() {
        guard isEnabled else { return }
        // Start from the stored rule so fields this form does not expose —
        // day-of-month, end date, occurrence limit and the count so far —
        // survive an edit.
        var rule = block.recurrence ?? Recurrence(frequency: frequency, interval: interval)
        rule.frequency = frequency
        rule.interval = interval
        rule.weekdays = frequency == .weekly ? weekdays : []
        rule.anchor = anchor

        switch ending {
        case .never:
            rule.endDate = nil
            rule.occurrenceLimit = nil
        case .onDate:
            rule.endDate = Calendar.current.startOfDay(for: endDate).addingTimeInterval(86_399)
            rule.occurrenceLimit = nil
        case .afterCount:
            rule.endDate = nil
            rule.occurrenceLimit = occurrenceLimit
        }
        env.store.setRecurrence(rule, for: block)
    }
}

/// Reminder time editor, offering offsets relative to the due date.
struct ReminderPicker: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var customDate: Date = .now
    @State private var authorizationDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if block.dueDate != nil {
                VStack(spacing: 2) {
                    offsetRow("At the due time", minutes: 0)
                    offsetRow("10 minutes before", minutes: -10)
                    offsetRow("1 hour before", minutes: -60)
                    offsetRow("1 day before", minutes: -1_440)
                }
                Divider()
            } else {
                Text("Add a due date to use relative reminders.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.tertiaryText)
            }

            DatePicker("Remind me at", selection: $customDate)
                .font(Theme.Font.body)
                .datePickerStyle(.compact)

            Button("Set reminder") {
                env.store.setReminder(customDate, for: block)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            if block.reminderAt != nil {
                Button("Remove reminder") {
                    env.store.setReminder(nil, for: block)
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(Theme.Font.metadata)
                .foregroundStyle(ListAccent.red.color)
            }

            if authorizationDenied {
                Text("Notifications are turned off for Openlist. Enable them in System Settings to get reminders.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(ListAccent.orange.color)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Notification Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(Theme.Font.metadata)
            }
        }
        .padding(14)
        .frame(width: 268)
        .onAppear {
            customDate = block.reminderAt ?? block.dueDate ?? .now
            Task {
                let status = await NotificationService.shared.authorizationStatus()
                authorizationDenied = status == .denied
            }
        }
    }

    private func offsetRow(_ title: String, minutes: Int) -> some View {
        Button {
            guard let dueDate = block.dueDate else { return }
            let base = block.includesTime
                ? dueDate
                : Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: dueDate) ?? dueDate
            env.store.setReminder(base.addingTimeInterval(TimeInterval(minutes * 60)), for: block)
            dismiss()
        } label: {
            HStack {
                Text(title)
                    .font(Theme.Font.body)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Attach existing labels or create a new one inline.
struct LabelPicker: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Find or create a label", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Font.body)
                .onSubmit(createFromQuery)

            let matches = filteredLabels
            if !matches.isEmpty {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(matches) { label in
                            Button {
                                env.store.toggleLabel(label, on: block)
                            } label: {
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(label.accent.color)
                                        .frame(width: 8, height: 8)
                                    Text(label.name)
                                        .font(Theme.Font.body)
                                    Spacer()
                                    if block.labelIDs.contains(label.id) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            if canCreate {
                Button {
                    createFromQuery()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11))
                        Text("Create “\(TaskLabel.normalize(query))”")
                            .font(Theme.Font.body)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if filteredLabels.isEmpty, !canCreate {
                Text("No labels yet. Type a name to create one.")
                    .font(Theme.Font.metadata)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    private var filteredLabels: [TaskLabel] {
        let needle = TaskLabel.normalize(query).lowercased()
        let all = env.store.allLabels()
        guard !needle.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(needle) }
    }

    private var canCreate: Bool {
        let name = TaskLabel.normalize(query)
        guard !name.isEmpty else { return false }
        return !env.store.allLabels().contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func createFromQuery() {
        guard let label = env.store.findOrCreateLabel(named: query) else { return }
        env.store.addLabel(label, to: block)
        query = ""
    }
}
