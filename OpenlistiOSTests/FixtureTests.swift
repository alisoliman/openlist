//
//  FixtureTests.swift
//  OpenlistiOSTests
//

import Foundation
import SwiftData
import Testing
@testable import OpenlistiOS

/// The review fixture is the library the mockups show.
@MainActor
struct FixtureTests {
    @Test func listsAndOpenCounts() throws {
        let phone = try TestPhone(seeded: true)
        let lists = phone.store.allLists().filter { !$0.isSystemInbox }
        #expect(lists.map(\.title) == ["Weekend in Kyoto", "Home", "Reading", "Q3 planning", "Hiring loop"])
        #expect(lists.map(\.icon) == ["🗻", "🏡", "📚", "💼", "🎯"])
        let open = lists.map { list in phone.store.blocks(inList: list.id).filter { $0.isTask && !$0.isCompleted }.count }
        #expect(open == [7, 3, 2, 4, 3])
        #expect(Set(phone.store.allLabels().map(\.name)) == ["travel", "focus", "food"])
        #expect(phone.env.settings.firstWeekday == 2)
    }

    @Test func inboxHoldsSixCapturesAgedAsTheMockup() throws {
        let phone = try TestPhone(seeded: true)
        let inbox = try #require(phone.store.inboxList())
        let tasks = phone.store.blocks(inList: inbox.id).filter(\.isTask)
        #expect(tasks.count == 6)
        #expect(tasks.map { CompactText.age(of: $0.createdAt, now: TestClock.mockupNow) } == ["2h", "5h", "1d", "2d", "3d", "4d"])
    }

    /// "2 of 13 done": 11 open, 3 of them late, and two done today.
    @Test func todayHasTheMockupsTasks() throws {
        let phone = try TestPhone(seeded: true)
        let tasks = try phone.container.mainContext.fetch(FetchDescriptor<Block>()).filter { phone.store.block(id: $0.id) != nil }
        let agenda = TodayAgenda(tasks: tasks.filter(\.isTask), now: TestClock.mockupNow, order: .schedule)
        #expect(agenda.progress.done == 2)
        #expect(agenda.progress.total == 13)
        #expect(agenda.overdue.map(\.text) == ["Close out Q2 retro actions", "Reserve the Nishiki market tour",
                                               "Fix the dripping bathroom tap"])
        #expect(Set(agenda.starred.map(\.text)) == ["Book the ryokan", "Finish The Overstory"])
        #expect(Set(agenda.doneToday.map(\.text)) == ["Standup notes", "Reply to Kasuga about the tatami room"])
        #expect(agenda.planned.map(\.text) == ["Draft Q3 OKRs"])
    }

    @Test func draftQ3OKRsIsUnderWayWithFiftyMinutesLeft() throws {
        let phone = try TestPhone(seeded: true)
        let session = try #require(phone.store.workSessions().first { $0.endedAt == nil })
        #expect(session.title == "Draft Q3 OKRs")
        #expect(session.startedAt == TestClock.mockupNow.addingTimeInterval(-40 * 60))
        let task = try #require(phone.task("Draft Q3 OKRs"))
        #expect(task.schedulingEstimateMinutes == 90)
        #expect(task.priority == .high)
        let placement = try #require(phone.store.placements(taskID: task.id).first)
        #expect(placement.end.timeIntervalSince(TestClock.mockupNow) == 50 * 60)
    }

    @Test func trashHoldsThreeEntries() throws {
        let phone = try TestPhone(seeded: true)
        let entries = try phone.store.trashEntries()
        #expect(Set(entries.map(\.title)) == ["Prep board update slides (duplicate)", "Old packing list draft", "Try the new ramen place"])
        let slides = try #require(entries.first { $0.title == "Prep board update slides (duplicate)" })
        #expect(slides.metadata?.listTitle == "Q3 planning")
        #expect(slides.metadata?.deletedAt == TestClock.mockupNow.addingTimeInterval(-3 * 3600))
    }

    /// "6-day streak · 81 done in 12 weeks".
    @Test func activityHistoryMatchesTheHeatmap() throws {
        let phone = try TestPhone(seeded: true)
        let heatmap = try phone.store.activityHeatmap(now: TestClock.mockupNow, calendar: TestClock.calendar)
        #expect(heatmap.total == 81)
        #expect(heatmap.streak == 6)
        #expect(heatmap.days.count == 7 * 11 + 3)
    }
}
