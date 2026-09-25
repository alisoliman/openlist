//
//  WidgetLink.swift
//  Shared between the app and the widget extension.
//

import Foundation

/// URLs a widget opens, and the app's reading of them.
///
/// They share the app's registered scheme but use the `widget` host. The app
/// claims them before item-link handling at every entry point, since
/// `LocalLink` parsing only accepts `v1` item links.
///
///     openlist://widget/capture
///     openlist://widget/capture/today
///     openlist://widget/capture/list/<uuid>
///     openlist://widget/inbox
///     openlist://widget/triage
///     openlist://widget/today
///     openlist://widget/calendar
///     openlist://widget/activity
///     openlist://widget/task/<uuid>
///     openlist://widget/list/<uuid>
nonisolated enum WidgetLink: Equatable, Sendable {
    /// Quick Add, optionally filing into a list.
    case capture(listID: UUID?)
    /// Quick Add from the Today widget: an undated task is due today, as New
    /// task on the app's Today screen makes it.
    case captureToday
    case inbox
    /// The Inbox's one-card-at-a-time triage view.
    case triage
    case today
    case calendar
    case activity
    case task(UUID)
    case list(UUID)

    static let host = "widget"

    /// Matches `LocalLink.scheme`: Dev builds register their own scheme so a
    /// Dev widget never opens the production app.
    static var scheme: String {
        #if OPENLIST_DEV
        "openlist-dev"
        #else
        "openlist"
        #endif
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.path = "/" + pathComponents.joined(separator: "/")
        return components.url!
    }

    private var pathComponents: [String] {
        switch self {
        case .capture(let listID?): ["capture", "list", listID.uuidString.lowercased()]
        case .capture(nil): ["capture"]
        case .captureToday: ["capture", "today"]
        case .inbox: ["inbox"]
        case .triage: ["triage"]
        case .today: ["today"]
        case .calendar: ["calendar"]
        case .activity: ["activity"]
        case .task(let id): ["task", id.uuidString.lowercased()]
        case .list(let id): ["list", id.uuidString.lowercased()]
        }
    }

    /// `true` for any URL on the widget host of either build's scheme, so the
    /// app can claim it before item-link handling reports it as unsupported.
    static func isWidgetLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["openlist", "openlist-dev"].contains(scheme) else { return false }
        return url.host?.lowercased() == host
    }

    /// The route, or `nil` for anything malformed or meant for the other build.
    init?(url: URL) {
        guard Self.isWidgetLink(url), url.scheme?.lowercased() == Self.scheme,
              url.query == nil, url.fragment == nil, url.user == nil, url.port == nil
        else { return nil }
        let parts = url.path.split(separator: "/").map { $0.lowercased() }
        switch parts.count {
        case 1:
            switch parts[0] {
            case "capture": self = .capture(listID: nil)
            case "inbox": self = .inbox
            case "triage": self = .triage
            case "today": self = .today
            case "calendar": self = .calendar
            case "activity": self = .activity
            default: return nil
            }
        case 2 where parts == ["capture", "today"]:
            self = .captureToday
        case 2:
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            switch parts[0] {
            case "task": self = .task(id)
            case "list": self = .list(id)
            default: return nil
            }
        case 3:
            guard parts[0] == "capture", parts[1] == "list", let id = UUID(uuidString: parts[2]) else { return nil }
            self = .capture(listID: id)
        default:
            return nil
        }
    }
}
