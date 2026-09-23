import Foundation

/// Only portable library behavior is included. App appearance, window layout,
/// menu-bar/hotkey controls, device identity, calendar connections, permissions,
/// notification delivery state, MCP credentials and sync state stay on this Mac.
nonisolated struct LibraryBackupSettings: Codable, Equatable, Sendable {
    var showsCompletedTasks: Bool
    var parsesNaturalLanguageDates: Bool
    var defaultDestination: String
    var confirmsBeforeDeletingLists: Bool
    var firstWeekday: Int
    var todaySorting: String
    var listsSorting: String
    var listsSortAscending: Bool
    var calendarPreferences: CalendarPreferences

    @MainActor init(defaults: UserDefaults) {
        func bool(_ key: String, fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        showsCompletedTasks = bool("settings.showsCompleted", fallback: false)
        parsesNaturalLanguageDates = bool("settings.naturalLanguage", fallback: true)
        defaultDestination = defaults.string(forKey: "settings.defaultDestination") ?? "inbox"
        confirmsBeforeDeletingLists = bool("settings.confirmDelete", fallback: true)
        firstWeekday = defaults.integer(forKey: "settings.firstWeekday")
        todaySorting = defaults.string(forKey: TodaySorting.preferenceKey) ?? TodaySorting.default.rawValue
        listsSorting = defaults.string(forKey: ListGallerySorting.preferenceKey) ?? ListGallerySorting.existing.rawValue
        listsSortAscending = bool(ListGallerySorting.ascendingPreferenceKey, fallback: true)
        calendarPreferences = defaults.data(forKey: "calendar.preferences")
            .flatMap { try? JSONDecoder().decode(CalendarPreferences.self, from: $0) } ?? CalendarPreferences()
    }

    func validate() throws {
        guard ["inbox", "today"].contains(defaultDestination), (0...7).contains(firstWeekday),
              TodaySorting(rawValue: todaySorting) != nil, ListGallerySorting(rawValue: listsSorting) != nil else {
            throw LibraryBackupError.invalid("Unsupported library preferences.")
        }
        guard calendarPreferences.defaultEstimateMinutes.isFinite,
              (1...1_440).contains(calendarPreferences.defaultEstimateMinutes),
              (1...1_440).contains(calendarPreferences.minimumSessionMinutes),
              (1...366).contains(calendarPreferences.horizonDays) else {
            throw LibraryBackupError.invalid("Invalid calendar preferences.")
        }
        for profile in [calendarPreferences.work, calendarPreferences.personal] {
            guard profile.weekly.keys.allSatisfy({ (1...7).contains($0) }),
                  profile.breaks.keys.allSatisfy({ (1...7).contains($0) }) else {
                throw LibraryBackupError.invalid("Invalid calendar weekday.")
            }
            let windows = profile.weekly.values.flatMap { $0 } + profile.breaks.values.flatMap { $0 }
                + profile.overrides.flatMap { $0.windows + $0.breaks }
            guard windows.allSatisfy({ (0...1_440).contains($0.startMinute) && (0...1_440).contains($0.endMinute) && $0.endMinute > $0.startMinute }) else {
                throw LibraryBackupError.invalid("Invalid calendar availability window.")
            }
        }
    }

    /// Only called during startup activation, before observers are constructed.
    @MainActor func apply(to defaults: UserDefaults) throws {
        try validate()
        defaults.set(showsCompletedTasks, forKey: "settings.showsCompleted")
        defaults.set(parsesNaturalLanguageDates, forKey: "settings.naturalLanguage")
        defaults.set(defaultDestination, forKey: "settings.defaultDestination")
        defaults.set(confirmsBeforeDeletingLists, forKey: "settings.confirmDelete")
        defaults.set(firstWeekday, forKey: "settings.firstWeekday")
        defaults.set(todaySorting, forKey: TodaySorting.preferenceKey)
        defaults.set(listsSorting, forKey: ListGallerySorting.preferenceKey)
        defaults.set(listsSortAscending, forKey: ListGallerySorting.ascendingPreferenceKey)
        defaults.set(try JSONEncoder().encode(calendarPreferences), forKey: "calendar.preferences")
    }
}
