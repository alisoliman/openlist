import SwiftData
import SwiftUI

/// Repeat-rule editor.
struct RecurrencePicker: View {
    let block: Block

    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                // The switch speaks for the row; its words toggle it too.
                HStack(spacing: 8) {
                    Image(systemName: "repeat")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(style.accent)
                    Text("Repeat this task")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(NX.ink)
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
                .onTapGesture { enabledBinding.wrappedValue.toggle() }
                .accessibilityHidden(true)
                NXToggle(isOn: isEnabled, label: "Repeat this task") { enabledBinding.wrappedValue.toggle() }
            }

            if isEnabled {
                section("Quick picks") { presets }

                section("Every") {
                    NXFlow(spacing: 4, alignment: .center) {
                        NXRepeatStepper(label: "Repeat interval", value: editing($interval), range: 1...52,
                                        spoken: "\(interval) \(interval == 1 ? frequency.singular : frequency.plural)") {
                            Text("\(interval)")
                        }
                        .padding(.trailing, 4)
                        ForEach(Recurrence.Frequency.allCases, id: \.self) { option in
                            pill(interval == 1 ? option.singular : option.plural, isOn: frequency == option) {
                                // Choosing the current value again saves nothing.
                                guard frequency != option else { return }
                                editing($frequency).wrappedValue = option
                            }
                        }
                    }
                }

                if frequency == .weekly {
                    section("On") { weekdayPicker }
                }

                section("Ends") { endCondition }

                section("Count from") {
                    NXFlow(spacing: 4) {
                        ForEach(Recurrence.Anchor.allCases, id: \.self) { option in
                            pill(option.title, isOn: anchor == option) {
                                guard anchor != option else { return }
                                editing($anchor).wrappedValue = option
                            }
                        }
                    }
                }

                if let rule = block.recurrence {
                    section("Next occurrences") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(RecurrenceEngine.upcoming(rule: rule, from: block.dueDate), id: \.self) { date in
                                Text(date.formatted(date: .complete, time: .omitted))
                                    .font(.system(size: 12))
                                    .foregroundStyle(NX.ink(0.62))
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NXCapsTitle(text: title)
            content()
        }
    }

    /// An inspector pill that says when it is the current choice.
    private func pill(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        NXInspectorPill(isOn: isOn, action: action) { Text(title) }
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private var endCondition: some View {
        VStack(alignment: .leading, spacing: 8) {
            NXFlow(spacing: 4) {
                ForEach(Ending.allCases) { option in
                    pill(option.title, isOn: ending == option) {
                        guard ending != option else { return }
                        editing($ending).wrappedValue = option
                    }
                }
            }

            switch ending {
            case .never:
                EmptyView()
            case .onDate:
                DatePicker("Repeat end date", selection: editing($endDate), displayedComponents: .date)
                    .labelsHidden()
                    .fixedSize()
            case .afterCount:
                NXRepeatStepper(label: "Occurrences", value: editing($occurrenceLimit), range: 1...365,
                                spoken: occurrenceLimit == 1 ? "1 time" : "\(occurrenceLimit) times") {
                    Text("\(occurrenceLimit) times")
                }
            }
        }
    }

    private var presets: some View {
        NXFlow(spacing: 4) {
            presetPill("Every day", rule: .daily)
            presetPill("Every weekday", rule: .weekdaysOnly)
            presetPill("Every week", rule: .weekly)
            presetPill("Every month", rule: .monthly)
            presetPill("Every year", rule: .yearly)
        }
    }

    private func presetPill(_ title: String, rule: Recurrence) -> some View {
        pill(title, isOn: block.recurrence?.displayText == rule.displayText) {
            env.store.setRecurrence(rule, for: block)
            load()
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 4) {
            ForEach(1...7, id: \.self) { day in
                NXInspectorPill(isOn: weekdays.contains(day)) {
                    if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                    apply()
                } label: {
                    Text(Recurrence.shortWeekdayName(day).prefix(2))
                        .frame(maxWidth: .infinity)
                }
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

/// The inspector's estimate stepper: grey minus and plus around the value,
/// one adjustable control to VoiceOver.
private struct NXRepeatStepper<Value: View>: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    /// The value with its unit, as VoiceOver reads it.
    let spoken: String
    @ViewBuilder var text: () -> Value

    var body: some View {
        HStack(spacing: 8) {
            step("minus", by: -1)
            text()
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(NX.ink)
                .contentTransition(.numericText())
                .fixedSize()
                .frame(minWidth: 18)
            step("plus", by: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(by: 1)
            case .decrement: change(by: -1)
            @unknown default: break
            }
        }
    }

    private func step(_ icon: String, by amount: Int) -> some View {
        NXStepButton(icon: icon) { change(by: amount) }
            .disabled(!range.contains(value + amount))
            .opacity(range.contains(value + amount) ? 1 : 0.45)
    }

    private func change(by amount: Int) {
        let next = min(range.upperBound, max(range.lowerBound, value + amount))
        if next != value { value = next }
    }
}
