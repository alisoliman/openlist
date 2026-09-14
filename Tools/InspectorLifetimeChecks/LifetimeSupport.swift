import SwiftUI

// Real metadata, label picker, chips, attachment, nested row/text view and menu
// are hosted. App navigation and the unopened schedule popup are isolated;
// this fixture does not assert their interaction or keyboard behavior.
enum DetailPicker: String { case due, repeatRule, reminder, labels }
@Observable final class AppEnvironment {
    let store: Store
    var requestedPicker: DetailPicker?
    var templateCopyRequest: TemplateCopyRequest?
    var activeDocument: DocumentContext?
    var commandToken = 0
    var pendingCommand: EditorCommand?
    let settings = FixtureSettings()
    let navigator = Navigator()
    func showCopiedTask(id: UUID, listID: UUID) {}
    func openTask(_ id: UUID, showing: DetailPicker) { navigator.openTask(id) }
    func consumeCommand() -> EditorCommand? { defer { pendingCommand = nil }; return pendingCommand }
    func copyLink(to target: LocalLink.Target) {}

    init(store: Store) { self.store = store }
}
final class FixtureSettings { var parsesNaturalLanguageDates = true }
struct TaskSchedulePicker: View {
    let block: Block
    let initialSection: DetailPicker
    var body: some View { EmptyView() }
}
enum MarkdownExporter {
    static func presentError(_ error: Error, operation: String) { preconditionFailure("Unexpected attachment open: \(operation)") }
}
