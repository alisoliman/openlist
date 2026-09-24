import SwiftUI

// The real label picker, attachment row and block text view are hosted. App
// navigation is isolated; this fixture does not assert its interaction or
// keyboard behavior.
enum DetailPicker: String { case due, repeatRule, reminder, labels }
@Observable final class AppEnvironment {
    let store: Store
    var templateCopyRequest: TemplateCopyRequest?
    var activeDocument: DocumentContext?
    var commandToken = 0
    var pendingCommand: EditorCommand?
    let settings = FixtureSettings()
    let navigator = Navigator()
    let workbench: FixtureWorkbench
    func openTask(_ id: UUID, showing: DetailPicker) { navigator.openTask(id) }
    func consumeCommand() -> EditorCommand? { defer { pendingCommand = nil }; return pendingCommand }
    func copyLink(to target: LocalLink.Target) {}

    init(store: Store) {
        self.store = store
        workbench = FixtureWorkbench(store: store)
    }
}
final class FixtureSettings { var parsesNaturalLanguageDates = true }
/// The label picker's edits, straight to the store; the app's go through its workbench.
final class FixtureWorkbench {
    let store: Store
    init(store: Store) { self.store = store }
    func toggleLabel(_ id: UUID, labelID: UUID) {
        if let block = store.block(id: id) { store.toggleLabel(id: labelID, on: block) }
    }
    func addLabel(named name: String, to id: UUID) {
        if let block = store.block(id: id), let label = store.findOrCreateLabel(named: name) { store.addLabel(label, to: block) }
    }
}
