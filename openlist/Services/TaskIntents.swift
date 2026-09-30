//
//  TaskIntents.swift
//  openlist
//

import AppIntents
import Foundation

/// How the app's intents reach the library, installed at launch by
/// `AppEnvironment` on the Mac and `PhoneEnvironment` on the iPhone, as
/// widget buttons reach it through `WidgetCommandRouter`. An intent can be
/// what launched the app, so `library` opens it first.
@MainActor
enum TaskIntentHost {
    /// The library, opened and ready.
    static var library: (() -> Store?)?
    /// Takes in tasks an intent added, as the capture does its own: one Undo
    /// and the fresh rows on the Mac, the tray on the iPhone.
    static var didAdd: (([Block], _ opened: [UUID]) -> Void)?
    /// Opens a screen as the app would a widget's link.
    static var open: ((WidgetLink) -> Void)?

    /// Tells Siri the lists there are, for "Add a task to <list> in Openlist".
    static func listsChanged() {
        OpenlistShortcuts.updateAppShortcutParameters()
    }
}

/// Adds tasks from what's said to Siri or typed in Shortcuts, read as voice
/// capture reads it: Apple Intelligence splits it into separate tasks where
/// this device has it, and each gets the list, day, time, repeat, labels,
/// priority and estimate said with it.
struct AddTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Tasks"
    static let description = IntentDescription(
        "Adds one or more tasks from what you say or type, such as “call mum tomorrow at 5 and buy milk on my groceries list”, each with its day, time, list, labels and priority.",
        categoryName: "Tasks")

    @Parameter(title: "Tasks", description: "What to add, in your own words.",
               requestValueDialog: IntentDialog("What should I add?"))
    var text: String

    @Parameter(title: "List", description: "Where tasks that don't name a list go. Inbox when not set.")
    var list: TaskListEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text)") {
            \.$list
        }
    }

    init() {}

    init(text: String, list: TaskListEntity? = nil) {
        self.text = text
        self.list = list
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        guard let store = TaskIntentHost.library?() else { throw TaskIntentError.libraryUnavailable }
        let vocabulary = SpokenCapture.Vocabulary(lists: store.allLists(), labels: store.allLabels())
        let heard = await VoiceTaskInterpreter().interpret(text, vocabulary: vocabulary, reference: .now)
        guard !heard.tasks.isEmpty else { throw TaskIntentError.nothingToAdd }
        let chosen = list.flatMap { store.list(id: $0.id) }.flatMap { $0.isEffectivelyArchived ? nil : $0 }
        let result = store.saveSpokenTasks(heard.tasks, destinationID: chosen?.id ?? store.inboxList()?.id)
        if !result.saved.isEmpty { TaskIntentHost.didAdd?(result.saved, result.opened) }
        if let error = result.error, result.saved.isEmpty { throw error }
        return .result(value: result.saved.map(\.text), dialog: IntentDialog(stringLiteral: Self.summary(result.saved, store: store)))
    }

    /// What Siri says back: the task, where it went and when it's due; or
    /// how many, and which.
    @MainActor
    static func summary(_ tasks: [Block], store: Store) -> String {
        let lists = Set(tasks.map(\.listID))
        let place = lists.count == 1 ? store.list(id: tasks[0].listID)?.displayTitle ?? "Inbox" : "\(lists.count) lists"
        guard tasks.count == 1, let task = tasks.first else {
            let titles = ListFormatter.localizedString(byJoining: tasks.map { "“\($0.text)”" })
            return "Added \(tasks.count) tasks to \(place): \(titles)."
        }
        let due = task.dueDate.map {
            ", due " + $0.formatted(date: .abbreviated, time: task.includesTime ? .shortened : .omitted)
        } ?? ""
        return "Added “\(task.text)” to \(place)\(due)."
    }
}

/// Opens capture listening for tasks to be said: for Siri, Spotlight, the
/// Action button and Shortcuts.
struct SayTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Say Tasks"
    static let description = IntentDescription("Opens Openlist listening for tasks to add.", categoryName: "Tasks")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        TaskIntentHost.open?(.captureVoice)
        return .result()
    }
}

enum TaskIntentError: Error, CustomLocalizedStringResourceConvertible {
    case libraryUnavailable, nothingToAdd

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .libraryUnavailable: "Openlist’s library isn’t open. Open Openlist and try again."
        case .nothingToAdd: "There was nothing to add."
        }
    }
}

/// A list tasks can be added to, for the List parameter and Siri's phrases.
struct TaskListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let defaultQuery = TaskListQuery()

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    init(_ list: TaskList) {
        id = list.id
        title = list.displayTitle
    }
}

/// The lists that take tasks, in sidebar order, found by name.
struct TaskListQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TaskListEntity] {
        lists().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [TaskListEntity] {
        let all = lists()
        if let id = SpokenCapture.list(named: string, in: all.map { ($0.id, $0.title) }) {
            return all.filter { $0.id == id }
        }
        return all.filter { $0.title.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TaskListEntity] {
        lists()
    }

    @MainActor
    private func lists() -> [TaskListEntity] {
        TaskIntentHost.library?()?.allLists().map(TaskListEntity.init) ?? []
    }
}

/// The phrases Siri knows Openlist by, with no set-up.
struct OpenlistShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTasksIntent(), phrases: [
            "Add tasks in \(.applicationName)",
            "Add a task in \(.applicationName)",
            "Add to \(.applicationName)",
            "New \(.applicationName) task",
            "Add a task to \(\.$list) in \(.applicationName)",
        ], shortTitle: "Add Tasks", systemImageName: "text.badge.plus")
        AppShortcut(intent: SayTasksIntent(), phrases: [
            "Say tasks in \(.applicationName)",
            "Talk to \(.applicationName)",
            "Capture with \(.applicationName)",
        ], shortTitle: "Say Tasks", systemImageName: "mic")
    }
}
