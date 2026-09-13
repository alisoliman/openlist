//
//  AppSettings.swift
//  openlist
//

import Foundation
import SwiftUI

/// User preferences, persisted in `UserDefaults`.
@Observable
@MainActor
final class AppSettings {
    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    /// Where a brand-new task from ⌘N or quick capture is filed.
    enum DefaultDestination: String, CaseIterable, Identifiable {
        case inbox, today
        var id: String { rawValue }
        var title: String {
            switch self {
            case .inbox: "Inbox"
            case .today: "Today (due today)"
            }
        }
    }

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }
    /// Default for list documents and Today; lists may explicitly override it.
    var showsCompletedTasks: Bool {
        didSet { defaults.set(showsCompletedTasks, forKey: Key.showsCompleted) }
    }
    var parsesNaturalLanguageDates: Bool {
        didSet { defaults.set(parsesNaturalLanguageDates, forKey: Key.naturalLanguage) }
    }
    var defaultDestination: DefaultDestination {
        didSet { defaults.set(defaultDestination.rawValue, forKey: Key.defaultDestination) }
    }
    var showsMenuBarExtra: Bool {
        didSet { defaults.set(showsMenuBarExtra, forKey: Key.menuBarExtra) }
    }
    var quickCaptureHotKeyEnabled: Bool {
        didSet { defaults.set(quickCaptureHotKeyEnabled, forKey: Key.quickCaptureHotKey) }
    }
    var showsDockBadge: Bool {
        didSet { defaults.set(showsDockBadge, forKey: Key.dockBadge) }
    }
    var confirmsBeforeDeletingLists: Bool {
        didSet { defaults.set(confirmsBeforeDeletingLists, forKey: Key.confirmDelete) }
    }
    /// 1 = Sunday, 2 = Monday. Zero means follow the locale.
    var firstWeekday: Int {
        didSet { defaults.set(firstWeekday, forKey: Key.firstWeekday) }
    }
    var hasSeededSampleData: Bool {
        didSet { defaults.set(hasSeededSampleData, forKey: Key.seeded) }
    }
    var mcpEnabled: Bool {
        didSet { defaults.set(mcpEnabled, forKey: Key.mcpEnabled) }
    }
    var mcpAllowsWrites: Bool {
        didSet { defaults.set(mcpAllowsWrites, forKey: Key.mcpAllowsWrites) }
    }
    var mcpPort: Int {
        didSet { defaults.set(mcpPort, forKey: Key.mcpPort) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = ReviewSession.defaults) {
        self.defaults = defaults
        #if OPENLIST_DEV
        let defaultMCPPort = 45874
        let defaultQuickCaptureHotKey = false
        #else
        let defaultMCPPort = 45873
        let defaultQuickCaptureHotKey = true
        #endif
        defaults.register(defaults: [
            Key.showsCompleted: true,
            Key.naturalLanguage: true,
            Key.menuBarExtra: true,
            Key.quickCaptureHotKey: defaultQuickCaptureHotKey,
            Key.dockBadge: true,
            Key.confirmDelete: true,
            Key.firstWeekday: 0,
            Key.mcpEnabled: false,
            Key.mcpAllowsWrites: false,
            Key.mcpPort: defaultMCPPort,
        ])

        appearance = Appearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        showsCompletedTasks = defaults.bool(forKey: Key.showsCompleted)
        parsesNaturalLanguageDates = defaults.bool(forKey: Key.naturalLanguage)
        defaultDestination = DefaultDestination(rawValue: defaults.string(forKey: Key.defaultDestination) ?? "") ?? .inbox
        showsMenuBarExtra = defaults.bool(forKey: Key.menuBarExtra)
        quickCaptureHotKeyEnabled = defaults.bool(forKey: Key.quickCaptureHotKey)
        showsDockBadge = defaults.bool(forKey: Key.dockBadge)
        confirmsBeforeDeletingLists = defaults.bool(forKey: Key.confirmDelete)
        firstWeekday = defaults.integer(forKey: Key.firstWeekday)
        hasSeededSampleData = defaults.bool(forKey: Key.seeded)
        mcpEnabled = defaults.bool(forKey: Key.mcpEnabled)
        mcpAllowsWrites = defaults.bool(forKey: Key.mcpAllowsWrites)
        mcpPort = defaults.integer(forKey: Key.mcpPort)
    }

    /// A calendar honouring the user's chosen first day of the week.
    var calendar: Calendar {
        var calendar = Calendar.current
        if firstWeekday >= 1, firstWeekday <= 7 {
            calendar.firstWeekday = firstWeekday
        }
        return calendar
    }

    private enum Key {
        static let appearance = "settings.appearance"
        static let showsCompleted = "settings.showsCompleted"
        static let naturalLanguage = "settings.naturalLanguage"
        static let defaultDestination = "settings.defaultDestination"
        static let menuBarExtra = "settings.menuBarExtra"
        static let quickCaptureHotKey = "settings.quickCaptureHotKey"
        static let dockBadge = "settings.dockBadge"
        static let confirmDelete = "settings.confirmDelete"
        static let firstWeekday = "settings.firstWeekday"
        static let seeded = "settings.hasSeededSampleData"
        static let mcpEnabled = "settings.mcpEnabled"
        static let mcpAllowsWrites = "settings.mcpAllowsWrites"
        static let mcpPort = "settings.mcpPort"
    }
}
