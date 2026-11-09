//
//  TodayScheduleCard.swift
//  OpenlistiOS
//

import SwiftUI

/// Today's Now card: what's under way, the work in hand first with its
/// Start, Resume or Working button, and what comes next today, meetings
/// included (`TodayNowNext`, read from the Mac's `TodaySchedule`). A
/// session's line opens its task and a long press gives its menu; a
/// meeting's long press shows its details. Under the lines, quiet notes: the
/// tasks for today with no time yet, which Fit gives a slot, and a calendar
/// to connect. On Today a chevron folds the card to its first line, what's
/// on now or next and when, and a tap on that line opens it again.
struct TodayScheduleCard: View {
    let schedule: TodaySchedule
    let work: PhoneWork
    let now: Date
    /// Today's tasks with no time yet, for Fit.
    var toPlan: [Block] = []
    /// The notes under the lines, and the card when it has no line: off on
    /// the Work tab, whose timeline plans the rest.
    var showsNotes = true
    /// The chevron that folds the card to one line, which stays folded
    /// across launches: Today's card has it; the Work tab's, whose timeline
    /// goes on from its lines, stays open.
    var folds = false
    @AppStorage(Self.foldedKey, store: ReviewSession.defaults) private var folded = false
    /// VoiceOver on the fold, where it goes once the folded line it was on
    /// opens and goes away.
    @AccessibilityFocusState private var onFold: Bool
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.olStyle) private var style
    @Environment(\.openURL) private var openURL

    /// Where Today keeps the card folded.
    static let foldedKey = "phone.today.scheduleFolded"

    var body: some View {
        let calendar = env.settings.calendar
        let store = env.store
        let model = TodayNowNext(schedule: schedule, work: work, now: now, calendar: calendar,
                                 task: { store.block(id: $0) }, list: { library.list($0)?.displayTitle })
        let connection = PhoneSchedule.connection(env.calendar.externalCalendars)
        let isFolded = folds && folded
        let notes = !isFolded && showsNotes && (!toPlan.isEmpty || connection != .connected)
        if showsNotes || !model.lines.isEmpty {
            OLNowCard {
                VStack(alignment: .leading, spacing: 0) {
                    // The top line, folded or not, with the fold beside it;
                    // one fades into the other as the card folds.
                    HStack(spacing: 0) {
                        ZStack(alignment: .leading) {
                            if isFolded {
                                summary(model)
                            } else if let first = model.lines.first {
                                // Its own, as the lines below are, so a new
                                // first line fades in for the last.
                                line(first).id(first.id)
                            } else if let empty = model.emptyText {
                                Text(empty)
                                    .font(OLFont.note)
                                    .foregroundStyle(OL.muted)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .accessibilityIdentifier("today.schedule.empty")
                                    .accessibilityActions { foldAction }
                            }
                        }
                        if folds {
                            OLNowCardFold(isFolded: isFolded) { fold(!isFolded) }
                                .accessibilityFocused($onFold)
                                // Into the card's margin, so the chevron
                                // sits near its edge with a full-size target.
                                .padding(.trailing, -14)
                                .accessibilityIdentifier("today.schedule.fold")
                        }
                    }
                    if !isFolded {
                        ForEach(model.lines.dropFirst()) { line in
                            self.line(line)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                if notes {
                    Rectangle().fill(OL.line).frame(height: 1).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        if !toPlan.isEmpty {
                            OLNowNote(toPlan.count == 1 ? "1 task has no time yet" : "\(toPlan.count) tasks have no time yet",
                                      actionTitle: "Fit", identifier: "today.fit") { env.actions.fit(toPlan) }
                                .accessibilityHint(toPlan.count == 1 ? "Finds it a free slot today" : "Finds each a free slot today")
                        }
                        switch connection {
                        case .connected:
                            EmptyView()
                        case .notConnected:
                            OLNowNote("No calendar connected", actionTitle: "Connect", identifier: "today.connect") {
                                PhoneSchedule.connect(env)
                            }
                            .accessibilityHint("Shows your meetings here, and plans around them")
                        case .unavailable:
                            OLNowNote("Calendar access is off", actionTitle: "Settings", identifier: "today.connect") {
                                PhoneSchedule.connect(env)
                            }
                            .accessibilityHint("Opens Settings, where Openlist can be allowed your calendars")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
            .animation(style.animation(.snappy(duration: 0.25)), value: model.lines.map(\.id))
            .olFeedback(.selection, trigger: isFolded)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.schedule")
        }
    }

    /// The card folded to its first line: what's on now or next and when,
    /// or that nothing is. A tap opens the card again.
    private func summary(_ model: TodayNowNext) -> some View {
        let first = model.lines.first
        let empty = model.emptyText ?? ""
        return Button {
            fold(false)
            onFold = true
        } label: {
            OLNowCardSummary(role: first?.role, title: first?.title ?? empty, time: first?.brief)
                .contentShape(.rect)
        }
        .buttonStyle(OLRowPressStyle())
        .accessibilityLabel(first.map { "\($0.role.label): \($0.title)" } ?? empty)
        .accessibilityValue(first?.brief ?? "")
        .accessibilityHint("Shows the whole schedule")
        .accessibilityIdentifier("today.schedule.summary")
    }

    /// Folds the card or opens it, the page below moving up or down with it.
    private func fold(_ isFolded: Bool) {
        withAnimation(style.animation(.snappy(duration: 0.3))) { folded = isFolded }
    }

    /// A line's VoiceOver action that folds the card, where it folds.
    @ViewBuilder private var foldAction: some View {
        if folds {
            Button("Collapse schedule") { fold(true) }
        }
    }

    @ViewBuilder private func line(_ line: TodayNowNext.Line) -> some View {
        let id = "today.schedule.\(line.role == .next ? "next" : "now")"
        let color = line.listID.flatMap { library.list($0) }?.accent.color
        let drawn = OLNowCardLine(role: line.role, title: line.title, detail: line.detail, listColor: color)
        switch line.kind {
        case let .work(state):
            HStack(spacing: 10) {
                Button { env.navigator.open(.working) } label: { drawn }
                    .buttonStyle(OLRowPressStyle())
                    .accessibilityHint("Opens Working")
                    .accessibilityActions { foldAction }
                    .accessibilityIdentifier(id)
                OLIconButton(state == .working ? "timer" : "play.fill",
                             label: state == .working ? "Open Working" : state == .paused ? "Resume" : "Start working",
                             kind: .accent, iconSize: 16) { work.play(env) }
            }
        case .session:
            let task = line.taskID.flatMap { env.store.block(id: $0) }
            Button { if let id = line.taskID { env.navigator.open(.taskDetail(id)) } } label: { drawn }
                .buttonStyle(OLRowPressStyle())
                .contextMenu { if let task { PhoneTaskMenu(task: task) } }
                .accessibilityHint("Opens the task")
                .accessibilityActions { foldAction }
                .accessibilityIdentifier(id)
        case .meeting:
            if let meeting = line.meeting {
                drawn
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contextMenu {
                        Button("Show in Timeline", systemImage: "calendar.day.timeline.left") {
                            env.navigator.openTimeline(on: nil)
                        }
                        Button("Open in Calendar", systemImage: "calendar") { openCalendar(at: meeting.start) }
                    } preview: {
                        OLMeetingDetails(title: meeting.title, start: meeting.start, end: meeting.end,
                                         location: meeting.place, calendarTitle: meeting.calendarTitle, now: now,
                                         calendar: env.settings.calendar)
                    }
                    .accessibilityValue([line.detail, meeting.calendarTitle.map { "\($0) calendar" }]
                        .compactMap(\.self).joined(separator: ", "))
                    .accessibilityAction(named: "Show in Timeline") { env.navigator.openTimeline(on: nil) }
                    .accessibilityActions { foldAction }
                    .accessibilityIdentifier(id)
            }
        }
    }

    private func openCalendar(at date: Date) {
        if let url = PhoneSchedule.calendarApp(at: date) { openURL(url) }
    }
}
