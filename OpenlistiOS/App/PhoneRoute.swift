//
//  PhoneRoute.swift
//  OpenlistiOS
//

import Foundation

/// The dock's four tabs, each with its own navigation stack.
enum PhoneTab: String, CaseIterable, Identifiable, Hashable, Codable {
    case today, inbox, lists, work

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .inbox: "Inbox"
        case .lists: "Lists"
        case .work: "Work"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .inbox: "tray"
        case .lists: "list.bullet"
        case .work: "timer"
        }
    }
}

/// What the Capture sheet starts with: a list (the Inbox when nil), whether
/// a task typed without a date is due today, and whether it starts listening
/// for tasks to be said.
struct CaptureRequest: Hashable, Identifiable, Codable {
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

/// What triage deals: the Inbox, to file and date, or the tasks in the lists
/// that have no date yet.
enum TriageMode: String, CaseIterable, Identifiable, Hashable, Codable {
    case inbox, undated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .undated: "No date"
        }
    }

    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .undated: "calendar"
        }
    }
}

/// Every screen of the iPhone app, and how each is presented.
enum PhoneRoute: Hashable, Identifiable, Codable {
    case today
    case work
    /// Today's day as a timeline, in Today's place (the calendar toggle).
    case timeline
    case activity
    case taskDetail(UUID)
    /// A task's own history, pushed from its page.
    case taskHistory(UUID)
    case inbox
    /// Triage, opening on the cards of one mode: the Inbox's or No date's.
    case triage(TriageMode)
    case lists
    case list(UUID)
    /// Find, starting from `query` ("" for none, "#travel" from a label chip).
    case find(String)
    case settings
    case trash
    /// The hours planning fills, pushed inside Settings.
    case planHours
    case working
    case capture(CaptureRequest)

    var id: Self { self }

    enum Presentation: Equatable {
        /// A tab's root screen.
        case tab(PhoneTab)
        /// Shown in its tab's root in place of another: the timeline in Today's.
        case mode(PhoneTab)
        /// Pushed on the stack in front: a tab's, the Settings sheet's, or a
        /// cover's.
        case push
        /// A sheet over everything: Settings, with its own stack, and Capture.
        case sheet
        /// Covers the dock and tabs: Working, Triage, each a mode with its
        /// own stack.
        case fullScreenCover
        /// Pushed inside the Settings sheet, opening it first if needed.
        case settingsStack
    }

    var presentation: Presentation {
        switch self {
        case .today: .tab(.today)
        case .inbox: .tab(.inbox)
        case .lists: .tab(.lists)
        case .work: .tab(.work)
        case .timeline: .mode(.today)
        case .activity, .taskDetail, .taskHistory, .list, .find: .push
        case .settings, .capture: .sheet
        case .working, .triage: .fullScreenCover
        case .trash, .planHours: .settingsStack
        }
    }

    /// The tab a link lands the screen on when nothing else decides.
    var home: PhoneTab {
        switch self {
        case .today, .timeline, .activity, .working, .taskDetail, .taskHistory: .today
        case .work: .work
        case .inbox, .triage: .inbox
        case .lists, .list, .find, .settings, .trash, .planHours: .lists
        case .capture: .today
        }
    }

    /// For UI tests and VoiceOver: the identifier the screen's root carries.
    var screenIdentifier: String {
        switch self {
        case .today: "screen.today"
        case .work: "screen.work"
        case .timeline: "screen.timeline"
        case .activity: "screen.activity"
        case .taskDetail: "screen.taskDetail"
        case .taskHistory: "screen.taskHistory"
        case .inbox: "screen.inbox"
        case .triage: "screen.triage"
        case .lists: "screen.lists"
        case .list: "screen.list"
        case .find: "screen.find"
        case .settings: "screen.settings"
        case .trash: "screen.trash"
        case .planHours: "screen.planHours"
        case .working: "screen.working"
        case .capture: "screen.capture"
        }
    }
}

/// A sheet on the root.
enum PhoneSheet: Identifiable, Hashable, Codable {
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
enum PhoneCover: String, Identifiable, Hashable, Codable {
    case working, triage
    var id: String { rawValue }
}
