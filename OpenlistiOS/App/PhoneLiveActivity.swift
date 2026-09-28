//
//  PhoneLiveActivity.swift
//  OpenlistiOS
//

import ActivityKit
import Foundation

/// Keeps the work Live Activity in step with the calendar: one for the work
/// in hand while it runs or is paused, none once it stops or is done.
///
/// ActivityKit is asked one step at a time, for the latest wanted state: the
/// calendar reports one change several times over, and steps run side by
/// side would each start an activity.
@MainActor
final class PhoneLiveActivity {
    private let environment: () -> PhoneEnvironment?
    private var lastState: WorkActivityAttributes.ContentState?
    private var lastKey: String?
    /// Off until the calendar has bootstrapped. Before then no work is in
    /// hand yet, and a sync would end the activity of work still running.
    var isReady = false

    private enum Wanted {
        case none
        case show(ActivityContent<WorkActivityAttributes.ContentState>, WorkActivityAttributes, key: String)
    }

    /// The state the next step brings the activities to.
    private var wanted: Wanted?
    private var updating: Task<Void, Never>?

    init(environment: @escaping () -> PhoneEnvironment?) {
        self.environment = environment
    }

    /// Whether a Live Activity still shows `session`'s work, which bootstrap
    /// carries on rather than pausing at its last heartbeat.
    static func isShowing(_ session: WorkSession) -> Bool {
        Activity<WorkActivityAttributes>.activities.contains {
            $0.attributes.taskID == session.taskID.uuidString && $0.attributes.occurrenceID == session.occurrenceID.uuidString
                && $0.activityState == .active
        }
    }

    /// Starts, updates or ends the activity for how the work stands now.
    func sync() {
        guard isReady, ActivityAuthorizationInfo().areActivitiesEnabled, let env = environment() else { return }
        let now = env.now
        let work = PhoneWork(env: env, now: now)
        guard let task = work.task, work.state != .planned else { return endAll() }
        let key = "\(task.id.uuidString)|\(task.occurrenceID.uuidString)"
        let list = env.store.list(id: task.listID)
        // The activity counts on the system clock; a review session's pinned
        // clock is carried over onto it.
        let shift = Date.now.timeIntervalSince(now)
        // Work started ahead of its slot counts from now; the bar always runs
        // forwards, at least a minute long.
        let start = min(work.start ?? now, now)
        let end = max(now.addingTimeInterval(work.remainingMinutes * 60), start.addingTimeInterval(60))
        let state = WorkActivityAttributes.ContentState(
            phase: work.state == .working ? .working : .paused,
            title: task.displayTitle,
            listLine: list.map { "\($0.isSystemInbox ? "📥" : $0.icon) \($0.displayTitle)" } ?? "",
            endsAt: end.addingTimeInterval(shift),
            startedAt: start.addingTimeInterval(shift),
            pausedMinutesLeft: work.state == .paused ? work.minutesLeft : nil)
        // The countdown runs on the activity's own clock; only a change of
        // phase, task or more than a minute's drift is worth an update, while
        // the activity is still up.
        if key == lastKey, let lastState, lastState.phase == state.phase, lastState.title == state.title,
           abs(lastState.endsAt.timeIntervalSince(state.endsAt)) < 60, Self.isLive(key) {
            return
        }
        lastKey = key
        lastState = state
        let content = ActivityContent(state: state, staleDate: nil)
        let attributes = WorkActivityAttributes(taskID: task.id.uuidString, occurrenceID: task.occurrenceID.uuidString)
        want(.show(content, attributes, key: key))
    }

    /// Queues `state`, replacing any not yet begun, and runs the queue.
    private func want(_ state: Wanted) {
        wanted = state
        guard updating == nil else { return }
        updating = Task { [weak self] in
            while let next = self?.wanted {
                self?.wanted = nil
                switch next {
                case .none:
                    await Self.endEvery()
                case let .show(content, attributes, key):
                    // One the system turned down is asked for again at the next change.
                    if await !Self.show(content, attributes: attributes), self?.lastKey == key { self?.lastState = nil }
                }
            }
            self?.updating = nil
        }
    }

    /// Whether the activity for `key` is on show, rather than ended or dismissed.
    private static func isLive(_ wanted: String) -> Bool {
        Activity<WorkActivityAttributes>.activities.contains {
            key(of: $0) == wanted && ($0.activityState == .active || $0.activityState == .stale)
        }
    }

    /// The one activity for `attributes`' work, updated or started; any other
    /// ends. False when the system wouldn't start one.
    nonisolated private static func show(_ content: ActivityContent<WorkActivityAttributes.ContentState>,
                                         attributes: WorkActivityAttributes) async -> Bool {
        let key = "\(attributes.taskID)|\(attributes.occurrenceID)"
        var found = false
        for activity in Activity<WorkActivityAttributes>.activities {
            let live = activity.activityState == .active || activity.activityState == .stale
            if Self.key(of: activity) == key, live, !found {
                found = true
                await activity.update(content)
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        if found { return true }
        return (try? Activity.request(attributes: attributes, content: content, pushType: nil)) != nil
    }

    nonisolated private static func key(of activity: Activity<WorkActivityAttributes>) -> String {
        "\(activity.attributes.taskID)|\(activity.attributes.occurrenceID)"
    }

    private func endAll() {
        lastKey = nil
        lastState = nil
        guard !Activity<WorkActivityAttributes>.activities.isEmpty || updating != nil else { return }
        want(.none)
    }

    nonisolated private static func endEvery() async {
        for activity in Activity<WorkActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
