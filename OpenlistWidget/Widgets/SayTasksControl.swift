//
//  SayTasksControl.swift
//  OpenlistWidget
//

import AppIntents
import SwiftUI
import WidgetKit

/// Say Tasks, for Control Center and the menu bar, and on the iPhone the
/// Lock Screen and the Action button: opens capture listening for tasks to
/// be said, Quick Add's on the Mac and the Capture sheet on the iPhone.
struct SayTasksControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKind.sayTasks) {
            ControlWidgetButton(action: OpenURLIntent(WidgetLink.captureVoice.url)) {
                Label("Say Tasks", systemImage: "mic")
            }
        }
        .displayName("Say Tasks")
        .description("Opens Openlist listening for tasks to add.")
    }
}
