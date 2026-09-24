import Foundation

/// Something on the calendar that planned work moved to a new time would
/// overlap: a meeting or another block drawn there.
struct WorkMoveOverlap: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
}
