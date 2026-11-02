import Foundation
import Testing
@testable import OpenlistiOS

/// Where a released row goes: commits by distance alone, with the row as
/// far over as the finger; a flick only picks where an uncommitted row rests.
@MainActor
struct TaskSwipeMotionTests {
    /// A row on a 393 pt phone, inside the gutters: Trash is 176.5 pt away.
    private let width: CGFloat = 353

    @Test func trashNeedsTheRowToReachItNotJustTheFinger() {
        let trash = TaskSwipeMotion.trashDistance(width: width)
        let open = TaskSwipeMotion.shortcutsWidth
        // From the shortcuts, a trash-length drag only gets the row just past
        // the delete reveal: it shows Delete, and nothing is trashed.
        #expect(TaskSwipeMotion.result(translation: -trash, origin: open, width: width) == .delete)
        #expect(TaskSwipeMotion.result(translation: -(trash + open) + 1, origin: open, width: width) == .delete)
        #expect(TaskSwipeMotion.result(translation: -(trash + open), origin: open, width: width) == .trash)
        // From rest the two are the same distance.
        #expect(TaskSwipeMotion.result(translation: -trash, width: width) == .trash)
        #expect(TaskSwipeMotion.result(translation: -trash + 1, width: width) == .delete)
    }

    @Test func todayNeedsTheRowToReachItToo() {
        let today = TaskSwipeMotion.todayDistance(width: width)
        let delete = -TaskSwipeMotion.deleteWidth
        #expect(TaskSwipeMotion.result(translation: today, origin: delete, width: width) == .shortcuts)
        #expect(TaskSwipeMotion.result(translation: today - delete, origin: delete, width: width) == .today)
        // Still the finger's whole distance from the shortcuts.
        #expect(TaskSwipeMotion.result(translation: today - 1, origin: TaskSwipeMotion.shortcutsWidth, width: width) == .shortcuts)
    }

    @Test func aFlickOpensWhatADragOfTheSameLengthWouldNot() {
        #expect(TaskSwipeMotion.result(translation: 30, width: width) == .closed)
        #expect(TaskSwipeMotion.result(translation: 30, width: width, velocity: 800) == .shortcuts)
        #expect(TaskSwipeMotion.result(translation: -30, width: width) == .closed)
        #expect(TaskSwipeMotion.result(translation: -30, width: width, velocity: -800) == .delete)
        // A slow release keeps to where the finger left the row.
        #expect(TaskSwipeMotion.result(translation: 30, width: width, velocity: 50) == .closed)
    }

    @Test func aFlickBackClosesAnOpenRowWithoutOpeningTheOtherSide() {
        let open = TaskSwipeMotion.shortcutsWidth
        #expect(TaskSwipeMotion.result(translation: -60, origin: open, width: width) == .shortcuts)
        #expect(TaskSwipeMotion.result(translation: -60, origin: open, width: width, velocity: -800) == .closed)
        #expect(TaskSwipeMotion.result(translation: -40, origin: open, width: width, velocity: -3000) == .closed)
        #expect(TaskSwipeMotion.result(translation: 20, origin: -TaskSwipeMotion.deleteWidth, width: width,
                                       velocity: 3000) == .closed)
        // Dragged over to the other side, the row opens there as before.
        #expect(TaskSwipeMotion.result(translation: -160, origin: open, width: width) == .delete)
    }

    @Test func aFlickNeverCommits() {
        #expect(TaskSwipeMotion.result(translation: 100, width: width, velocity: 6000) == .shortcuts)
        #expect(TaskSwipeMotion.result(translation: -100, width: width, velocity: -6000) == .delete)
    }

    @Test func theProjectionIsAFastScrollViewsStop() {
        #expect(abs(TaskSwipeMotion.projection(of: 1000) - 99) < 0.001)
        #expect(abs(TaskSwipeMotion.projection(of: -500) + 49.5) < 0.001)
        #expect(TaskSwipeMotion.projection(of: 0) == 0)
    }
}
