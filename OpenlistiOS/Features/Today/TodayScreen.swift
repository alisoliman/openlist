//
//  TodayScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// Today (mockups 01, 02). The shell's stub: the Today feature replaces its
/// body with the day's tasks, the Now card and the empty state.
struct TodayScreen: View {
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let navigator = env.navigator
        OLScreen(identifier: PhoneRoute.today.screenIdentifier) {
            OLTopBar {
                OLEyebrow(OLFormat.eyebrowDate(env.now, calendar: env.settings.calendar))
            } trailing: {
                OLIconButton(icon: .calendar, label: "Show as timeline", kind: .bare, iconSize: 22) {
                    navigator.open(.timeline)
                }
            }
        } content: {
            OLHeader("Today")
            FeaturePlaceholder(summary: "Today’s tasks, the Now card and the empty state come with the Today feature.",
                               links: [
                                   .init("Timeline", symbol: "calendar", route: .timeline, navigator: navigator),
                                   .init("Working", symbol: "timer", route: .working, navigator: navigator),
                                   .init("Activity", symbol: "waveform.path.ecg", route: .activity, navigator: navigator),
                               ] + FeaturePlaceholder.firstTask(in: env))
        }
    }
}
