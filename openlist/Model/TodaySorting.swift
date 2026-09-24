import Foundation

/// The Today sort choice from the previous design. Nothing on screen reads it
/// any more, but library backups still carry and validate the saved value, so
/// its vocabulary and defaults key stay.
enum TodaySorting: String {
    case `default`
    case priority
    case dueDate
    case alphabetical
    case createdAt
    case listOrder

    static let preferenceKey = "today.sorting"
}
