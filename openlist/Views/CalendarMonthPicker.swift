import SwiftUI

/// A width-filling calendar with native buttons, explicit selection, and arrow
/// key navigation. Browsing months and moving focus never assign a due date.
/// Days before `earliest`, when given, can't be picked.
struct CalendarMonthPicker: View {
    let selection: Date?
    let calendar: Calendar
    let earliest: Date?
    let onSelect: (Date) -> Void

    @Environment(\.nextStyle) private var style
    @State private var displayedMonth: Date
    @State private var hoveredDay: Date?
    @FocusState private var focusedDay: Date?

    init(selection: Date?, calendar: Calendar, earliest: Date? = nil, onSelect: @escaping (Date) -> Void) {
        self.selection = selection
        self.calendar = calendar
        self.earliest = earliest
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
                    // No month before the earliest day's.
                    .disabled(earliest.map { displayedMonth <= monthStart($0) } ?? false)
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
        let isTooEarly = CalendarMonthGrid.isBefore(day, earliest: earliest, calendar: calendar)
        let isHovered = hoveredDay == day && !isTooEarly
        return Button { onSelect(day) } label: {
            // The design's calendar day number: 500 weight, tabular, the accent for today.
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : isTooEarly ? NX.ink(0.2) : isToday ? style.accent
                                 : isInMonth ? NX.ink : NX.ink(0.3))
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
        .disabled(isTooEarly)
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
        // Stops at the earliest day, as the disabled days and months before it can't take focus.
        guard let date = CalendarMonthGrid.day(day, movedBy: amount, earliest: earliest, calendar: calendar) else { return .ignored }
        if !calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = monthStart(date)
        }
        focusedDay = date
        return .handled
    }
}

/// A date as a value pill, for a popover with no room to keep a month open:
/// it opens the month under its row, as its chevron shows.
struct NXDatePill: View {
    let label: String
    let date: Date
    let isOpen: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            NXValuePill(text: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                        isExpanded: isOpen, hovering: hovering)
        }
        .buttonStyle(NXBareButtonStyle())
        .onHover { hovering = $0 }
        .fixedSize()
        .accessibilityLabel(label)
        .accessibilityValue(date.formatted(date: .complete, time: .omitted))
        .accessibilityHint(isOpen ? "Hides the month" : "Shows a month to pick another day")
    }
}

/// A time of day as a value pill, like the hours editor's: every quarter
/// hour, and Custom… for any minute typed as HH:MM.
struct NXTimePill: View {
    let label: String
    /// Minutes after midnight.
    let minute: Int
    let onSelect: (Int) -> Void

    var body: some View {
        NXPopUpPill(value: NXHours.clock(minute), label: label, monospacedDigits: true,
                    custom: NXCustomValue(label: label, placeholder: "HH:MM", initial: NXHours.clock(minute),
                                          width: 58, monospaced: true) { text in
                        guard let typed = NXHours.minute(from: text), typed < 1440 else { return false }
                        onSelect(typed)
                        return true
                    },
                    entries: nxPresets(Array(stride(from: 0, to: 1440, by: 15)), including: minute).map { option in
                        .choice(NXHours.clock(option), isSelected: option == minute) { onSelect(option) }
                    })
    }
}
