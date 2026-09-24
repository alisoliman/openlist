//
//  OpenlistWidgetBundle.swift
//  OpenlistWidget
//

import SwiftUI
import WidgetKit

@main
struct OpenlistWidgetBundle: WidgetBundle {
    init() {
        WidgetFonts.register()
    }

    /// In the design's order.
    var body: some Widget {
        TodayWidget()
        UpNextWidget()
        CaptureWidget()
        ListWidget()
        AgendaWidget()
        SummaryWidget()
        ActivityWidget()
    }
}
