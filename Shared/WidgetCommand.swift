//
//  WidgetCommand.swift
//  Shared between the app and the widget extension.
//

import Foundation

/// Something a widget button asks the app to do.
///
/// Widget intents prefer to run inside the app, where they are applied at once
/// through `WidgetCommandRouter`. If the system ever performs one in the widget
/// extension instead, the command is appended to a queue in the App Group and
/// the app applies it the next time it drains (on launch, on activation, or when
/// `WidgetCommandSignal` wakes it). The widget draws queued commands on top of
/// the snapshot so a tap never looks ignored while it waits.
nonisolated struct WidgetCommand: Codable, Equatable, Identifiable, Sendable {
    enum Action: String, Codable, Sendable {
        /// Complete one task occurrence.
        case complete
        /// Reopen a completed task.
        case reopen
        /// Start recording work on a task occurrence.
        case startWork
        /// Pause the running work session.
        case pauseWork
        /// Resume the paused work session.
        case resumeWork
        /// Complete the task being worked on.
        case finishWork
    }

    var id = UUID()
    var action: Action
    var taskID: UUID?
    var occurrenceID: UUID?
    var issuedAt = Date.now

    /// How long Start, Pause and Resume stay good for. They are about the
    /// moment of the tap: replayed later, a Start would record time nobody
    /// worked, from a launch hours on, and a Pause would stop work begun since.
    /// A queue drained by the extension's signal is well inside this; one left
    /// for the next launch is not, and the app already paused its work on quit.
    static let workWindow: TimeInterval = 2 * 60

    /// Whether the app still acts on this command at `now`. Ticks keep for the
    /// queue's lifetime, since their occurrence already guards against a stale
    /// tap, and no longer: the app drops them then, so a widget still drawing
    /// one would show a tick that never lands. The widget draws only commands
    /// the app will apply, so an expired Start never shows a clock that is not
    /// running. The work window holds on both sides of the tap: a clock set
    /// back since dates it in the future, which makes it no fresher.
    func isCurrent(at now: Date) -> Bool {
        guard WidgetCommandQueue.keeps(self, at: now) else { return false }
        return switch action {
        case .startWork, .pauseWork, .resumeWork: abs(now.timeIntervalSince(issuedAt)) <= Self.workWindow
        case .complete, .reopen, .finishWork: true
        }
    }

    /// The first moment `isCurrent` is false, so a timeline can stop drawing
    /// the command then instead of at its next reload. The work window
    /// includes its last second.
    var expiry: Date {
        switch action {
        case .startWork, .pauseWork, .resumeWork: issuedAt.addingTimeInterval(Self.workWindow + 1)
        case .complete, .reopen, .finishWork: issuedAt.addingTimeInterval(WidgetCommandQueue.lifetime)
        }
    }
}

/// Hands commands to the app when an intent runs in the app's own process.
@MainActor
enum WidgetCommandRouter {
    /// Installed by the app at launch. `nil` inside the widget extension.
    /// Returns once the change is saved and the snapshot rewritten, so the
    /// timeline reload that follows an intent already shows the result.
    static var handler: ((WidgetCommand) async -> Void)?

    /// Applies the command in-process when the app is the one running the
    /// intent. Returns `false` when there is no app to hand it to.
    static func dispatch(_ command: WidgetCommand) async -> Bool {
        guard let handler else { return false }
        await handler(command)
        return true
    }
}

/// Commands waiting for the app, persisted in the App Group.
nonisolated enum WidgetCommandQueue {
    /// Stale commands are dropped rather than replayed hours later.
    static let lifetime: TimeInterval = 6 * 3600

    /// Whether a command is still young enough to keep at `now`. One rule
    /// for the file and for the widget's overlay, so the widget stops drawing
    /// a tap at the moment the app would drop it.
    static func keeps(_ command: WidgetCommand, at now: Date) -> Bool {
        now.timeIntervalSince(command.issuedAt) < lifetime
    }

    static var url: URL? {
        AppGroup.containerURL?.appendingPathComponent("widget-commands.json")
    }

    static func append(_ command: WidgetCommand) {
        update { commands in
            // A newer tick, untick or Done on the same task supersedes an
            // unapplied older one, so toggling twice leaves a single, final
            // intent.
            if let taskID = command.taskID {
                commands.removeAll { $0.taskID == taskID && conflicts($0.action, command.action) }
            }
            commands.append(command)
        }
    }

    /// Commands not yet applied, oldest first.
    static func pending(now: Date = .now) -> [WidgetCommand] {
        guard let url else { return [] }
        var result: [WidgetCommand] = []
        coordinate(url, writing: false) { url in
            result = read(url).filter { keeps($0, at: now) }
        }
        return result
    }

    /// Forgets commands once the app has applied them.
    static func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        update { commands in commands.removeAll { ids.contains($0.id) } }
    }

    private static func conflicts(_ lhs: WidgetCommand.Action, _ rhs: WidgetCommand.Action) -> Bool {
        let taskActions: Set<WidgetCommand.Action> = [.complete, .reopen, .finishWork]
        return taskActions.contains(lhs) && taskActions.contains(rhs)
    }

    private static func update(_ change: (inout [WidgetCommand]) -> Void) {
        guard let url else { return }
        coordinate(url, writing: true) { url in
            var commands = read(url).filter { keeps($0, at: .now) }
            change(&commands)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            if commands.isEmpty {
                try? FileManager.default.removeItem(at: url)
            } else if let data = try? encoder.encode(commands) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static func read(_ url: URL) -> [WidgetCommand] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode([WidgetCommand].self, from: data)) ?? []
    }

    /// The app and the extension are separate processes; file coordination
    /// keeps one side's read-modify-write from losing the other's command.
    private static func coordinate(_ url: URL, writing: Bool, _ body: (URL) -> Void) {
        var error: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        if writing {
            coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &error, byAccessor: body)
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &error, byAccessor: body)
        }
    }
}

/// A cross-process nudge telling a running app that commands are waiting.
nonisolated enum WidgetCommandSignal {
    /// Prefixed with the App Group, the namespace a sandboxed process may use.
    static var name: String { "\(AppGroup.identifier).widget-commands" }

    static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }
}
