import Foundation

struct TaskCaptureRequest: Identifiable {
    let id = UUID()
    var text = ""
    var suggestedListID: UUID?
    var plansForToday = false
    /// A list's "Add to …": the capture starts in the suggested list, and a
    /// request arriving while a draft is on screen moves the draft there.
    /// A user-selected destination still wins.
    var startsInSuggestedList = false
    /// A list's Tasks view appends at the document root, where its add row
    /// sits, so capture for it does too; display position is never used. The
    /// Inbox never asks: its captures are prepended from everywhere. See
    /// `appendsToRoot(of:suggested:)` for when the request is honoured.
    var appendsToSuggestedList = false
    /// Capture from a Today screen, such as the Today widget's New task: a task
    /// typed without a date is due today, so it shows where it was added from.
    /// It still files into the Inbox, as New task on the app's Today does.
    var dueTodayWhenUndated = false

    /// Whether a task typed without a date is due today: the request asks for
    /// it, or new tasks go to Today. A task planned for today stays undated.
    func undatedTaskIsDueToday(newTasksGoTo destination: AppSettings.DefaultDestination) -> Bool {
        !plansForToday && (dueTodayWhenUndated || destination == .today)
    }

    /// Whether a task saved into `destination` goes at the end of its document.
    /// `suggested` is the suggested list as the store resolves it now.
    ///
    /// Only while the task still goes into the suggested list, and never into
    /// the Inbox, as capture in the window appends only into the list whose
    /// Tasks view is on screen. Picking another list, or falling back to the
    /// Inbox because the suggested one was archived or deleted, prepends as
    /// every other capture does.
    func appendsToRoot(of destination: TaskList?, suggested: TaskList?) -> Bool {
        guard appendsToSuggestedList, let destination, let suggested else { return false }
        return destination.id == suggested.id && !destination.isSystemInbox
    }
}
