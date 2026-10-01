#if DEBUG
import Foundation

/// An explicit review-only addition, separate from the canonical phone
/// fixture. Bootstrap calls this only while first seeding an empty, local
/// review library, so neither normal launches nor relaunches add content.
@MainActor
enum ListDocumentFixture {
    static func seedIfRequested(into store: Store, reviewSession: String?,
                                environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard reviewSession != nil, environment["OpenlistDocumentFixture"] == "1" else { return }
        store.withoutLogging {
            let list = store.createList(title: "Document review", icon: "🗻", accent: .violet)
            let document = DocumentContext(listID: list.id)
            store.appendBlock(kind: .heading1, text: "Before we go", to: document)
            let parent = store.appendBlock(kind: .task, text: "Renew passports", to: document)
            let done = store.insertChild(kind: .task, text: "Get passport photos", of: parent, at: .last)
            done.isCompleted = true
            store.insertChild(kind: .task, text: "Submit the passport applications", of: parent, at: .last)
            parent.isCollapsed = true
            store.appendBlock(kind: .paragraph, text: "Bring the travel folder.", to: document)
            store.appendBlock(kind: .heading1, text: "In Kyoto", to: document)
            store.appendBlock(kind: .paragraph, text: "Ryokan check-in is at 15:00. Leave the bags at reception if we arrive early.", to: document)
            store.appendBlock(kind: .task, text: "Pick up the rail passes", to: document)

            let notes = store.createList(title: "Travel notes", icon: "📝", accent: .blue)
            store.appendBlock(kind: .paragraph, text: "Keep the train confirmation here.",
                              to: DocumentContext(listID: notes.id))
            store.save()
        }
    }
}
#endif
