//
//  PhoneRoute.swift
//  OpenlistiOS
//

import Foundation

/// The dock's three tabs, each with its own navigation stack.
enum PhoneTab: String, CaseIterable, Identifiable, Hashable {
    case today, inbox, lists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .inbox: "Inbox"
        case .lists: "Lists"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .inbox: "tray"
        case .lists: "square.grid.2x2"
        }
    }
}

/// What the Capture sheet starts with: a list (the Inbox when nil), whether
/// a task typed without a date is due today, and whether it starts listening
/// for tasks to be said.
struct CaptureRequest: Hashable, Identifiable {
    var listID: UUID?
    var dueToday = false
    var listens = false
    /// Two requests for the same list are still two presentations.
    var id = UUID()

    init(listID: UUID? = nil, dueToday: Bool = false, listens: Bool = false) {
        self.listID = listID
        self.dueToday = dueToday
        self.listens = listens
    }

    init(_ request: QuickCaptureRequest) {
        self.init(listID: request.listID, dueToday: request.dueToday, listens: request.listens)
    }
}

/// Every screen of the iPhone app, and how each is presented.
enum PhoneRoute: Hashable, Identifiable {
    case today
    /// Today's day as a timeline, in Today's place (the calendar toggle).
    case timeline
    case activity
    case taskDetail(UUID)
    case inbox
    case triage
    case lists
    case list(UUID)
    /// Find, starting from `query` ("" for none, "#travel" from a label chip).
    case find(String)
    case settings
    case trash
    case working
    case capture(CaptureRequest)

    var id: Self { self }

    enum Presentation: Equatable {
        /// A tab's root screen.
        case tab(PhoneTab)
        /// Shown in its tab's root in place of another: the timeline in Today's.
        case mode(PhoneTab)
        /// Pushed on the current navigation stack, a tab's or the Settings sheet's.
        case push
        /// Over everything: Settings, with its own stack, covering the screen,
        /// and Capture, a sheet.
        case sheet
        /// Covers the dock and tabs: Working, Triage.
        case fullScreenCover
        /// Pushed inside the Settings sheet, opening it first if needed.
        case settingsStack
    }

    var presentation: Presentation {
        switch self {
        case .today: .tab(.today)
        case .inbox: .tab(.inbox)
        case .lists: .tab(.lists)
        case .timeline: .mode(.today)
        case .activity, .taskDetail, .list, .find: .push
        case .settings, .capture: .sheet
        case .working, .triage: .fullScreenCover
        case .trash: .settingsStack
        }
    }

    /// The tab a link lands the screen on when nothing else decides.
    var home: PhoneTab {
        switch self {
        case .today, .timeline, .activity, .working, .taskDetail: .today
        case .inbox, .triage: .inbox
        case .lists, .list, .find, .settings, .trash: .lists
        case .capture: .today
        }
    }

    /// For UI tests and VoiceOver: the identifier the screen's root carries.
    var screenIdentifier: String {
        switch self {
        case .today: "screen.today"
        case .timeline: "screen.timeline"
        case .activity: "screen.activity"
        case .taskDetail: "screen.taskDetail"
        case .inbox: "screen.inbox"
        case .triage: "screen.triage"
        case .lists: "screen.lists"
        case .list: "screen.list"
        case .find: "screen.find"
        case .settings: "screen.settings"
        case .trash: "screen.trash"
        case .working: "screen.working"
        case .capture: "screen.capture"
        }
    }
}

/// A sheet on the root.
enum PhoneSheet: Identifiable, Hashable {
    case settings
    case capture(CaptureRequest)

    var id: String {
        switch self {
        case .settings: "settings"
        case let .capture(request): "capture-\(request.id)"
        }
    }
}

/// A full-screen cover on the root.
enum PhoneCover: String, Identifiable, Hashable {
    case working, triage
    var id: String { rawValue }
}
