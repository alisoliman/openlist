import Foundation

struct TaskCaptureRequest: Identifiable {
    let id = UUID()
    var text = ""
    var suggestedListID: UUID?
}
