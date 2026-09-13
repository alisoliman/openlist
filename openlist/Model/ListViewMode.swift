import Foundation

/// A presentation choice for this Mac, separate from the synced document.
enum ListViewMode: String, CaseIterable, Identifiable {
    case document, tasks

    var id: String { rawValue }
    var title: String { self == .document ? "Document" : "Tasks" }
}
