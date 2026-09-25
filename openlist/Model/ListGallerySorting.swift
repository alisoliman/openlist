import Foundation

/// The Lists gallery sort choice from the previous design. Nothing on screen
/// reads it any more, but library backups still carry and validate the saved
/// value, so its vocabulary and defaults keys stay.
enum ListGallerySorting: String {
    case existing
    case alphabetical
    case creationDate

    static let preferenceKey = "listsGallery.sorting"
    static let ascendingPreferenceKey = "listsGallery.sortAscending"
}
