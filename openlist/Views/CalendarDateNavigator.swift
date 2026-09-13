import SwiftUI

/// Compact date navigation for a calendar popover. Selecting a day reports the
/// local start of that day; the caller owns navigation and popover dismissal.
struct CalendarDateNavigator: View {
    let selection: Date
    let calendar: Calendar
    let onSelect: (Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedMonth: Date
    @State private var jumpDate: Date
    @State private var hoveredDay: Date?

    init(selection: Date, calendar: Calendar, onSelect: @escaping (Date) -> Void) {
        self.selection = selection
        self.calendar = calendar
        self.onSelect = onSelect
        _displayedMonth = State(initialValue: calendar.dateInterval(of: .month, for: selection)?.start ?? selection)
        _jumpDate = State(initialValue: selection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            monthHeading
            calendarGrid
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("Jump to date")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                HStack(spacing: 8) {
                    DatePicker("Jump to date", selection: $jumpDate, displayedComponents: .date)
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .accessibilityLabel("Jump to date")
                        .frame(width: 130)
                    Button("Go") { choose(jumpDate) }
                        .keyboardShortcut(.defaultAction)
                        .help("Show the entered date")
                    Spacer(minLength: 0)
                    Button("Today") { choose(.now) }
                        .help(Date.now.formatted(date: .complete, time: .omitted))
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 300)
        .environment(\.calendar, calendar)
        .onChange(of: jumpDate) { _, value in
            displayedMonth = monthStart(value)
        }
        .onChange(of: selection) { _, value in
            displayedMonth = monthStart(value)
            jumpDate = value
        }
    }

    private var monthHeading: some View {
        HStack(spacing: 8) {
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 16, height: 18)
            }
            .accessibilityLabel("Previous month")
            .help("Previous month")
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right").frame(width: 16, height: 18)
            }
            .accessibilityLabel("Next month")
            .help("Next month")
        }
        .buttonStyle(.borderless)
    }

    private var calendarGrid: some View {
        VStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(0..<7) { index in
                    let weekday = (calendar.firstWeekday - 1 + index) % 7
                    Text(calendar.shortStandaloneWeekdaySymbols[weekday])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 3)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                ForEach(monthDays, id: \.self) { day in
                    dayButton(day)
                }
            }
        }
    }

    private var monthDays: [Date] {
        let offset = (calendar.component(.weekday, from: displayedMonth) - calendar.firstWeekday + 7) % 7
        guard let first = calendar.date(byAdding: .day, value: -offset, to: displayedMonth) else { return [] }
        // Six fixed rows keep the popover size steady while browsing months.
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        let isInMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isHovered = hoveredDay == day
        return Button { choose(day) } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 12, weight: isSelected || isToday ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : (isInMonth ? Color.primary : Theme.tertiaryText))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    Circle()
                        .fill(isSelected ? Theme.accent : (isHovered ? Theme.rowHover : Color.clear))
                        .frame(width: 30, height: 30)
                }
                .overlay {
                    if isToday, !isSelected {
                        Circle().stroke(Theme.accent.opacity(0.6), lineWidth: 1)
                            .frame(width: 29, height: 29)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(isToday ? "Today" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { value in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                if value { hoveredDay = day }
                else if hoveredDay == day { hoveredDay = nil }
            }
        }
    }

    private func monthStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func shiftMonth(_ amount: Int) {
        if let date = calendar.date(byAdding: .month, value: amount, to: displayedMonth) {
            displayedMonth = monthStart(date)
            hoveredDay = nil
        }
    }

    private func choose(_ date: Date) {
        onSelect(calendar.startOfDay(for: date))
    }
}
