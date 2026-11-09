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
/// to connect.
struct TodayScheduleCard: View {
    let schedule: TodaySchedule
    let work: PhoneWork
    let now: Date
    /// Today's tasks with no time yet, for Fit.
    var toPlan: [Block] = []
    /// The notes under the lines, and the card when it has no line: off on
    /// the Work tab, whose timeline plans the rest.
    var showsNotes = true
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.olStyle) private var style
    @Environment(\.openURL) private var openURL

    var body: some View {
        let calendar = env.settings.calendar
        let store = env.store
        let model = TodayNowNext(schedule: schedule, work: work, now: now, calendar: calendar,
                                 task: { store.block(id: $0) }, list: { library.list($0)?.displayTitle })
        let connection = PhoneSchedule.connection(env.calendar.externalCalendars)
        let notes = showsNotes && (!toPlan.isEmpty || connection != .connected)
        if showsNotes || !model.lines.isEmpty {
            OLNowCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.lines) { line in
                        self.line(line)
                    }
                    if let empty = model.emptyText {
                        Text(empty)
                            .font(OLFont.note)
                            .foregroundStyle(OL.muted)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .accessibilityIdentifier("today.schedule.empty")
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
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.schedule")
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
                                         location: meeting.location, calendarTitle: meeting.calendarTitle, now: now,
                                         calendar: env.settings.calendar)
                    }
                    .accessibilityValue([line.detail, meeting.calendarTitle.map { "\($0) calendar" }]
                        .compactMap(\.self).joined(separator: ", "))
                    .accessibilityAction(named: "Show in Timeline") { env.navigator.openTimeline(on: nil) }
                    .accessibilityIdentifier(id)
            }
        }
    }

    private func openCalendar(at date: Date) {
        if let url = PhoneSchedule.calendarApp(at: date) { openURL(url) }
    }
}
