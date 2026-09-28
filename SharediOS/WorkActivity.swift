//
//  WorkActivity.swift
//  SharediOS
//

import ActivityKit
import AppIntents
import Foundation

/// The Live Activity of work under way (mockup 05): the task, how long is
/// left, and Pause or Resume and Done. The app starts it when work starts,
/// updates it as the work pauses and resumes, and ends it when the work stops.
nonisolated struct WorkActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable { case working, paused }

        var phase: Phase
        var title: String
        /// "💼 Q3 planning".
        var listLine: String
        /// When the block the work runs in ends, or its estimate runs out:
        /// what "50 min left" counts down to while it runs.
        var endsAt: Date
        /// Where the bar starts: the block's start, or the work's.
        var startedAt: Date
        /// Minutes left when it paused, which stay put until it resumes.
        var pausedMinutesLeft: Int?

        var isPaused: Bool { phase == .paused }

        /// How far through the block it is at `now`, 0–1.
        func progress(at now: Date) -> Double {
            let length = endsAt.timeIntervalSince(startedAt)
            guard length > 0 else { return 0 }
            return min(1, max(0, now.timeIntervalSince(startedAt) / length))
        }
    }

    /// The task and occurrence the work is on, which its buttons name.
    var taskID: String
    var occurrenceID: String
}

// The Live Activity's buttons run in the app, as the widgets' do, even from
// the Lock Screen.
extension PauseWorkIntent: LiveActivityIntent {}
extension ResumeWorkIntent: LiveActivityIntent {}
extension FinishWorkIntent: LiveActivityIntent {}
