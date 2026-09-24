//
//  WidgetActions.swift
//  Shared between the app and the widget extension.
//

import Foundation
import WidgetKit

/// Something a widget button or checkbox asked Openlist to do.
nonisolated struct WidgetAction: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Pause and Resume say which they were, so one the timer has since
        /// moved past does nothing, rather than the opposite.
        case complete, reopen, startWork, pauseWork, resumeWork, finishWork

        /// Start, Pause and Resume answer the timer as the widget showed it.
        /// Done completes the task whatever the timer has done since, as a tick does.
        var answersTimer: Bool { self == .startWork || self == .pauseWork || self == .resumeWork }
    }

    var id = UUID()
    var kind: Kind
    var taskID: UUID
    /// The occurrence the widget showed. A repeat that rolled on since is left alone.
    var occurrenceID: UUID?
    var createdAt: Date = .now

    /// Where `actions` takes back the tick or untick at `index`: the next
    /// action on the same task, when it's the opposite one on the same
    /// occurrence. The app skips such a pair while the task is still as the
    /// first found it, and the widget lays neither over the snapshot, so a task
    /// ticked and unticked while Openlist was quit keeps its place, its slot
    /// and its history, as if neither had been made.
    static func takingBack(_ index: Int, in actions: [WidgetAction]) -> Int? {
        let action = actions[index]
        let opposite: Kind
        switch action.kind {
        case .complete: opposite = .reopen
        case .reopen: opposite = .complete
        case .startWork, .pauseWork, .resumeWork, .finishWork: return nil
        }
        guard let next = actions[(index + 1)...].firstIndex(where: { $0.taskID == action.taskID }),
              actions[next].kind == opposite, actions[next].occurrenceID == action.occurrenceID else { return nil }
        return next
    }

    /// The pair both sides skip: what takes back the tick or untick at `index`,
    /// while the task is still as that one found it, open for a tick and done
    /// for an untick. The app asks with the task, the widget with its snapshot.
    static func takingBack(_ index: Int, in actions: [WidgetAction], whileCompleted isCompleted: Bool) -> Int? {
        guard isCompleted == (actions[index].kind == .reopen) else { return nil }
        return takingBack(index, in: actions)
    }
}

/// Runs widget actions wherever the intent happens to run.
///
/// Inside the app the environment registers a performer that applies the action
/// straight away. In the widget extension there is none, so the action is queued
/// for the app, and the widgets show it as done in the meantime.
@MainActor
enum WidgetActionDispatcher {
    static var performer: ((WidgetAction) async -> Void)?

    static func dispatch(_ action: WidgetAction) async {
        if let performer {
            await performer(action)
        } else {
            WidgetActionQueue.enqueue(action)
            // The system reloads only the widget that was tapped. Every other
            // one showing the task lays the queue over the snapshot too, as
            // they all change together when the app publishes.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

/// Actions waiting for the app, one file each in the shared container.
///
/// One file per action means neither process ever rewrites what the other may
/// be reading, so the queue needs no coordination: the widget only adds files,
/// the app only removes them.
nonisolated enum WidgetActionQueue {
    static var directoryURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("widget-actions", isDirectory: true)
    }

    static func enqueue(_ action: WidgetAction) {
        guard let directory = directoryURL else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(action) else { return }
        // The time first, so a name sort is the order the actions were made in.
        let stamp = String(format: "%.3f", action.createdAt.timeIntervalSinceReferenceDate)
        let url = directory.appendingPathComponent("\(stamp)-\(action.id.uuidString).json")
        try? data.write(to: url, options: .atomic)
    }

    /// Every queued action, oldest first.
    static func pending() -> [(url: URL, action: WidgetAction)] {
        guard let directory = directoryURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return urls.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let action = try? decoder.decode(WidgetAction.self, from: data) else { return nil }
                return (url, action)
            }
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes files that aren't readable actions, once they're old enough not
    /// to be one still being written.
    static func removeUnreadable(keeping readable: Set<URL>, olderThan age: TimeInterval = 60) {
        guard let directory = directoryURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for url in urls where !readable.contains(url) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date.now.timeIntervalSince(modified) > age { remove(url) }
        }
    }
}
