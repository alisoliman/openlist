import SwiftUI

// The real metadata, label picker and chips are hosted below. Their unrelated
// schedule popover and application services are not opened by this fixture.
enum DetailPicker: String { case due, repeatRule, reminder, labels }
@Observable final class AppEnvironment {
    let store: Store
    var requestedPicker: DetailPicker?
    init(store: Store) { self.store = store }
}
struct TaskSchedulePicker: View {
    let block: Block
    let initialSection: DetailPicker
    var body: some View { EmptyView() }
}
struct TaskCompletionFeedback: ViewModifier {
    let trigger: Int
    let accent: Color
    func body(content: Content) -> some View { content }
}
