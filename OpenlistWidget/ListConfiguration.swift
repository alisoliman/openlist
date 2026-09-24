//
//  ListConfiguration.swift
//  OpenlistWidget
//

import AppIntents
import WidgetKit

/// A list the List widget can show, read from the published snapshot so the
/// picker fills whether or not Openlist is running.
struct ListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let defaultQuery = ListEntityQuery()

    var id: String
    var title: String
    var icon: String

    /// "🗻 Weekend in Kyoto", or the list's SF Symbol as the entry's image
    /// rather than its name in the title.
    var displayRepresentation: DisplayRepresentation {
        if ListIcon.isSymbolName(icon) {
            return DisplayRepresentation(title: "\(title)", image: DisplayRepresentation.Image(systemName: icon))
        }
        return DisplayRepresentation(title: "\(icon.isEmpty ? "" : icon + " ")\(title)")
    }

    init(_ list: WidgetSnapshot.ListSummary) {
        id = list.id.uuidString
        title = list.title
        icon = list.icon
    }
}

struct ListEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ListEntity] {
        let wanted = Set(identifiers)
        return lists().filter { wanted.contains($0.id) }
    }

    /// Every list, in sidebar order.
    func suggestedEntities() async throws -> [ListEntity] { lists() }

    func defaultResult() async -> ListEntity? { lists().first }

    private func lists() -> [ListEntity] {
        (WidgetSnapshotStore.read()?.lists ?? []).map(ListEntity.init)
    }
}

/// "List · Choose what this widget shows".
struct SelectListIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "List"
    static let description = IntentDescription("Choose what this widget shows")

    @Parameter(title: "List") var list: ListEntity?
    @Parameter(title: "Show completed", default: false) var showsCompleted: Bool

    init() {}
}
