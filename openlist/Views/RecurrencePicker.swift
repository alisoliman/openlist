import SwiftData
import SwiftUI

/// Repeat-rule editor.
struct RecurrencePicker: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env

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
        // SwiftUI may update this child after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { liveContent }
    }

    private var liveContent: some View {
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
