//
//  WidgetRoute.swift
//  Shared between the app and the widget extension.
//

import Foundation

/// The places a widget tap can open, beyond the task and list links every
/// Openlist link already covers.
///
/// Widget routes use a host of their own (`openlist://capture`), so they never
/// collide with version 1 item links (`openlist://v1/<library>/task/<id>`),
/// which this type builds but leaves to `LocalLink` to open.
nonisolated enum WidgetRoute: Equatable, Hashable, Sendable {
    /// Quick Add, optionally filing into a list or planning for today.
    case capture(listID: UUID?, forToday: Bool)
    case inbox, triage, today, calendar, activity

    #if OPENLIST_DEV
    static let scheme = "openlist-dev"
    #else
    static let scheme = "openlist"
    #endif

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = parts.host?.lowercased(), parts.path.isEmpty || parts.path == "/" else { return nil }
        let query = Dictionary((parts.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        switch host {
        case "capture": self = .capture(listID: query["list"].flatMap(UUID.init(uuidString:)), forToday: query["today"] == "1")
        case "inbox": self = .inbox
        case "triage": self = .triage
        case "today": self = .today
        case "calendar": self = .calendar
        case "activity": self = .activity
        default: return nil
        }
    }

    var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        switch self {
        case let .capture(listID, forToday):
            parts.host = "capture"
            var items: [URLQueryItem] = []
            if let listID { items.append(URLQueryItem(name: "list", value: listID.uuidString.lowercased())) }
            if forToday { items.append(URLQueryItem(name: "today", value: "1")) }
            if !items.isEmpty { parts.queryItems = items }
        case .inbox: parts.host = "inbox"
        case .triage: parts.host = "triage"
        case .today: parts.host = "today"
        case .calendar: parts.host = "calendar"
        case .activity: parts.host = "activity"
        }
        return parts.url!
    }

    /// Exactly the app's version 1 task link, or Today when the library's link
    /// identity is unknown.
    static func taskURL(libraryID: UUID?, taskID: UUID) -> URL {
        itemURL(libraryID: libraryID, route: "task", id: taskID)
    }

    /// Exactly the app's version 1 list link, or Today when the library's link
    /// identity is unknown.
    static func listURL(libraryID: UUID?, listID: UUID) -> URL {
        itemURL(libraryID: libraryID, route: "list", id: listID)
    }

    private static func itemURL(libraryID: UUID?, route: String, id: UUID) -> URL {
        guard let libraryID else { return WidgetRoute.today.url }
        return URL(string: "\(scheme)://v1/\(libraryID.uuidString.lowercased())/\(route)/\(id.uuidString.lowercased())")!
    }
}
