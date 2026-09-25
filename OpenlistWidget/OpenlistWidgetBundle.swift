//
//  OpenlistWidgetBundle.swift
//  OpenlistWidget
//

import SwiftUI
import WidgetKit

@main
struct OpenlistWidgetBundle: WidgetBundle {
    init() {
        // Titles and big numbers are set in Instrument Serif. The Info.plist
        // declares it too; registering here covers hosts that load the
        // extension without reading that key.
        WidgetFonts.register()
    }

    /// In the order the widget gallery lists them.
    var body: some Widget {
        TodayWidget()
        UpNextWidget()
        QuickAddWidget()
        ListWidget()
        AgendaWidget()
        SummaryWidget()
        ActivityWidget()
    }
}
