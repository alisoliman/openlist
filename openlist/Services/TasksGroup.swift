import Foundation

/// Stable keys keep same-name lists and labels distinct.
struct TasksGroup: Identifiable {
    var id: String
    var title: String
    var symbol: String?
    var accent: ListAccent
    var tasks: [Block]
}
