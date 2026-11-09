import Foundation

/// Today's schedule as the Today screen draws it beside the day's tasks: the
/// meetings from connected calendars and the task sessions the Calendar
/// draws, on the day of `now`, with what is on now and what comes next.
///
/// It reads what the Calendar screen reads (`CalendarCoordinator.visibleBlocks`
/// and the calendars' busy time) and only picks out the day and its moment;
/// it never plans. Times are by the wall clock, as the day column's hour
/// labels and now line are (`CalendarOverlapLayout.hours`).
struct TodaySchedule {
    enum Kind: Equatable { case meeting, session }

    struct Item: Identifiable {
        let kind: Kind
        /// The meeting, for a meeting.
        let meeting: FixedBusyTime?
        /// The block the Calendar draws, for a session.
        let block: PlannedBlock?
        let id: String
        let title: String
        let start: Date
        let end: Date
        /// A session that's done, or whose completion is settling, which now
        /// and next pass over.
        let isDone: Bool

        var taskID: UUID? { block?.taskID }
        /// Running work, which is under way whatever its times say.
        var isActive: Bool { block?.isActive ?? false }
        /// A meeting's place as its line names it: a link as the service it
        /// opens (`MeetingPlace`).
        var place: String? { meeting?.place }

        /// Under way at `now`.
        func isCurrent(at now: Date) -> Bool { !isDone && (isActive || (start <= now && now < end)) }
    }

    /// The start of the day shown.
    let day: Date
    let now: Date
    /// Meetings and sessions overlapping the day, by start: at the same time,
    /// meetings first and longer first, as the Calendar's lanes order them.
    let items: [Item]
    /// Busy time of 20 hours or more, named beside the schedule, not drawn.
    let holds: [FixedBusyTime]
    /// What's under way now: running work first, then by start.
    let current: [Item]
    /// The first thing still to start today.
    let next: Item?
    private let calendar: Calendar

    /// - Parameters:
    ///   - blocks: the blocks the Calendar draws (`visibleBlocks`), any days.
    ///   - busy: the calendars' busy time, any days.
    ///   - day: the day to read, when not the day of `now`, as the iPhone's
    ///     Timeline reads the other days of its week. Now and next stay
    ///     `now`'s: a day gone by has neither, a day to come its first item next.
    ///   - title: a session's title, its task's as the Calendar names it.
    ///   - isDone: whether a session is done, as the Calendar draws it.
    init(blocks: [PlannedBlock], busy: [FixedBusyTime], now: Date, day: Date? = nil, calendar: Calendar = .current,
         title: (PlannedBlock) -> String = { $0.titleSnapshot ?? "Task" },
         isDone: (PlannedBlock) -> Bool = \.isCompleted) {
        let day = calendar.startOfDay(for: day ?? now)
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        func overlaps(_ start: Date, _ finish: Date) -> Bool { finish > day && start < end }
        let meetings = busy.filter { overlaps($0.start, $0.end) && !$0.isAllDayHold }.map {
            Item(kind: .meeting, meeting: $0, block: nil, id: "meeting-\($0.id)", title: $0.title.isEmpty ? "Busy" : $0.title,
                 start: $0.start, end: $0.end, isDone: false)
        }
        let sessions = blocks.filter { overlaps($0.start, $0.end) }.map {
            Item(kind: .session, meeting: nil, block: $0, id: "session-\($0.id)", title: title($0), start: $0.start,
                 end: $0.end, isDone: isDone($0))
        }
        let items = (meetings + sessions).sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.kind != $1.kind { return $0.kind == .meeting }
            if $0.end != $1.end { return $0.end > $1.end }
            return $0.id < $1.id
        }
        self.day = day
        self.now = now
        self.calendar = calendar
        self.items = items
        holds = busy.filter { overlaps($0.start, $0.end) && $0.isAllDayHold }.sorted { $0.start < $1.start }
        let under = items.filter { $0.isCurrent(at: now) }
        current = under.filter(\.isActive) + under.filter { !$0.isActive }
        next = items.first { !$0.isDone && !$0.isActive && $0.start > now }
    }

    /// Nothing scheduled today, meetings or sessions.
    var isEmpty: Bool { items.isEmpty }

    /// Whether anything is under way or still to come.
    var hasRest: Bool { !current.isEmpty || next != nil }

    /// `time` on the day's clock: 10:40 is 10.67, yesterday's is negative,
    /// and tomorrow's 24 and up.
    func hour(_ time: Date) -> Double { CalendarOverlapLayout.hours(time, on: day, calendar: calendar) }

    /// The whole hours worth drawing: from the hour before now, or from the
    /// start of what's under way, to the end of the day's last item and at
    /// least two hours past now, so the now line never sits on an edge.
    /// `showsEarlier` reaches back to the day's first item too.
    func hours(showsEarlier: Bool) -> ClosedRange<Int> {
        let nowHour = Int(hour(now).rounded(.down))
        var low = nowHour - 1
        for item in current { low = min(low, Int(hour(item.start).rounded(.down))) }
        if showsEarlier, let first = items.first { low = min(low, Int(hour(first.start).rounded(.down))) }
        low = min(23, max(0, low))
        var high = max(nowHour + 2, low + 3)
        for item in items where hour(item.end) > Double(low) {
            high = max(high, Int(hour(item.end).rounded(.up)))
        }
        return low...min(24, max(low + 1, high))
    }

    /// What ends before `hours` begins: the earlier part of the day, folded
    /// away until asked for.
    func earlier(than hours: ClosedRange<Int>) -> [Item] {
        items.filter { hour($0.end) <= Double(hours.lowerBound) }
    }

    /// What `hours` shows: anything overlapping them.
    func shown(in hours: ClosedRange<Int>) -> [Item] {
        items.filter { hour($0.end) > Double(hours.lowerBound) && hour($0.start) < Double(hours.upperBound) }
    }
}

extension FixedBusyTime {
    /// Where the meeting is, as Today's lines and a meeting's details name
    /// it: a link as the service it opens (`MeetingPlace`), a room or an
    /// address as the calendar has it.
    var place: String? { location.map(MeetingPlace.name) }
}

/// A meeting's place as a line names it. A link reads as the service it
/// opens, "Microsoft Teams", "Zoom" or "Google Meet", and any other link as
/// its bare domain, so a long address never fills the line; a room or a
/// street stays as the calendar has it. Where a place gives both, as
/// "Room 4.12 / https://zoom.us/j/1" does, the room stays and the link is
/// named after it, unless the words name it already ("Zoom Meeting
/// https://zoom.us/j/1").
nonisolated enum MeetingPlace {
    /// The services meetings are held on, by the domain of their links,
    /// subdomains included ("us02web.zoom.us").
    private static let services: [(domain: String, name: String)] = [
        ("teams.microsoft.com", "Microsoft Teams"), ("teams.live.com", "Microsoft Teams"),
        ("teams.microsoft.us", "Microsoft Teams"),
        ("zoom.us", "Zoom"), ("zoom.com", "Zoom"), ("zoomgov.com", "Zoom"),
        ("meet.google.com", "Google Meet"),
        ("webex.com", "Webex"),
        ("gotomeeting.com", "GoTo Meeting"), ("gotomeet.me", "GoTo Meeting"), ("meet.goto.com", "GoTo Meeting"),
        ("facetime.apple.com", "FaceTime"),
        ("whereby.com", "Whereby"),
        ("chime.aws", "Amazon Chime"),
        ("bluejeans.com", "BlueJeans"),
        ("skype.com", "Skype"),
        ("meet.jit.si", "Jitsi Meet"),
        ("slack.com", "Slack"),
        ("discord.com", "Discord"), ("discord.gg", "Discord"),
        ("ringcentral.com", "RingCentral"),
        ("maps.apple.com", "Apple Maps"),
        ("maps.google.com", "Google Maps"), ("maps.app.goo.gl", "Google Maps"),
    ]

    /// What's trimmed from the words left beside a link: "Room 4.12 /".
    private static let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":;,|/-–—·•"))
    /// What's trimmed from around a link: "<https://…>", "(zoom.us/j/1),".
    private static let wrapping = CharacterSet(charactersIn: "<>()[]{}\"'“”‘’,;.!?")

    /// `location` with each link named: "https://teams.microsoft.com/meet/1"
    /// reads "Microsoft Teams", "https://www.example.com/events/1"
    /// "example.com". A place with no link comes back as it is.
    static func name(_ location: String) -> String {
        guard location.split(whereSeparator: \.isWhitespace).contains(where: { link($0) != nil }) else { return location }
        // Each part of the place, as calendars separate them, by the words
        // beside its links, then their names.
        var names: [String] = []
        for part in location.split(whereSeparator: { $0 == ";" || $0.isNewline }) {
            var words: [Substring] = []
            var linked: [String] = []
            for word in part.split(whereSeparator: \.isWhitespace) {
                if let link = link(word) { linked.append(name(host: link.host, path: link.path)) } else { words.append(word) }
            }
            let text = words.joined(separator: " ").trimmingCharacters(in: separators)
            names += ([text] + linked).filter { !$0.isEmpty }
        }
        // A name that another says already goes, as "Microsoft Teams" beside
        // "Microsoft Teams Meeting" does, and so does a repeat.
        let kept = names.enumerated().filter { index, name in
            !names.enumerated().contains { other, wider in
                other != index && wider.localizedCaseInsensitiveContains(name) && (wider.count > name.count || other < index)
            }
        }
        return kept.map(\.element).joined(separator: ", ")
    }

    /// The host and path of the link `word` is, if it's one: a link with a
    /// scheme ("https://…", "zoommtg://…"), or one without that starts
    /// "www.", goes on to a path ("zoom.us/j/1") or is a service's
    /// ("meet.google.com"). "4.12", "St.Mary" and an email address aren't.
    private static func link(_ word: Substring) -> (host: String, path: Substring)? {
        var rest = Substring(word.trimmingCharacters(in: wrapping))
        var schemed = false
        if let separator = rest.range(of: "://") {
            let scheme = rest[..<separator.lowerBound]
            guard scheme.first?.isLetter == true,
                  scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }) else { return nil }
            rest = rest[separator.upperBound...]
            schemed = true
        }
        let end = rest.firstIndex { "/?#".contains($0) } ?? rest.endIndex
        var authority = rest[..<end]
        let path = rest[end...]
        if let at = authority.lastIndex(of: "@") {
            guard schemed else { return nil }
            authority = authority[authority.index(after: at)...]
        }
        if let colon = authority.lastIndex(of: ":"), authority[authority.index(after: colon)...].allSatisfy(\.isNumber) {
            authority = authority[..<colon]
        }
        let host = authority.lowercased()
        if schemed {
            guard !host.isEmpty, host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }) else { return nil }
            return (host, path)
        }
        guard isDomain(host), host.hasPrefix("www.") || !path.isEmpty || service(host) != nil else { return nil }
        return (host, path)
    }

    /// A domain name: two labels or more of letters, digits and hyphens, the
    /// last of two letters or more ("zoom.us", not "4.12").
    private static func isDomain(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let last = labels.last, last.count >= 2,
              last.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    /// A link's name: its service's, else its domain without "www.".
    private static func name(host: String, path: Substring) -> String {
        if let service = service(host) { return service }
        // Google Maps' links are on google.com and goo.gl too.
        if path.hasPrefix("/maps"), isUnder(host, "google.com") || host == "goo.gl" { return "Google Maps" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func service(_ host: String) -> String? {
        services.first { isUnder(host, $0.domain) }?.name
    }

    private static func isUnder(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}
