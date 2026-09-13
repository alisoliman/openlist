import SwiftUI

// Real metadata, label picker, chips, attachment, nested row/text view and menu
// are hosted. App navigation and the unopened schedule popup are isolated;
// this fixture does not assert their interaction or keyboard behavior.
enum DetailPicker: String { case due, repeatRule, reminder, labels }
@Observable final class AppEnvironment {
    let store: Store
    var requestedPicker: DetailPicker?
    var templateCopyRequest: TemplateCopyRequest?
    let navigator = Navigator()
    func showCopiedTask(id: UUID, listID: UUID) {}
    init(store: Store) { self.store = store }
}
@Observable final class Navigator {
    var selection: Set<UUID> = []
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

enum MarkdownExporter {
    static func presentError(_ error: Error, operation: String) { preconditionFailure("Unexpected attachment open: \(operation)") }
}
