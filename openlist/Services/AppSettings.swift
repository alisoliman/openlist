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

    enum AfterVoiceCapture: String, CaseIterable, Identifiable {
        case reviewBeforeSaving, saveAutomatically
        var id: String { rawValue }
        var title: String {
            switch self {
            case .reviewBeforeSaving: "Review before saving"
            case .saveAutomatically: "Save automatically"
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
    var afterVoiceCapture: AfterVoiceCapture {
        didSet { defaults.set(afterVoiceCapture.rawValue, forKey: Key.afterVoiceCapture) }
    }
    var showsMenuBarExtra: Bool {
        didSet { defaults.set(showsMenuBarExtra, forKey: Key.menuBarExtra) }
    }
    var quickCaptureHotKeyEnabled: Bool {
        didSet { defaults.set(quickCaptureHotKeyEnabled, forKey: Key.quickCaptureHotKey) }
    }
    var voiceCaptureHotKeyEnabled: Bool {
        didSet { defaults.set(voiceCaptureHotKeyEnabled, forKey: Key.voiceCaptureHotKey) }
    }
    var voiceCaptureShortcut: CaptureShortcut {
        didSet { defaults.set(try? JSONEncoder().encode(voiceCaptureShortcut), forKey: Key.voiceCaptureShortcut) }
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
    /// The iPhone's Haptics setting: ticks, holds and selections answer with
    /// the system's feedback. Per device, like every setting here; the Mac
    /// has no haptics and never reads it.
    var playsHaptics: Bool {
        didSet { defaults.set(playsHaptics, forKey: Key.haptics) }
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
            Key.haptics: true,
        ])

        appearance = Appearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        showsCompletedTasks = defaults.bool(forKey: Key.showsCompleted)
        parsesNaturalLanguageDates = defaults.bool(forKey: Key.naturalLanguage)
        defaultDestination = DefaultDestination(rawValue: defaults.string(forKey: Key.defaultDestination) ?? "") ?? .inbox
        afterVoiceCapture = AfterVoiceCapture(rawValue: defaults.string(forKey: Key.afterVoiceCapture) ?? "") ?? .reviewBeforeSaving
        showsMenuBarExtra = defaults.bool(forKey: Key.menuBarExtra)
        quickCaptureHotKeyEnabled = defaults.bool(forKey: Key.quickCaptureHotKey)
        voiceCaptureHotKeyEnabled = defaults.bool(forKey: Key.voiceCaptureHotKey)
        voiceCaptureShortcut = defaults.data(forKey: Key.voiceCaptureShortcut)
            .flatMap { try? JSONDecoder().decode(CaptureShortcut.self, from: $0) } ?? .defaultVoice
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
        playsHaptics = defaults.bool(forKey: Key.haptics)
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
        static let afterVoiceCapture = "settings.afterVoiceCapture"
        static let menuBarExtra = "settings.menuBarExtra"
        static let quickCaptureHotKey = "settings.quickCaptureHotKey"
        static let voiceCaptureHotKey = "settings.voiceCaptureHotKey"
        static let voiceCaptureShortcut = "settings.voiceCaptureShortcut"
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
        static let haptics = "settings.haptics"
    }
}

struct CaptureShortcut: Codable, Equatable {
    struct Modifiers: OptionSet, Codable, Sendable {
        let rawValue: UInt32
        static let control = Self(rawValue: 1 << 0)
        static let option = Self(rawValue: 1 << 1)
        static let shift = Self(rawValue: 1 << 2)
        static let command = Self(rawValue: 1 << 3)
        static let supported: Self = [.control, .option, .shift, .command]
    }

    nonisolated enum ValidationFailure: Equatable, Sendable {
        case needsModifiers, unsupportedKey, quickAddCollision, inAppVoiceCollision, systemCollision, menuCollision, systemUnavailable

        var message: String {
            switch self {
            case .needsModifiers: "Use at least two modifiers: Control, Option, Shift or Command."
            case .unsupportedKey: "Choose a letter, number, punctuation key, Space or a function key."
            case .quickAddCollision: "⇧⌥Space is reserved for typed Quick Add. Choose a different combination."
            case .inAppVoiceCollision: "⌥⌘V is reserved for voice capture inside Openlist. Choose a different combination."
            case .systemCollision: "This combination is an enabled macOS system shortcut. Choose a different combination."
            case .menuCollision: "This combination is used by an Openlist menu command. Choose a different combination."
            case .systemUnavailable: "System shortcuts could not be checked. Try recording the shortcut again."
            }
        }
    }

    var keyCode: UInt32
    var modifiers: Modifiers
    var keyLabel = ""

    static let defaultVoice = Self(keyCode: 49, modifiers: [.control, .shift, .option])
    static let typedQuickAdd = Self(keyCode: 49, modifiers: [.shift, .option])

    var validationFailure: ValidationFailure? {
        guard modifiers.subtracting(.supported).isEmpty, modifiers.rawValue.nonzeroBitCount >= 2 else { return .needsModifiers }
        guard Self.keyNames[keyCode] != nil else { return .unsupportedKey }
        if keyCode == Self.typedQuickAdd.keyCode, modifiers == Self.typedQuickAdd.modifiers { return .quickAddCollision }
        if modifiers == [.option, .command], keyCode == 9 || keyLabel.lowercased() == "v" { return .inAppVoiceCollision }
        return nil
    }

    var display: String {
        let symbols = (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.shift) ? "⇧" : "")
            + (modifiers.contains(.option) ? "⌥" : "") + (modifiers.contains(.command) ? "⌘" : "")
        let printable = keyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = keyCode == 49 || keyCode >= 64 || printable.isEmpty
            || printable.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            ? Self.keyNames[keyCode] ?? "Unknown key" : String(printable.prefix(8)).uppercased()
        return symbols + key
    }

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 49: "Space", 50: "`", 64: "F17", 79: "F18",
        80: "F19", 90: "F20", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        118: "F4", 120: "F2", 122: "F1"
    ]
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
    /// The accent as 0xRRGGBB, which the widget snapshot carries. `color`
    /// is built from it, so the widgets can never drift from the app.
    nonisolated var hex: UInt32 {
        switch self {
        case .violet: 0x7C4DF0
        case .blue: 0x2F6FE0
        case .green: 0x1F8A6D
        case .orange: 0xC2532B
        }
    }
    /// Spelled out rather than `Color(hex:)`: the dev-isolation checks build
    /// these settings without Shared/ListAccent.swift.
    var color: Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
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
