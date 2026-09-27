//
//  ActivityScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// Activity (mockup 14), pushed from Today or Settings. The shell's stub: the
/// Activity feature adds the heatmap, the day's completions and Recent changes.
struct ActivityScreen: View {
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let navigator = env.navigator
        OLScreen(identifier: PhoneRoute.activity.screenIdentifier) {
            OLTopBar { OLBackButton(env.backTitle(for: .activity)) { navigator.pop() } }
        } content: {
            OLHeader("Activity")
            FeaturePlaceholder(summary: "The heatmap and recent changes come with the Activity feature.")
        }
    }
}
