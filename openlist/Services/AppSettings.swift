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
    /// Takes a library snapshot each day, keeping the last fourteen.
    var takesDailySnapshots: Bool {
        didSet { defaults.set(takesDailySnapshots, forKey: Key.dailySnapshots) }
    }

    // MARK: Interface

    var accent: NextAccent {
        didSet { defaults.set(accent.rawValue, forKey: Key.accent) }
    }
    var density: NextDensity {
        didSet { defaults.set(density.rawValue, forKey: Key.density) }
    }
    var serifTitles: Bool {
        didSet { defaults.set(serifTitles, forKey: Key.serifTitles) }
    }
    var motion: NextMotion {
        didSet { defaults.set(motion.rawValue, forKey: Key.motion) }
    }
    /// Keeps state changes but drops bounces, rings and slides.
    var reducesMotion: Bool {
        didSet { defaults.set(reducesMotion, forKey: Key.reducesMotion) }
    }
    /// How long a finished task stays in place before it settles, 2–8 seconds.
    var undoDwellSeconds: Int {
        didSet { defaults.set(undoDwellSeconds, forKey: Key.undoDwell) }
    }
    var tasksFilterStyle: TasksFilterStyle {
        didSet { defaults.set(tasksFilterStyle.rawValue, forKey: Key.tasksFilterStyle) }
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
            Key.showsCompleted: false,
            Key.naturalLanguage: true,
            Key.menuBarExtra: true,
            Key.quickCaptureHotKey: defaultQuickCaptureHotKey,
            Key.dockBadge: true,
            Key.confirmDelete: true,
            Key.firstWeekday: 0,
            Key.mcpEnabled: false,
            Key.mcpAllowsWrites: false,
            Key.mcpPort: defaultMCPPort,
            Key.serifTitles: true,
            Key.undoDwell: 5,
            Key.dailySnapshots: true,
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
        takesDailySnapshots = defaults.bool(forKey: Key.dailySnapshots)
        accent = NextAccent(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .violet
        density = NextDensity(rawValue: defaults.string(forKey: Key.density) ?? "") ?? .comfortable
        serifTitles = defaults.bool(forKey: Key.serifTitles)
        motion = NextMotion(rawValue: defaults.string(forKey: Key.motion) ?? "") ?? .expressive
        reducesMotion = defaults.bool(forKey: Key.reducesMotion)
        undoDwellSeconds = min(8, max(2, defaults.integer(forKey: Key.undoDwell)))
        tasksFilterStyle = TasksFilterStyle(rawValue: defaults.string(forKey: Key.tasksFilterStyle) ?? "") ?? .query
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
        static let accent = "settings.accent"
        static let density = "settings.density"
        static let serifTitles = "settings.serifTitles"
        static let motion = "settings.motion"
        static let reducesMotion = "settings.reducesMotion"
        static let undoDwell = "settings.undoDwellSeconds"
        static let tasksFilterStyle = "settings.tasksFilterStyle"
        static let dailySnapshots = "settings.dailySnapshots"
    }
}

enum NextAccent: String, CaseIterable, Identifiable {
    case violet, blue, green, orange
    var id: String { rawValue }
    var title: String {
        switch self {
        case .violet: "Violet"
        case .blue: "Blue"
        case .green: "Green"
        case .orange: "Orange"
        }
    }
    var color: Color {
        switch self {
        case .violet: Color(.sRGB, red: 0x7C / 255, green: 0x4D / 255, blue: 0xF0 / 255)
        case .blue: Color(.sRGB, red: 0x2F / 255, green: 0x6F / 255, blue: 0xE0 / 255)
        case .green: Color(.sRGB, red: 0x1F / 255, green: 0x8A / 255, blue: 0x6D / 255)
        case .orange: Color(.sRGB, red: 0xC2 / 255, green: 0x53 / 255, blue: 0x2B / 255)
        }
    }
}

enum NextDensity: String, CaseIterable, Identifiable {
    case comfortable, compact
    var id: String { rawValue }
    var title: String { self == .comfortable ? "Comfortable" : "Compact" }
}

enum NextMotion: String, CaseIterable, Identifiable {
    case restrained, expressive, playful
    var id: String { rawValue }
    var title: String {
        switch self {
        case .restrained: "Restrained"
        case .expressive: "Expressive"
        case .playful: "Playful"
        }
    }
    var scale: Double {
        switch self {
        case .restrained: 0.6
        case .expressive: 1
        case .playful: 1.2
        }
    }
}

enum TasksFilterStyle: String, CaseIterable, Identifiable {
    case query, sentence
    var id: String { rawValue }
    var title: String { self == .query ? "Query" : "Sentence" }
}
