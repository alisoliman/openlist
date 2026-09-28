//
//  PhoneFixture.swift
//  OpenlistiOS
//

import Foundation
import SwiftData

/// The library the iPhone mockups show (docs/design/openlist-ios-companion),
/// seeded into an empty review-session library so screenshots and UI tests
/// open on Wednesday 23 September with "Draft Q3 OKRs" under way.
///
/// Only `PhoneEnvironment.bootstrap` calls it, behind the Mac's guard: a Debug
/// review session, iCloud off, nothing seeded yet and no content. Every date
/// is relative to `now`, which UI tests pin with `OpenlistFixtureNow`
/// (2026-09-23T10:40:00 gives the mockups' clock exactly). History that the
/// Store dates at the moment it's written (completions, trash, work) is
/// written through the Store and then moved back to when the mockups say it
/// happened.
@MainActor
enum PhoneFixture {
    /// The mockups' moment: Wednesday 23 September 2026, 10:40, with Draft Q3
    /// OKRs 40 minutes into its 90.
    static let mockupNow = "2026-09-23T10:40:00"

    /// Completions per day over the 12 weeks before today, Monday first, from
    /// the Activity mockup's heatmap. Today's two are the fixture's own tasks;
    /// the rest are history of tasks since erased. Sums to 81 with today's.
    static let heatmap: [Int] = [
        0, 1, 0, 2, 1, 0, 0, 1, 0, 3, 1, 0, 2, 0, 0, 2, 1, 0, 4, 1, 0, 1, 1, 0, 2, 0, 0, 1,
        0, 3, 2, 1, 0, 1, 0, 2, 0, 1, 0, 5, 1, 0, 0, 1, 2, 0, 1, 0, 3, 1, 0, 0, 2, 1, 4, 0,
        0, 2, 1, 3, 0, 1, 0, 1, 0, 2, 1, 0, 0, 2, 0, 1, 3, 0, 1, 2, 1, 1, 2, 2,
    ]

    /// The timeline mockup's meeting: Design sync, 14:00–15:00 today.
    static func meetings(now: Date, calendar: Calendar = .current) -> [FixedBusyTime] {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today) else { return [] }
        return [FixedBusyTime(id: "fixture-design-sync", title: "Design sync", start: start, end: start.addingTimeInterval(3600))]
    }

    struct Seeded {
        var kyoto: TaskList
        var home: TaskList
        var reading: TaskList
        var q3: TaskList
        var hiring: TaskList
        var draftOKRs: Block
        var workSession: WorkSession?
    }

    @discardableResult
    static func seed(into store: Store, settings: AppSettings? = nil, now: Date,
                     calendar: Calendar = .current) -> Seeded? {
        guard let inbox = store.inboxList() else { return nil }
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(dayOffset))!
        }
        // The mockups' week starts on Monday (Settings: "Week starts on Monday").
        settings?.firstWeekday = 2

        let section = store.defaultSection()
        var seeded: Seeded!
        var tasks: [String: Block] = [:]

        store.withoutLogging {
            let travel = store.findOrCreateLabel(named: "travel")
            travel?.accent = .teal
            let focus = store.findOrCreateLabel(named: "focus")
            focus?.accent = .violet
            let food = store.findOrCreateLabel(named: "food")
            food?.accent = .amber

            let kyoto = store.createList(title: "Weekend in Kyoto", icon: "🗻", accent: .violet, in: section)
            let home = store.createList(title: "Home", icon: "🏡", accent: .green, in: section)
            let reading = store.createList(title: "Reading", icon: "📚", accent: .amber, in: section)
            let q3 = store.createList(title: "Q3 planning", icon: "💼", accent: .blue, in: section)
            let hiring = store.createList(title: "Hiring loop", icon: "🎯", accent: .pink, in: section)

            @MainActor @discardableResult
            func task(_ title: String, in list: TaskList, due: Date? = nil, timed: Bool = false,
                      labels: [TaskLabel?] = [], starred: Bool = false, estimate: Int = 0,
                      created: Date? = nil) -> Block {
                let block = store.appendBlock(kind: .task, text: title, to: DocumentContext(listID: list.id))
                block.dueDate = due
                block.includesTime = timed
                block.labelIDs = labels.compactMap { $0?.id }
                block.isStarred = starred
                block.schedulingEstimateMinutes = estimate
                if let created { block.createdAt = created }
                tasks[title] = block
                return block
            }
            @MainActor @discardableResult
            func subtask(_ title: String, of parent: Block, due: Date? = nil, timed: Bool = false) -> Block {
                let block = store.insertChild(kind: .task, text: title, of: parent, at: .last)
                block.dueDate = due
                block.includesTime = timed
                tasks[title] = block
                return block
            }

            // Inbox: six captures, newest first, 2 hours to 4 days old.
            for (title, hours) in [("Send Jun the photos from Nara", 2), ("Cancel the gym trial before it renews", 5),
                                   ("Call the dentist back about the crown", 24), ("Look into a standing desk for the study", 48),
                                   ("Return the library books", 72), ("Gift ideas for Mika’s birthday", 96)] {
                task(title, in: inbox, created: now.addingTimeInterval(-Double(hours) * 3600))
            }

            // Weekend in Kyoto: 7 open, "1 done".
            task("Renew passports", in: kyoto, due: day(3), labels: [travel])
            let ryokan = task("Book the ryokan", in: kyoto, labels: [travel], starred: true)
            subtask("Compare Gion vs Arashiyama", of: ryokan)
            subtask("Email Kasuga about the tatami room", of: ryokan)
            subtask("Pay the ryokan deposit", of: ryokan, due: at(18), timed: true)
            task("Reserve the Nishiki market tour", in: kyoto, due: day(-2), labels: [travel, food])
            let planters = task("Ask Mika to water the planters", in: kyoto, due: day(0))
            var everyWednesday = Recurrence.weekly
            everyWednesday.weekdays = [calendar.component(.weekday, from: today)]
            planters.recurrence = everyWednesday
            task("Pick up JR passes at Kyoto Station", in: kyoto, due: day(4), labels: [travel])
            task("Reply to Kasuga about the tatami room", in: kyoto, labels: [travel])
            task("Old packing list draft", in: kyoto)

            // Home: 3 open.
            task("Fix the dripping bathroom tap", in: home, due: day(-1))
            task("Order new water filters", in: home, due: at(16, 30), timed: true, estimate: 10)
            task("Book the boiler service", in: home, due: day(9))
            task("Try the new ramen place", in: home)

            // Reading: 2 open.
            task("Finish The Overstory", in: reading, starred: true)
            task("Start Piranesi", in: reading)

            // Q3 planning: 4 open.
            let okrs = task("Draft Q3 OKRs", in: q3, labels: [focus], estimate: 90)
            okrs.note = "Keep it to three objectives. Pull last quarter’s numbers from the board deck."
            okrs.priority = .high
            okrs.selectedForDay = today
            task("Close out Q2 retro actions", in: q3, due: day(-3))
            task("Prep board update slides", in: q3, due: day(2), labels: [focus])
            task("Share the OKR draft with leads", in: q3)
            task("Standup notes", in: q3, due: day(0), estimate: 30)
            task("Prep board update slides (duplicate)", in: q3)

            // Hiring loop: 3 open.
            task("Write interview feedback for Priya", in: hiring, due: at(11, 30), timed: true, estimate: 20)
            task("Update the design role scorecard", in: hiring, due: at(13), timed: true, estimate: 30)
            task("Schedule the panel for Tomás", in: hiring, due: day(5))

            seeded = Seeded(kyoto: kyoto, home: home, reading: reading, q3: q3, hiring: hiring, draftOKRs: okrs)
        }
        store.save()

        // Today's plan: pinned slots, as the timeline mockup draws them.
        if let okrs = tasks["Draft Q3 OKRs"] {
            store.setPlacement(for: okrs, start: now.addingTimeInterval(-40 * 60),
                               end: now.addingTimeInterval(50 * 60), isPinned: true)
        }
        for (title, start, minutes) in [("Write interview feedback for Priya", at(11, 30), 20),
                                        ("Update the design role scorecard", at(13), 30),
                                        ("Order new water filters", at(16, 30), 10)] {
            if let task = tasks[title] {
                store.setPlacement(for: task, start: start, end: start.addingTimeInterval(Double(minutes) * 60), isPinned: true)
            }
        }

        // Done: yesterday's subtask, and today's two ("2 done today").
        complete(tasks["Compare Gion vs Arashiyama"], at: at(19, 10, dayOffset: -1), in: store)
        complete(tasks["Reply to Kasuga about the tatami room"], at: at(8, 28), in: store)
        complete(tasks["Standup notes"], at: at(9, 46), in: store,
                 planned: CompletionCalendarInterval(start: at(9, 15), end: at(9, 45)))

        // Trash: three, one of them from Home ("Restored to Home").
        trash(tasks["Try the new ramen place"], at: now.addingTimeInterval(-3 * 86400), in: store)
        trash(tasks["Old packing list draft"], at: now.addingTimeInterval(-86400), in: store)
        trash(tasks["Prep board update slides (duplicate)"], at: now.addingTimeInterval(-3 * 3600), in: store)

        insertHistory(into: store, lists: [seeded.kyoto, seeded.home, seeded.reading, seeded.q3, seeded.hiring],
                      now: now, calendar: calendar)

        // Work under way: Draft Q3 OKRs since 10:00, 50 minutes left of its 90.
        if let deviceID = store.calendarDeviceID, let okrs = tasks["Draft Q3 OKRs"],
           let session = store.startWorkSession(for: okrs, deviceID: deviceID, now: now.addingTimeInterval(-40 * 60)) {
            session.plannedIntervals = [CompletionCalendarInterval(start: now.addingTimeInterval(-40 * 60),
                                                                  end: now.addingTimeInterval(50 * 60))]
            session.lastHeartbeatAt = now
            seeded.workSession = session
            store.save()
        }
        return seeded
    }

    /// Completes `task` through the Store, then dates its history `date`.
    private static func complete(_ task: Block?, at date: Date, in store: Store,
                                 planned: CompletionCalendarInterval? = nil) {
        guard let task else { return }
        let id = task.id
        store.toggleCompletion(task, now: date)
        for event in events(for: id, in: store) where event.kind == .completed {
            event.timestamp = date
        }
        if let planned {
            for record in store.completionRecords(taskID: id) { record.plannedIntervals = [planned] }
        }
        store.save()
    }

    /// Moves `task` to Trash through the Store, then dates the entry `date`.
    private static func trash(_ task: Block?, at date: Date, in store: Store) {
        guard let task, store.trashBlocks([task]) else { return }
        if let data = task.trashMetadataData, var metadata = try? JSONDecoder().decode(TrashMetadata.self, from: data) {
            metadata.deletedAt = date
            task.trashMetadataData = try? JSONEncoder().encode(metadata)
        }
        for event in events(for: task.id, in: store) where event.kind == .deleted {
            event.timestamp = date
        }
        store.save()
    }

    private static func events(for taskID: UUID, in store: Store) -> [ActivityEvent] {
        (try? store.context.fetch(FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.blockID == taskID }))) ?? []
    }

    /// The heatmap's earlier completions: saved history of tasks done and since
    /// erased, which Activity counts as the Store's own completions are counted.
    private static func insertHistory(into store: Store, lists: [TaskList], now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        let weekday = (calendar.component(.weekday, from: today) + 5) % 7
        guard let weekStart = calendar.date(byAdding: .day, value: -weekday, to: today),
              let first = calendar.date(byAdding: .day, value: -7 * 11, to: weekStart) else { return }
        let titles = ["Water the herbs", "Send the invoice", "Book a haircut", "Answer Lena", "Tidy the desk",
                      "Read two chapters", "Pay the phone bill", "Plan the week", "Back up the laptop",
                      "Review the budget", "Call Grandma", "Clean the fridge", "Sort the receipts"]
        var index = 0
        for (offset, count) in heatmap.enumerated() {
            guard let date = calendar.date(byAdding: .day, value: offset, to: first), date < today else { continue }
            // Yesterday's subtask is one of its two, done through the Store.
            let fixtureDone = calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!) ? 1 : 0
            for slot in 0..<max(0, count - fixtureDone) {
                let list = lists[index % lists.count]
                let at = calendar.date(bySettingHour: 9 + (slot * 3 + index) % 10, minute: (index * 17) % 60,
                                       second: 0, of: date)!
                let event = ActivityEvent(kind: .completed, title: titles[index % titles.count], blockID: UUID(),
                                          listID: list.id, listTitle: list.displayTitle, listIcon: list.icon)
                event.timestamp = at
                event.change = TaskActivityChange(completionID: UUID(), completedAt: at,
                                                  completedOccurrenceID: UUID(), completionWasRecurring: false)
                store.context.insert(event)
                index += 1
            }
        }
        store.save()
    }
}
