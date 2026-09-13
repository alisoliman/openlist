import SwiftUI

struct CalendarZoomMenu: View {
    let selection: CGFloat
    let onSelect: (CGFloat) -> Void

    var body: some View {
        Menu {
            CheckmarkMenuItem("Compact", isSelected: selection == 64) { onSelect(64) }
            CheckmarkMenuItem("Comfortable", isSelected: selection == 88) { onSelect(88) }
            CheckmarkMenuItem("Large", isSelected: selection == 112) { onSelect(112) }
        } label: {
            Image(systemName: "plus.magnifyingglass").frame(width: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Calendar zoom")
        .help("Adjust the height of each hour")
    }
}
