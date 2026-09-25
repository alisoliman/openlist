//
//  ListWidgetIntent.swift
//  OpenlistWidget
//

import AppIntents
import Foundation

/// A list the List widget can show, as the configuration picker offers it.
nonisolated struct ListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let defaultQuery = ListEntityQuery()

    var id: UUID
    var title: String
    /// "Parent › Child" for nested lists.
    var path: String
    var icon: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(icon.isEmpty ? path : "\(icon) \(path)")")
    }

    init(id: UUID, title: String, path: String, icon: String) {
        self.id = id
        self.title = title
        self.path = path
        self.icon = icon
    }

    init(_ list: WidgetSnapshot.ListSummary) {
        self.init(id: list.id, title: list.title, path: list.path, icon: list.icon)
    }
}

/// Lists come from the snapshot the app publishes; the extension never opens
/// the store.
nonisolated struct ListEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ListEntity] {
        lists().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ListEntity] {
        lists().filter { $0.path.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [ListEntity] {
        lists()
    }

    /// The first real list: the Inbox has its own widget in Quick Add.
    func defaultResult() async -> ListEntity? {
        let lists = WidgetSnapshotStore.read()?.lists ?? []
        return (lists.first { !$0.isInbox } ?? lists.first).map(ListEntity.init)
    }

    private func lists() -> [ListEntity] {
        (WidgetSnapshotStore.read()?.lists ?? []).map(ListEntity.init)
    }
}

/// The List widget's configuration.
///
/// Not `nonisolated`, unlike the entity: a nonisolated struct cannot hold the
/// `@Parameter` property wrappers.
struct ListWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "List"
    /// Typed as the requirement is: a non-optional value would only shadow it.
    static let description: IntentDescription? = IntentDescription("Choose what this widget shows")

    @Parameter(title: "List")
    var list: ListEntity?

    @Parameter(title: "Show completed", default: false)
    var showsCompleted: Bool

    init() {}

    init(list: ListEntity?, showsCompleted: Bool = false) {
        self.list = list
        self.showsCompleted = showsCompleted
    }
}

extension ListSelection {
    nonisolated init(_ configuration: ListWidgetIntent) {
        self.init(listID: configuration.list?.id, showsCompleted: configuration.showsCompleted)
    }
}
