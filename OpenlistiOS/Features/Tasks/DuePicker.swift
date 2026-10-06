//
//  DuePicker.swift
//  OpenlistiOS
//

import SwiftUI

/// The quick days a task can be moved to: Triage's When chips and the date
/// picker's shortcuts.
enum PhoneDay: CaseIterable, Identifiable {
    case today, tomorrow, weekend, nextWeek

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .weekend: "This weekend"
        case .nextWeek: "Next week"
        }
    }

    /// The day it names from `now`: the weekend is the coming Saturday, or
    /// today on a weekend; next week its first day.
    func date(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        func add(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: today) ?? today }
        switch self {
        case .today: return today
        case .tomorrow: return add(1)
        case .weekend:
            let weekday = calendar.component(.weekday, from: today)
            return weekday == 1 || weekday == 7 ? today : add(7 - weekday)
        case .nextWeek:
            let week = OLWeekStrip.week(containing: today, calendar: calendar)
            return week.first.flatMap { calendar.date(byAdding: .day, value: 7, to: $0) } ?? add(7)
        }
    }
}

/// A due date, when the chips don't have it: the month, a time if it has one,
/// and Clear. Set hands back the date and whether it has a time.
struct DuePickerSheet: View {
    let title: String
    let onSet: (_ date: Date?, _ includesTime: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appClock) private var clock
    @Environment(\.calendar) private var calendar
    @State private var date: Date
    @State private var includesTime: Bool
    /// Clear is offered: the task has a date and the caller can take nil.
    private let clears: Bool

    init(title: String = "Due date", date: Date?, includesTime: Bool, now: Date, clears: Bool = true,
         onSet: @escaping (_ date: Date?, _ includesTime: Bool) -> Void) {
        self.title = title
        self.onSet = onSet
        self.clears = clears && date != nil
        _date = State(initialValue: date ?? now)
        _includesTime = State(initialValue: date != nil && includesTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OLSheetHeader(confirmTitle: "Set", cancel: { dismiss() }) {
                onSet(includesTime ? date : calendar.startOfDay(for: date), includesTime)
                dismiss()
            }
            Text(title).font(OLFont.groupHeader).foregroundStyle(OL.muted).padding(.top, 6)
            OLFlowLayout {
                ForEach(PhoneDay.allCases) { day in
                    OLChipButton(OLChip(day.title, small: true)) { pick(day.date(now: clock.now, calendar: calendar)) }
                }
            }
            .padding(.top, 10)
            DatePicker("Day", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(OL.accent)
                .padding(.top, 6)
                .accessibilityIdentifier("duePicker.day")
            VStack(spacing: 0) {
                OLSettingsRow("At a time") {
                    Toggle("At a time", isOn: $includesTime).labelsHidden().olToggle()
                        .accessibilityIdentifier("duePicker.includesTime")
                }
                if includesTime {
                    OLSettingsRow("Time", separator: .inset(16)) {
                        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute).labelsHidden()
                            .accessibilityIdentifier("duePicker.time")
                    }
                }
            }
            .olCard()
            if clears {
                Button("Clear date") {
                    onSet(nil, false)
                    dismiss()
                }
                .buttonStyle(.olLink())
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, OLMetrics.gutter)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .presentationDetents([.large])
        .olSheet()
    }

    private func pick(_ day: Date) {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        date = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }
}

/// A row's due date as a menu, Task detail's When choices for the day: a
/// quick day, the date picker or Clear, so a task moves without opening it.
struct PhoneDueMenu: View {
    let task: Block
    /// The row's date as it reads, which the menu draws in its place.
    let trailing: OLTrailing
    @Environment(PhoneEnvironment.self) private var env
    @State private var picksDate = false
    /// The picker's choice, saved once its sheet has gone: a cleared or moved
    /// date can take this menu off the row, which mustn't happen under a
    /// sheet still closing.
    @State private var picked: (date: Date?, includesTime: Bool)?

    var body: some View {
        let actions = env.actions
        let now = env.now
        let calendar = env.settings.calendar
        Menu {
            Button("Due date…", systemImage: "calendar") { picksDate = true }
            ForEach([PhoneDay.today, .tomorrow, .nextWeek]) { day in
                Button(day.title) { actions.schedule([task], on: day.date(now: now, calendar: calendar)) }
            }
            Button("Clear due date", systemImage: "xmark", role: .destructive) { actions.schedule([task], on: nil) }
        } label: {
            // A 44 pt target around the date, as the row asks of its control.
            OLTrailingView(trailing)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(OLRowPressStyle())
        .accessibilityLabel("Due date")
        .accessibilityValue(trailing.accessibilityLabel ?? trailing.text ?? "")
        .accessibilityHint("Changes when \(task.displayTitle) is due")
        .accessibilityIdentifier("task.due.\(task.displayTitle)")
        .sheet(isPresented: $picksDate) {
            guard let picked else { return }
            self.picked = nil
            actions.schedule([task], on: picked.date, includesTime: picked.includesTime)
        } content: {
            DuePickerSheet(date: task.dueDate, includesTime: task.includesTime, now: now) { picked = ($0, $1) }
        }
    }
}
