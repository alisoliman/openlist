import SwiftUI

/// Lists' two views, Cards and Tasks, on the design's view switch.
struct ListsViewPicker: View {
    @Binding var selection: ListsViewMode

    var body: some View {
        OLViewPicker("Lists view", options: ListsViewMode.allCases.map { mode in
            OLViewPicker.Option(value: mode, title: mode.title, symbol: mode.symbol, identifier: "lists.view.\(mode.rawValue)")
        }, selection: $selection)
    }
}
