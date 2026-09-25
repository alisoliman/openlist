import SwiftUI

// The AppEnvironment stand-in the editor, inspector-text and inspector-lifetime
// checks share, around the real label picker, attachment row, block text view
// and outline editor. App navigation is isolated; this fixture does not assert
// its interaction or keyboard behavior.
@Observable final class AppEnvironment {
    let store: Store
    var activeDocument: DocumentContext?
    var commandToken = 0
    var pendingCommand: EditorCommand?
    let navigator = Navigator()
    let workbench: FixtureWorkbench
    func consumeCommand() -> EditorCommand? { defer { pendingCommand = nil }; return pendingCommand }

    init(store: Store) {
        self.store = store
        workbench = FixtureWorkbench(store: store)
    }
}
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
