//
//  TimelineScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// Today as a timeline (mockup 03), in Today's place. The shell's stub: the
/// Today feature draws the day's plan on the timeline card.
struct TimelineScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @State private var day: Date?

    var body: some View {
        let navigator = env.navigator
        let calendar = env.settings.calendar
        let selected = day ?? calendar.startOfDay(for: env.now)
        OLScreen(identifier: PhoneRoute.timeline.screenIdentifier) {
            OLTopBar {
                OLEyebrow(OLFormat.eyebrowDate(env.now, calendar: calendar))
            } trailing: {
                OLIconButton("list.bullet", label: "Show as list", kind: .bare, iconSize: 22) {
                    navigator.open(.today)
                }
            }
        } content: {
            OLHeader("Today")
            OLWeekStrip(days: OLWeekStrip.week(containing: env.now, calendar: calendar),
                        selection: Binding(get: { selected }, set: { day = $0 }), today: env.now, calendar: calendar)
                .padding(.top, 14)
            OLGroup("Schedule") {
                OLTimeline(items: [], now: env.now, calendar: calendar)
                    .olCard()
            }
        }
    }
}
