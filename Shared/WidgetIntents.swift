//
//  WidgetIntents.swift
//  Shared between the app and the widget extension.
//

import AppIntents
import Foundation

// The widget's buttons and checkboxes. They're compiled into both processes so
// the system can run each one wherever suits it; either way the action goes
// through `WidgetActionDispatcher`, which applies it inside the app or queues it
// for the app from the extension.

/// Ticks a task off, or reopens it, from a widget checkbox.
///
/// Runs wherever the system likes, the extension included, so the task is
/// ticked off without opening Openlist.
struct SetTaskCompletionIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description = IntentDescription("Ticks a task off, or reopens it, from an Openlist widget.")
    static let isDiscoverable = false

    @Parameter(title: "Task") var taskID: String
    @Parameter(title: "Occurrence") var occurrenceID: String
    @Parameter(title: "Completed") var value: Bool

    init() {}

    init(taskID: UUID, occurrenceID: UUID?) {
        self.taskID = taskID.uuidString
        self.occurrenceID = occurrenceID?.uuidString ?? ""
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskID) {
            await WidgetActionDispatcher.dispatch(WidgetAction(kind: value ? .complete : .reopen, taskID: id,
                                                               occurrenceID: UUID(uuidString: occurrenceID)))
        }
        return .result()
    }
}

// Work is only ever recorded by the running app, and these share state with the
// timer in its toolbar, so they ask to run in the app's process: in the
// background, as a ForegroundContinuableIntent did, without bringing it forward.
// From macOS 27 `allowedExecutionTargets` pins them there. Before it the system
// may still pick the extension, which queues them like a tick; one the app
// only finds after the timer has moved on is dropped, with a notice in the tray.

/// Up Next's Start.
struct StartWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Working"
    static let description = IntentDescription("Starts the timer on a task.")
    static let isDiscoverable = false
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    @available(macOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Task") var taskID: String
    @Parameter(title: "Occurrence") var occurrenceID: String

    init() {}

    init(taskID: UUID, occurrenceID: UUID?) {
        self.taskID = taskID.uuidString
        self.occurrenceID = occurrenceID?.uuidString ?? ""
    }

    func perform() async throws -> some IntentResult {
        await dispatchWork(.startWork, taskID: taskID, occurrenceID: occurrenceID)
        return .result()
    }
}

/// Up Next's Pause, and its Resume once paused. Which one the widget showed
/// travels with it: a widget behind the timer can't flip it the wrong way.
struct PauseWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or Resume Working"
    static let description = IntentDescription("Pauses the timer, or resumes paused work.")
    static let isDiscoverable = false
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    @available(macOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Task") var taskID: String
    @Parameter(title: "Occurrence") var occurrenceID: String
    /// Pause, or when false, Resume.
    @Parameter(title: "Pause") var pauses: Bool

    init() {}

    init(taskID: UUID, occurrenceID: UUID?, pauses: Bool) {
        self.taskID = taskID.uuidString
        self.occurrenceID = occurrenceID?.uuidString ?? ""
        self.pauses = pauses
    }

    func perform() async throws -> some IntentResult {
        await dispatchWork(pauses ? .pauseWork : .resumeWork, taskID: taskID, occurrenceID: occurrenceID)
        return .result()
    }
}

/// Up Next's Done: completes the task the timer is on.
struct FinishWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Finish Working"
    static let description = IntentDescription("Completes the task you're working on.")
    static let isDiscoverable = false
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]
    @available(macOS 27, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Task") var taskID: String
    @Parameter(title: "Occurrence") var occurrenceID: String

    init() {}

    init(taskID: UUID, occurrenceID: UUID?) {
        self.taskID = taskID.uuidString
        self.occurrenceID = occurrenceID?.uuidString ?? ""
    }

    func perform() async throws -> some IntentResult {
        await dispatchWork(.finishWork, taskID: taskID, occurrenceID: occurrenceID)
        return .result()
    }
}

private func dispatchWork(_ kind: WidgetAction.Kind, taskID: String, occurrenceID: String) async {
    guard let id = UUID(uuidString: taskID) else { return }
    await WidgetActionDispatcher.dispatch(WidgetAction(kind: kind, taskID: id, occurrenceID: UUID(uuidString: occurrenceID)))
}
