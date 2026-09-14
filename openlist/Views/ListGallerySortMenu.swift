import SwiftUI

struct ListGallerySortMenu: View {
    @Binding var sorting: ListGallerySorting
    @Binding var ascending: Bool

    var body: some View {
        Menu {
            Picker("Sort by", selection: $sorting) {
                ForEach(ListGallerySorting.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)

            if sorting != .existing {
                Divider()
                Picker("Order", selection: $ascending) {
                    Text(sorting.directionTitle(ascending: true)).tag(true)
                    Text(sorting.directionTitle(ascending: false)).tag(false)
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label(sorting == .existing ? "Sort" : sorting.title, systemImage: "arrow.up.arrow.down")
                .font(Theme.Font.metadata)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Sort lists")
        .accessibilityValue(sorting.summary(ascending: ascending))
        .help("Sort the Lists gallery")
    }
}
