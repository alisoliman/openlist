//
//  OpenlistiOSWidgetBundle.swift
//  OpenlistiOSWidget
//

import SwiftUI
import WidgetKit

/// The iPhone widget extension. It reads the snapshot the app publishes to
/// the App Group through the Mac widget's providers and model, which it
/// compiles from OpenlistWidget/.
@main
struct OpenlistiOSWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayCountWidget()
    }
}

/// A stand-in until the iPhone widgets are drawn: how much of Today is done.
struct TodayCountWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.today, provider: SnapshotProvider()) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.headline)
                if entry.isPlaceholder {
                    Text("Open Openlist")
                        .foregroundStyle(.secondary)
                } else {
                    let progress = entry.state.todayProgress
                    Text("\(progress.done) of \(progress.total) done")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("How much of today is done.")
        .supportedFamilies([.systemSmall])
    }
}
