import SwiftUI

/// Browsing changes only the viewport. All scales share the coordinator's plan.
struct CalendarScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var scaleSelection
    @AppStorage("calendar.viewSpan", store: ReviewSession.defaults) private var span: CalendarSpan = .threeDays
    @State private var date = Date.now
    @State private var showsDateNavigator = false
    @State private var showsSettings = false
    @State private var showsHistory = false
    @State private var showsCoverage = false
    @AppStorage("calendar.hourHeight", store: ReviewSession.defaults) private var savedHourHeight: Double = 88
    @State private var scrollRequest = 0
    @State private var scrollTarget: Date?
    private var hourHeight: CGFloat {
        get { [64.0, 88.0, 112.0].contains(savedHourHeight) ? CGFloat(savedHourHeight) : 88 }
        nonmutating set { savedHourHeight = Double(newValue) }
    }
    private var calendar: Calendar {
        var value = Calendar.current
        if env.settings.firstWeekday != 0 { value.firstWeekday = env.settings.firstWeekday }
        return value
    }
    private var firstDay: Date {
        span == .week ? calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date) : calendar.startOfDay(for: date)
    }
    private var dates: [Date] {
        (0..<span.days).compactMap { calendar.date(byAdding: .day, value: $0, to: firstDay) }
    }
    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.28) }
    private var title: String {
        if span == .month { return date.formatted(.dateTime.month(.wide).year()) }
        if span == .day {
            return calendar.isDate(date, equalTo: .now, toGranularity: .year)
                ? date.formatted(.dateTime.month(.wide).day())
                : date.formatted(.dateTime.month(.wide).day().year())
        }
        let last = dates.last ?? date
        if !calendar.isDate(firstDay, equalTo: last, toGranularity: .year) {
            return "\(firstDay.formatted(.dateTime.month(.abbreviated).day().year())) – \(last.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
        let isCurrentYear = calendar.isDate(firstDay, equalTo: .now, toGranularity: .year)
        if calendar.isDate(firstDay, equalTo: last, toGranularity: .month) {
            let range = "\(firstDay.formatted(.dateTime.month(.wide).day()))–\(last.formatted(.dateTime.day()))"
            return isCurrentYear ? range : "\(range), \(last.formatted(.dateTime.year()))"
        }
        let ending = isCurrentYear ? last.formatted(.dateTime.month(.abbreviated).day()) : last.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(firstDay.formatted(.dateTime.month(.abbreviated).day())) – \(ending)"
    }

    private var riskCount: Int { env.calendar.plan.assessments.filter { $0.status == .cannotFitBeforeDeadline || !$0.conflicts.isEmpty }.count }
    private var outsideCount: Int { env.calendar.plan.assessments.filter { $0.status == .outsidePlanningHorizon }.count }
    private var coverageTitle: String {
        if riskCount > 0 { return "\(riskCount) need attention" }
        if outsideCount > 0 { return "\(outsideCount) outside plan" }
        return env.calendar.plan.assessments.isEmpty ? "Build your plan" : "Deadlines on track"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if span == .month {
                monthGrid
            } else {
                CalendarTimeGrid(dates: dates, calendar: calendar, hourHeight: hourHeight,
                                 scrollRequest: scrollRequest, scrollTarget: scrollTarget,
                                 onOpenDay: openDay)
            }
            Divider()
            footer
        }
        .background(Theme.canvas)
        .onAppear { env.calendar.storeDidChange() }
        .sheet(isPresented: $showsSettings) { CalendarSettingsSheet() }
        .sheet(isPresented: $showsHistory) { CalendarHistoryView() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondaryText)
                    Button { showsDateNavigator.toggle() } label: {
                        HStack(spacing: 7) {
                            Text(title).font(.system(size: 23, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                                .contentTransition(.numericText())
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.secondaryText)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Choose date, \(title)")
                    .help("Jump to a date")
                    .popover(isPresented: $showsDateNavigator, arrowEdge: .bottom) {
                        CalendarDateNavigator(selection: date, calendar: calendar) { day in
                            showsDateNavigator = false
                            navigate(to: day)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    navigationButton("chevron.left", title: "Previous calendar period", key: .leftArrow) { advance(-1) }
                    navigationButton("chevron.right", title: "Next calendar period", key: .rightArrow) { advance(1) }
                }.padding(3).background(Theme.chipFill, in: Capsule())
                Button(action: jumpToNow) {
                    Label("Now", systemImage: "location.fill").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 3).frame(height: 27)
                }
                .buttonStyle(.glassProminent).buttonBorderShape(.capsule).tint(Theme.accent)
                .keyboardShortcut("0", modifiers: .command)
                .help("Go to the current day and time (⌘0)")
                .accessibilityLabel("Go to current time").accessibilityInputLabels(["Now", "Go to current time"])
                Menu {
                    Button("Add task", systemImage: "plus") { env.send(.newTask) }
                    Divider()
                    Button("Work history", systemImage: "clock.arrow.circlepath") { showsHistory = true }
                    Button("Calendar settings", systemImage: "slider.horizontal.3") { showsSettings = true }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Calendar options")
            }
            HStack(spacing: 12) {
                scalePicker
                Spacer(minLength: 0)
                Button { showsCoverage.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: riskCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle")
                        Text(coverageTitle).lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(riskCount > 0 ? ListAccent.orange.color : Theme.secondaryText)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain).help("Review scheduled time and deadline coverage")
                .accessibilityLabel("Deadline coverage, \(coverageTitle)")
                .popover(isPresented: $showsCoverage, arrowEdge: .bottom) {
                    CalendarCoverageView().frame(width: 420, height: 420)
                }
            }
            if env.calendar.plan.assessments.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus").foregroundStyle(Theme.accent)
                    Text("Select tasks for today or add a due date. Openlist finds the time.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 0)
                    Button("Add task") { env.send(.newTask) }.font(.caption)
                }
            }
            if let error = env.calendar.externalCalendars.error {
                Label(error, systemImage: "calendar.badge.exclamationmark")
                    .font(.caption).foregroundStyle(ListAccent.orange.color)
            }
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 16)
        .background(Theme.chrome.opacity(0.35))
    }

    private func navigationButton(_ symbol: String, title: String, key: KeyEquivalent, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 27, height: 25) }
            .buttonStyle(.plain).accessibilityLabel(title).help(title + " (⌥⌘ arrow)")
            .keyboardShortcut(key, modifiers: [.command, .option])
    }
    private var scalePicker: some View {
        HStack(spacing: 2) {
            ForEach(CalendarSpan.allCases) { item in
                Button {
                    withAnimation(motion) { span = item }
                } label: {
                    Text(item.rawValue).font(.system(size: 11, weight: span == item ? .semibold : .medium))
                        .foregroundStyle(span == item ? Color.primary : Theme.secondaryText)
                        .frame(width: 60, height: 27)
                        .background {
                            if span == item {
                                RoundedRectangle(cornerRadius: 7).fill(Theme.canvas)
                                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "calendar-scale", in: scaleSelection)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityAddTraits(span == item ? [.isSelected] : [])
                .accessibilityLabel(item.rawValue + " calendar view")
            }
        }.padding(3).background(Theme.chipFill, in: RoundedRectangle(cornerRadius: 10))
    }
    private var footer: some View {
        HStack(spacing: 13) {
            Label("Work", systemImage: "circle.fill").foregroundStyle(ListAccent.blue.color)
            Label("Personal", systemImage: "circle.fill").foregroundStyle(ListAccent.green.color)
            Label("Busy", systemImage: "lock.fill").foregroundStyle(Theme.secondaryText)
            Label("Completed", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 4)
            Text("Plan through \(env.calendar.plan.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))")
                .foregroundStyle(Theme.secondaryText).lineLimit(1)
            if span != .month {
                CalendarZoomMenu(selection: hourHeight) { value in
                    hourHeight = value
                }
            }
        }
        .font(.system(size: 10, weight: .medium)).padding(.horizontal, 22).frame(height: 34)
        .background(Theme.chrome.opacity(0.4))
    }
    private func advance(_ direction: Int) {
        let next = calendar.date(byAdding: span == .month ? .month : .day, value: direction * (span == .month ? 1 : span.days), to: date) ?? date
        withAnimation(motion) { date = next }
    }
    private func navigate(to day: Date) {
        withAnimation(motion) { date = day }
        if span != .month { reveal(day) }
    }
    private func openDay(_ day: Date) {
        withAnimation(motion) { date = day; span = .day }
        reveal(day)
    }
    private func reveal(_ day: Date) {
        scrollTarget = calendar.isDateInToday(day) ? .now : env.calendar.visibleBlocks.first(where: { calendar.isDate($0.start, inSameDayAs: day) })?.start ?? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
        scrollRequest += 1
    }
    private func jumpToNow() {
        withAnimation(motion) { date = .now; if span == .month { span = .day } }
        scrollTarget = .now
        scrollRequest += 1
    }
    private var monthGrid: some View {
        GeometryReader { geometry in
            let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? date
            let offset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
            let gridStart = calendar.date(byAdding: .day, value: -offset, to: monthStart) ?? monthStart
            let days = (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                    ForEach(0..<7) { index in
                        Text(calendar.shortWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondaryText)
                            .frame(maxWidth: .infinity).frame(height: 32)
                    }
                    ForEach(days, id: \.self) { day in
                        CalendarMonthCell(day: day, calendar: calendar,
                                          belongsToMonth: calendar.isDate(day, equalTo: date, toGranularity: .month),
                                          height: max(112, (geometry.size.height - 40) / 6), onOpenDay: { openDay(day) })
                    }
                }.padding(8)
            }
        }
    }
}
