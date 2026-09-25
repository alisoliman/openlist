//
//  WidgetIntents.swift
//  Shared between the app and the widget extension.
//

import AppIntents
import Foundation
import WidgetKit

// Widget buttons. They are compiled into both targets and ask to run in the
// app, where the store, the calendar and the work timer live; the app launches
// in the background if it is not already running. See `WidgetCommand` for the
// queued fallback used if the system performs one in the extension instead.

/// Ticks a task off, or reopens it.
struct ToggleTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let isDiscoverable = false
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Task") var taskID: String
    @Parameter(title: "Occurrence") var occurrenceID: String
    @Parameter(title: "Completed") var completed: Bool

    init() {}

    init(taskID: UUID, occurrenceID: UUID, completed: Bool) {
        self.taskID = taskID.uuidString
        self.occurrenceID = occurrenceID.uuidString
        self.completed = completed
    }

    func perform() async throws -> some IntentResult {
        await WidgetIntentPerformer.run(WidgetCommand(
            action: completed ? .complete : .reopen,
            taskID: UUID(uuidString: taskID),
            occurrenceID: UUID(uuidString: occurrenceID)
        ))
        return .result()
    }
}

/// Starts recording the planned block's task.
struct StartWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Work"
    static let isDiscoverable = false
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Task") var taskID: String
    @Parameter(title: "Occurrence") var occurrenceID: String

    init() {}

    init(taskID: UUID, occurrenceID: UUID) {
        self.taskID = taskID.uuidString
        self.occurrenceID = occurrenceID.uuidString
    }

    func perform() async throws -> some IntentResult {
        await WidgetIntentPerformer.run(WidgetCommand(
            action: .startWork,
            taskID: UUID(uuidString: taskID),
            occurrenceID: UUID(uuidString: occurrenceID)
        ))
        return .result()
    }
}

/// Pauses the running work session. Names the session the widget drew, so a
/// stale widget can never pause work that started since.
struct PauseWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Work"
    static let isDiscoverable = false
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Task") var taskID: String
    @Parameter(title: "Occurrence") var occurrenceID: String

    init() {}

    init(taskID: UUID, occurrenceID: UUID) {
        self.taskID = taskID.uuidString
        self.occurrenceID = occurrenceID.uuidString
    }

    func perform() async throws -> some IntentResult {
        await WidgetIntentPerformer.run(WidgetCommand(
            action: .pauseWork,
            taskID: UUID(uuidString: taskID),
            occurrenceID: UUID(uuidString: occurrenceID)
        ))
        return .result()
    }
}

/// Resumes the paused work session the widget drew.
struct ResumeWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Work"
    static let isDiscoverable = false
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Task") var taskID: String
    @Parameter(title: "Occurrence") var occurrenceID: String

    init() {}

    init(taskID: UUID, occurrenceID: UUID) {
        self.taskID = taskID.uuidString
        self.occurrenceID = occurrenceID.uuidString
    }

    func perform() async throws -> some IntentResult {
        await WidgetIntentPerformer.run(WidgetCommand(
            action: .resumeWork,
            taskID: UUID(uuidString: taskID),
            occurrenceID: UUID(uuidString: occurrenceID)
        ))
        return .result()
    }
}

/// Completes the task being worked on.
struct FinishWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Finish Work"
    static let isDiscoverable = false
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Task") var taskID: String
    @Parameter(title: "Occurrence") var occurrenceID: String

    init() {}

    init(taskID: UUID, occurrenceID: UUID) {
        self.taskID = taskID.uuidString
        self.occurrenceID = occurrenceID.uuidString
    }

    func perform() async throws -> some IntentResult {
        await WidgetIntentPerformer.run(WidgetCommand(
            action: .finishWork,
            taskID: UUID(uuidString: taskID),
            occurrenceID: UUID(uuidString: occurrenceID)
        ))
        return .result()
    }
}

nonisolated enum WidgetIntentPerformer {
    /// In the app, applies the command before returning. Anywhere else, queues
    /// it for the app and wakes it.
    static func run(_ command: WidgetCommand) async {
        if await WidgetCommandRouter.dispatch(command) { return }
        WidgetCommandQueue.append(command)
        WidgetCommandSignal.post()
        // The system reloads only the widget that was tapped. Every other one
        // showing the task draws the queue over the snapshot too, so they
        // change together, as they do when the app publishes.
        WidgetCenter.shared.reloadAllTimelines()
    }
}
