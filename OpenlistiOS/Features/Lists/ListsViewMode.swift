import Foundation

/// The two ways to browse Lists. Stored per device and kept when returning.
enum ListsViewMode: String, CaseIterable, Identifiable {
    case cards, tasks

    var id: String { rawValue }
    var title: String { self == .cards ? "Cards" : "Tasks" }
    var symbol: String { self == .cards ? "square.grid.2x2" : "checklist" }
}
