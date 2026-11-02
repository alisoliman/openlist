//
//  TriageSession.swift
//  OpenlistiOS
//

import Foundation
import Observation

/// One pass through the Inbox, one card at a time, as the Mac's triage card
/// keeps it: the cards dealt with since triage opened, and those set aside
/// (Later, or scheduled and left in the Inbox) until the app next launches.
/// No date's pass through the lists' undated tasks is kept the same way; a
/// card it dates leaves that queue on its own.
///
/// What a card's step did is read back from the tasks rather than counted:
/// taken back by the tray's Undo, a card is on the queue again and no longer
/// reviewed. A card dated from triage stays aside only while it has the date
/// it was given, and a repeat marked done only once it has rolled on, so
/// Undo brings either back.
@Observable
@MainActor
final class TriageSession {
    /// Set aside with Later.
    private(set) var later: Set<UUID> = []
    /// Given a day from the card, which leaves them in the Inbox: the date
    /// each was given.
    private(set) var scheduled: [UUID: Date] = [:]
    /// Repeats marked done, which roll on in the Inbox: the date each had.
    private(set) var rolled: [UUID: Date] = [:]
    /// Filed, done or deleted from the card, or dated from No date's.
    private(set) var finished: Set<UUID> = []
    /// What triage has dealt with since it opened.
    private var dealt: Set<UUID> = []

    /// Triage opening: the count starts over; what was set aside stays aside.
    func begin() { dealt = [] }

    /// A card filed, done or deleted, or dated from No date's.
    func finish(_ id: UUID) {
        finished.insert(id)
        dealt.insert(id)
    }

    /// A card set aside for later: left in the Inbox, or without a date.
    func keep(_ id: UUID) {
        later.insert(id)
        dealt.insert(id)
    }

    /// A card given a day, which stays in the Inbox, due `date`.
    func schedule(_ id: UUID, due date: Date) {
        scheduled[id] = date
        dealt.insert(id)
    }

    /// A repeating card marked done, due `date` until it rolls on.
    func rollOn(_ id: UUID, from date: Date) {
        rolled[id] = date
        dealt.insert(id)
    }

    /// The tasks off the queue: kept for later, still due the day triage gave
    /// them, or rolled on from the date they had.
    func kept(dueDate: (UUID) -> Date?) -> Set<UUID> {
        later
            .union(scheduled.filter { dueDate($0.key) == $0.value }.keys)
            .union(rolled.filter { entry in dueDate(entry.key).map { $0 != entry.value } ?? false }.keys)
    }

    /// Cards dealt with since triage opened that haven't come back to `queue`.
    func reviewed(queue: [Block]) -> Int {
        dealt.subtracting(queue.lazy.map(\.id)).count
    }

    /// Every kept task back on the queue.
    func reviewKept() {
        later = []
        scheduled = [:]
        rolled = [:]
    }
}

extension NextLibrary {
    /// The Inbox's queue as this triage pass leaves it.
    func inboxQueue(triage: TriageSession, closing: Set<UUID>) -> [Block] {
        inboxQueue(kept: kept(by: triage), closing: closing)
    }

    /// The lists' undated tasks as No date's pass leaves them, in the lists'
    /// order; `blocks` are the documents' non-trashed blocks.
    func undatedQueue(blocks: [Block], triage: TriageSession, closing: Set<UUID>) -> [Block] {
        undatedQueue(blocks: blocks, kept: kept(by: triage), closing: closing)
    }

    /// How many cards No date's pass has left.
    func undatedCount(triage: TriageSession, closing: Set<UUID>) -> Int {
        undatedCount(kept: kept(by: triage), closing: closing)
    }

    /// What `triage` keeps off its queue. The tasks' dates are looked up in
    /// one dictionary, made only once a dated card asks, not by searching
    /// every task for each card.
    func kept(by triage: TriageSession) -> Set<UUID> {
        var dueDates: [UUID: Date]?
        return triage.kept { id in
            let dates = dueDates ?? Dictionary(tasks.compactMap { task in task.dueDate.map { (task.id, $0) } },
                                               uniquingKeysWith: { first, _ in first })
            dueDates = dates
            return dates[id]
        }
    }
}

extension PhoneEnvironment {
    /// The pass dealing `mode`'s cards.
    func triage(for mode: TriageMode) -> TriageSession {
        switch mode {
        case .inbox: triage
        case .undated: undatedTriage
        }
    }
}
