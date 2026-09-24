import SwiftUI

/// A width-filling calendar with native buttons, explicit selection, and arrow
/// key navigation. Browsing months and moving focus never assign a due date.
struct CalendarMonthPicker: View {
    let selection: Date?
    let calendar: Calendar
    let onSelect: (Date) -> Void

    @Environment(\.nextStyle) private var style
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
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NX.ink)
                Spacer(minLength: 0)
                monthButton("Previous month", symbol: "chevron.left", by: -1)
                monthButton("Next month", symbol: "chevron.right", by: 1)
            }
            .padding(.bottom, 2)

            HStack(spacing: 2) {
                ForEach(0..<7) { index in
                    let weekday = (calendar.firstWeekday - 1 + index) % 7
                    // The design's calendar weekday: 600 10px, 0.04em, uppercase.
                    Text(calendar.shortStandaloneWeekdaySymbols[weekday])
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(NX.ink(0.45))
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
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

    private func monthButton(_ title: String, symbol: String, by amount: Int) -> some View {
        Button { shiftMonth(amount) } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .icon))
        .accessibilityLabel(title)
        .help(title)
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = selection.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
        let isToday = calendar.isDateInToday(day)
        let isInMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isHovered = hoveredDay == day
        return Button { onSelect(day) } label: {
            // The design's calendar day number: 500 weight, tabular, the accent for today.
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : isToday ? style.accent : isInMonth ? NX.ink : NX.ink(0.3))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? style.accent
                              : isToday ? style.accent.opacity(isHovered ? 0.16 : 0.1)
                              : isHovered ? NX.ink(0.06) : Color.clear)
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
