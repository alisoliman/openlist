import SwiftUI

/// A width-filling calendar with native buttons, explicit selection, and arrow
/// key navigation. Browsing months and moving focus never assign a due date.
struct CalendarMonthPicker: View {
    let selection: Date?
    let calendar: Calendar
    let onSelect: (Date) -> Void

    @State private var displayedMonth: Date
    @State private var hoveredDay: Date?
    @FocusState private var focusedDay: Date?

    init(selection: Date?, calendar: Calendar, onSelect: @escaping (Date) -> Void) {
        self.selection = selection
        self.calendar = calendar
        self.onSelect = onSelect
        _displayedMonth = State(initialValue: calendar.dateInterval(of: .month, for: selection ?? .now)?.start ?? .now)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
                Button("Previous month", systemImage: "chevron.left") { shiftMonth(-1) }
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
                Button("Next month", systemImage: "chevron.right") { shiftMonth(1) }
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)

            HStack(spacing: 3) {
                ForEach(0..<7) { index in
                    let weekday = (calendar.firstWeekday - 1 + index) % 7
                    Text(calendar.shortStandaloneWeekdaySymbols[weekday])
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                ForEach(CalendarMonthGrid.days(in: displayedMonth, calendar: calendar), id: \.self) { day in
                    dayButton(day)
                }
            }
        }
        .onChange(of: selection) { _, date in
            if let date { displayedMonth = monthStart(date) }
        }
        .environment(\.calendar, calendar)
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = selection.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
        let isToday = calendar.isDateInToday(day)
        let isInMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        return Button { onSelect(day) } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 14, weight: isSelected || isToday ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : (isInMonth ? Color.primary : Theme.secondaryText))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background {
                    Circle().fill(isSelected ? Theme.accent : (hoveredDay == day ? Theme.rowHover : Color.clear))
                        .frame(width: 32, height: 32)
                }
                .overlay {
                    if isToday && !isSelected {
                        Circle().stroke(Theme.accent, lineWidth: 1)
                            .frame(width: 30, height: 30)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedDay, equals: day)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(isToday ? "Today" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Use arrow keys to move between dates, then Space to choose.")
        .onHover { hoveredDay = $0 ? day : nil }
        .help(day.formatted(date: .complete, time: .omitted))
        .onKeyPress(.leftArrow) { moveFocus(from: day, by: -1) }
        .onKeyPress(.rightArrow) { moveFocus(from: day, by: 1) }
        .onKeyPress(.upArrow) { moveFocus(from: day, by: -7) }
        .onKeyPress(.downArrow) { moveFocus(from: day, by: 7) }
    }

    private func monthStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func shiftMonth(_ amount: Int) {
        guard let month = calendar.date(byAdding: .month, value: amount, to: displayedMonth) else { return }
        displayedMonth = monthStart(month)
    }

    private func moveFocus(from day: Date, by amount: Int) -> KeyPress.Result {
        guard let date = calendar.date(byAdding: .day, value: amount, to: day) else { return .ignored }
        if !calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = monthStart(date)
        }
        focusedDay = date
        return .handled
    }
}
