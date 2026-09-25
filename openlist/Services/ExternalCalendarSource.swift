import EventKit
import Foundation
import Observation

struct ExternalCalendarDescriptor: Identifiable {
    var id: String
    var title: String
    var source: String
}

/// EventKit is used only to read calendars and events. There is deliberately no
/// event-writing API in this adapter. Access and calendar IDs remain per-Mac.
@Observable @MainActor
final class ExternalCalendarSource {
    private let eventStore = EKEventStore()
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private var range: DateInterval?
    private var fixtureBusyTimes: [FixedBusyTime]?
    private(set) var calendars: [ExternalCalendarDescriptor] = []
    private(set) var selectedCalendarIDs: Set<String>
    private(set) var busyTimes: [FixedBusyTime] = []
    private(set) var isConnected: Bool
    private(set) var isAuthorized = false
    private(set) var authorizationDescription = "Connect calendars to avoid meetings."
    private(set) var error: String?
    var onChange: (() -> Void)?
    /// Bumped on every reload, so readers of `busyTimes(in:)` can keep what
    /// they read until the calendars reload, and observers of it see changes
    /// `busyTimes` doesn't show, like a meeting renamed or one earlier in the week.
    private(set) var revision = 0

    init(defaults: UserDefaults = ReviewSession.defaults, fixtureBusyTimes: [FixedBusyTime]? = nil) {
        self.fixtureBusyTimes = fixtureBusyTimes
        self.defaults = defaults
        selectedCalendarIDs = Set(defaults.stringArray(forKey: "calendar.selectedIDs") ?? [])
        isConnected = defaults.bool(forKey: "calendar.connected")
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func requestAccess() async {
        do {
            guard try await eventStore.requestFullAccessToEvents() else {
                updateAuthorization()
                error = "Calendar access was not granted. Enable it in System Settings > Privacy & Security > Calendars."
                return
            }
            isConnected = true
            defaults.set(true, forKey: "calendar.connected")
            // An explicit empty selection must survive relaunch and reconnect.
            if defaults.object(forKey: "calendar.selectedIDs") == nil {
                selectedCalendarIDs = Set(eventStore.calendars(for: .event).map(\.calendarIdentifier))
                persistSelection()
            }
            reload()
        } catch {
            self.error = error.localizedDescription
            updateAuthorization()
        }
    }

    /// A fixture's meetings edited, as in Calendar, for the checks. Like an
    /// edit there, it leaves `revision` alone until the calendars reload, so
    /// readers that keep what they read see it only then.
    func editFixture(_ busyTimes: [FixedBusyTime]) {
        guard fixtureBusyTimes != nil else { return }
        fixtureBusyTimes = busyTimes
    }

    func refresh(start: Date, end: Date) {
        range = DateInterval(start: start, end: end)
        reload()
    }

    func setCalendarEnabled(_ id: String, enabled: Bool) {
        if enabled { selectedCalendarIDs.insert(id) } else { selectedCalendarIDs.remove(id) }
        persistSelection()
        reload()
    }

    func disconnect() {
        revision &+= 1
        isConnected = false
        defaults.set(false, forKey: "calendar.connected")
        calendars = []
        busyTimes = []
        error = nil
        updateAuthorization()
        onChange?()
    }

    private func persistSelection() {
        defaults.set(selectedCalendarIDs.sorted(), forKey: "calendar.selectedIDs")
    }

    private func updateAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = isConnected && status == .fullAccess
        if !isConnected { authorizationDescription = "Connect calendars to avoid meetings." }
        else if isAuthorized { authorizationDescription = "External events are fixed busy time. Openlist never changes them." }
        else { authorizationDescription = "Calendar access is unavailable. Your schedule cannot account for meetings." }
    }

    private func reload() {
        revision &+= 1
        if let fixtureBusyTimes {
            busyTimes = fixtureBusyTimes
            authorizationDescription = "Isolated calendar fixture"
            onChange?()
            return
        }
        updateAuthorization()
        guard isAuthorized else {
            error = isConnected ? "Calendar access is unavailable. Allow access in System Settings to include meetings in this plan." : nil
            calendars = []
            busyTimes = []
            onChange?()
            return
        }
        error = nil
        let sources = eventStore.calendars(for: .event)
        calendars = sources.map { ExternalCalendarDescriptor(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
        let selected = sources.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        let unavailable = selectedCalendarIDs.subtracting(Set(sources.map(\.calendarIdentifier)))
        if !unavailable.isEmpty { error = "Some selected calendars are unavailable. Check the connected calendar selection; their busy time is missing from this plan." }
        guard let range, !selected.isEmpty else {
            busyTimes = []
            onChange?()
            return
        }
        let predicate = eventStore.predicateForEvents(withStart: range.start, end: range.end, calendars: selected)
        busyTimes = busy(eventStore.events(matching: predicate))
        onChange?()
    }

    /// The selected calendars' busy time in `interval`, read without changing
    /// what the planner uses. The widget's week starts before today, where the
    /// planner's range doesn't reach.
    func busyTimes(in interval: DateInterval) -> [FixedBusyTime] {
        if let fixtureBusyTimes { return fixtureBusyTimes.filter { $0.end > interval.start && $0.start < interval.end } }
        guard isConnected, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let selected = eventStore.calendars(for: .event).filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else { return [] }
        return busy(eventStore.events(matching: eventStore.predicateForEvents(withStart: interval.start, end: interval.end, calendars: selected)))
    }

    /// Events that hold time: not cancelled, not free, not declined.
    private func busy(_ events: [EKEvent]) -> [FixedBusyTime] {
        events.compactMap { event in
            guard event.status != .canceled, event.availability != .free,
                  !(event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false),
                  let start = event.startDate, let end = event.endDate, end > start else { return nil }
            return FixedBusyTime(id: "\(event.calendarItemIdentifier)-\(start.timeIntervalSinceReferenceDate)",
                                 title: event.title ?? "Busy", start: start, end: end)
        }.sorted { $0.start < $1.start }
    }
}
