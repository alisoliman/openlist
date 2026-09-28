import Foundation
import MCP
import OpenlistMCP

enum OpenlistMCPTool: String, CaseIterable {
    case listLists = "openlist_list_lists"
    case getList = "openlist_get_list"
    case listTasks = "openlist_list_tasks"
    case getTask = "openlist_get_task"
    case listLabels = "openlist_list_labels"
    case createList = "openlist_create_list"
    case updateList = "openlist_update_list"
    case createTask = "openlist_create_task"
    case updateTask = "openlist_update_task"
    case setTaskCompleted = "openlist_set_task_completed"
    case moveTask = "openlist_move_task"
    case appendBlock = "openlist_append_block"
    case createLabel = "openlist_create_label"
    case listCalendar = "openlist_list_calendar"
    case scheduleTask = "openlist_schedule_task"
    case unscheduleTask = "openlist_unschedule_task"
    case updateBlock = "openlist_update_block"
    case trashBlock = "openlist_trash_block"

    var isReadOnly: Bool {
        switch self {
        case .listLists, .getList, .listTasks, .getTask, .listLabels, .listCalendar: true
        default: false
        }
    }

    static func catalog(allowsWrites: Bool) -> [MCPTool] {
        allCases.filter { allowsWrites || $0.isReadOnly }.map(\.definition)
    }

    var definition: MCPTool {
        let title = MCPField.text("Literal title; dates and #labels are not parsed.", min: 1, max: 1_000)
        let listID = MCPField.uuid("List ID returned by openlist_list_lists.")
        let taskID = MCPField.uuid("Task ID returned by a read tool.")
        let blockID = MCPField.uuid("Block ID returned by openlist_get_list or openlist_get_task.")
        let parentID = MCPField.uuid("Optional parent task or list item in the destination list, as the list document nests lines: two levels deep at most. Null means the document root.", nullable: true)
        let note = MCPField.text("Plain-text task note. An empty string clears it.", max: 100_000)
        let labelIDs = MCPField.array(MCPField.uuid("An existing label ID."), max: 100)
        let expected = MCPField.text("Optional updated_at value from a read. Rejects a stale edit; recommended when completing a repeating task.", max: 40)
        let taskFields: [String: MCPValue] = [
            "title": title,
            "note": note,
            "due_date": MCPField.text("YYYY-MM-DD in the Mac's time zone, or RFC 3339 timestamp with a time zone. Null clears the due date and reminder.", max: 40, nullable: true),
            "reminder_at": MCPField.text("RFC 3339 timestamp with a time zone, or null to clear.", max: 40, nullable: true),
            "priority": MCPField.integer("0 = none, 1 = low, 2 = medium, 3 = high.", min: 0, max: 3),
            "starred": MCPField.boolean("Whether the task is starred."),
            "label_ids": labelIDs,
            "duration_minutes": MCPField.integer("How long the task takes, which the calendar plans for. Null returns to the default in Settings > Calendar.",
                                                 min: 1, max: 40_320, nullable: true),
            "repeat": MCPField.repeatRule,
            "planned_for_today": MCPField.boolean("Pick the task for today, as the app's Plan for today does, or unpick it. Unpicking also ends a deferral."),
            "deferred_until": MCPField.text("YYYY-MM-DD, today or later: the task's work waits for that day, which picks it for then, and its calendar slots come off. Null ends the deferral. Not with planned_for_today.",
                                            max: 10, nullable: true),
            "keep_together": MCPField.boolean("Plan the remaining work as one uninterrupted session instead of splitting it."),
            "track_away": MCPField.boolean("Keep recording work while the Mac is locked or asleep."),
        ]
        let properties: [String: MCPValue]
        let required: [String]
        let description: String

        switch self {
        case .listLists:
            properties = MCPField.page.merging([
                "include_archived": MCPField.boolean("Include archived lists. Default false."),
                "query": MCPField.text("Case-insensitive title or summary search.", max: 1_000),
            ]) { _, new in new }
            required = []
            description = "List Openlist documents, including the system Inbox. Returns IDs, metadata, and pagination. Excludes archived lists by default."
        case .getList:
            properties = MCPField.page.merging(["list_id": listID]) { _, new in new }
            required = ["list_id"]
            description = "Read a list and its document blocks in outline order, including notes, completed tasks and collapsed descendants. Parent IDs and depth preserve nesting. Archived lists are readable by ID. Follow next_offset for remaining blocks."
        case .listTasks:
            properties = MCPField.page.merging([
                "list_id": listID,
                "query": MCPField.text("Case-insensitive title or task-note search.", max: 1_000),
                "status": MCPField.choice(["open", "completed", "all"], "Completion filter. Default open."),
                "view": MCPField.choice(["all", "today", "overdue", "starred"], "Default all. Today includes open overdue, due-today, planned-for-today and starred tasks, and completed-today tasks when status includes completed, matching the app."),
                "include_archived": MCPField.boolean("Include tasks in archived lists. Default false."),
                "label_id": MCPField.uuid("Filter by an existing label ID."),
            ]) { _, new in new }
            required = []
            description = "Find tasks across lists or within one list. Defaults to open tasks in active lists, including Inbox and subtasks. Returns task IDs, metadata, local time zone and pagination."
        case .getTask:
            properties = MCPField.page.merging(["task_id": taskID]) { _, new in new }
            required = ["task_id"]
            description = "Read a task's title, note, scheduling, labels, recurrence and descendants (the subtasks and list items under it in its list document), including collapsed or completed content. Follow next_offset for remaining descendants."
        case .listLabels:
            properties = MCPField.page
            required = []
            description = "List label IDs and names for task filters and label_ids updates."
        case .createList:
            properties = [
                "title": title,
                "summary": MCPField.text("List description.", max: 100_000),
            ]
            required = ["title"]
            description = "Create a list in the app's default sidebar section. Requires write access. Does not create tasks."
        case .updateList:
            properties = [
                "list_id": listID, "title": title, "expected_updated_at": expected,
                "summary": MCPField.text("List description. Empty clears it.", max: 100_000),
                "is_archived": MCPField.boolean("Archive or restore the list. Archiving hides its tasks from active views and cancels their reminders without deleting content."),
                "hours": MCPField.choice(["work", "personal"], "Which hours in Settings > Calendar the list's tasks are planned in."),
            ]
            required = ["list_id"]
            description = "Rename a list, change its summary, or archive/restore it. Supply at least one changed field. The Inbox cannot be renamed or archived. No permanent deletion."
        case .createTask:
            properties = taskFields.merging(["list_id": listID, "parent_id": parentID]) { _, new in new }
            required = ["title"]
            description = "Create a task with literal text and explicit metadata. Omitted list_id uses Inbox (or the parent's list when parent_id is supplied). Optional parent_id creates a subtask under a task or list item, two levels deep at most. Archived destinations, completed ancestors and deeper nesting are rejected."
        case .updateTask:
            properties = taskFields.merging(["task_id": taskID, "expected_updated_at": expected]) { _, new in new }
            required = ["task_id"]
            description = "Update only supplied task fields. Preserves inline title styling and existing recurrence. label_ids replaces the whole label set; [] clears it. Dates/reminders accept null to clear. Use separate completion/move tools for those actions."
        case .setTaskCompleted:
            properties = [
                "task_id": taskID, "completed": MCPField.boolean("True completes the current occurrence; false reopens a completed task."),
                "expected_updated_at": expected,
            ]
            required = ["task_id", "completed"]
            description = "Complete or reopen a task using the app's rules. Completing a parent completes its subtasks. A repeating task advances to its next occurrence and resets subtasks instead of staying completed: inspect the returned state. Repeating completion is NOT idempotent; supply expected_updated_at and re-read after an uncertain response rather than retrying blindly."
        case .moveTask:
            properties = [
                "task_id": taskID, "list_id": listID, "parent_id": parentID,
                "expected_updated_at": expected,
            ]
            required = ["task_id", "list_id"]
            description = "Move a task and all its descendants to the end of a destination list, or under parent_id, a task or list item. Omit parent_id to move to the root. Rejects cycles, archived destinations, completed ancestors, and a parent that would put the task or the lines under it more than two levels deep."
        case .appendBlock:
            properties = [
                "list_id": listID, "parent_id": parentID,
                "text": MCPField.text("Literal block text; may be empty only for a divider.", max: 100_000),
                "kind": MCPField.choice(["paragraph", "heading1", "heading2", "heading3", "bullet", "numbered", "quote", "code", "divider"], "Default paragraph. Use openlist_create_task for tasks. Under a parent_id, only bullet or numbered."),
            ]
            required = ["list_id", "text"]
            description = "Append a block to a list document, or a list item under a task or list item. Supports paragraphs, headings, bullets, numbered items, quotes, code and dividers at the document root; under a parent, only bullets and numbered items, two levels deep at most, as the list document nests them. Does not read or write attachment files."
        case .createLabel:
            properties = ["name": MCPField.text("Label name, optionally prefixed with #.", min: 1, max: 80)]
            required = ["name"]
            description = "Find or create a label by name (case-insensitive). Returns its ID for label_ids. Does not attach it to a task."
        case .listCalendar:
            properties = [
                "start_date": MCPField.text("First day, YYYY-MM-DD in the Mac's time zone. Default today.", max: 10),
                "days": MCPField.integer("How many days from start_date. Default 7.", min: 1, max: 31),
            ]
            required = []
            description = "Read the calendar as the app draws it: each task's planned slots and, while Openlist runs, the busy times of the Mac's calendars. Use it to find free time before openlist_schedule_task."
        case .scheduleTask:
            properties = [
                "task_id": taskID, "expected_updated_at": expected,
                "start": MCPField.text("RFC 3339 timestamp with a time zone, not in the past. Omit to take the next free slot around busy times and other planned work, inside the list's hours, this week or next.", max: 40),
                "duration_minutes": MCPField.integer("The slot's length. Default the task's duration.", min: 5, max: 1_440),
            ]
            required = ["task_id"]
            description = "Put an open task on the calendar at start, or in the next free slot, as the app's Plan does. Replaces the task's other slots. Its due date and whether it's picked for today stay as they are."
        case .unscheduleTask:
            properties = [
                "task_id": taskID, "expected_updated_at": expected,
                "slot_id": MCPField.uuid("One slot from calendar_slots to take off. Omit to take off every slot."),
            ]
            required = ["task_id"]
            description = "Take a task's planned slots off the calendar. The task, its due date and whether it's picked for today stay as they are."
        case .updateBlock:
            properties = [
                "block_id": blockID, "expected_updated_at": expected,
                "text": MCPField.text("The line's new literal text.", min: 1, max: 100_000),
                "kind": MCPField.choice(["paragraph", "heading1", "heading2", "heading3", "bullet", "numbered", "quote", "code", "task"],
                                        "Turn the line into another kind. Headings, paragraphs, quotes and code stay at the document root with nothing under them; task turns the line into an open task."),
            ]
            required = ["block_id"]
            description = "Edit a document line that isn't a task: its text or its kind. Use openlist_update_task for tasks."
        case .trashBlock:
            properties = ["block_id": blockID, "expected_updated_at": expected]
            required = ["block_id"]
            description = "Move a task or document line, with everything under it, to Trash. It can be restored from Trash in the app; nothing is erased."
        }

        let additive = [.createList, .createTask, .appendBlock, .createLabel].contains(self)
        let idempotent = ![.createList, .createTask, .appendBlock, .setTaskCompleted].contains(self)
        return MCPTool(
            name: rawValue,
            description: description,
            inputSchema: .object([
                "type": "object",
                "properties": .object(properties),
                "required": .array(required.map(MCPValue.string)),
                "additionalProperties": false,
            ]),
            annotations: .init(
                readOnlyHint: isReadOnly,
                destructiveHint: !isReadOnly && !additive,
                idempotentHint: idempotent,
                openWorldHint: false
            )
        )
    }
}

private enum MCPField {
    static let page: [String: MCPValue] = [
        "limit": integer("Maximum items to return. Default 100; reduce for large documents.", min: 1, max: 200),
        "offset": integer("Zero-based offset. Default 0; use next_offset from the previous result.", min: 0, max: Int.max),
    ]

    static func text(_ description: String, min: Int = 0, max: Int, nullable: Bool = false) -> MCPValue {
        .object([
            "type": nullable ? ["string", "null"] : "string",
            "description": .string(description),
            "minLength": .int(min), "maxLength": .int(max),
        ])
    }

    static func uuid(_ description: String, nullable: Bool = false) -> MCPValue {
        var schema = text(description, min: 36, max: 36, nullable: nullable).objectValue ?? [:]
        schema["format"] = "uuid"
        return .object(schema)
    }

    static func boolean(_ description: String) -> MCPValue {
        .object(["type": "boolean", "description": .string(description)])
    }

    static func integer(_ description: String, min: Int, max: Int, nullable: Bool = false) -> MCPValue {
        .object(["type": nullable ? ["integer", "null"] : "integer", "description": .string(description),
                 "minimum": .int(min), "maximum": .int(max)])
    }

    /// A repeat rule as openlist_get_task returns it, or null to stop repeating.
    static let repeatRule: MCPValue = .object([
        "type": ["object", "null"],
        "description": "Repeat rule, as openlist_get_task returns it; null stops repeating. A task without a due date gets today's.",
        "properties": .object([
            "frequency": choice(["daily", "weekly", "monthly", "yearly"], "How often it repeats."),
            "interval": integer("Every how many days, weeks, months or years. Default 1.", min: 1, max: 365),
            "weekdays": .object([
                "type": "array", "description": "Weekly rules only: the days it falls on, 1 = Sunday … 7 = Saturday. Default the due date's weekday.",
                "items": integer("A weekday, 1 = Sunday … 7 = Saturday.", min: 1, max: 7), "maxItems": 7, "uniqueItems": true,
            ]),
            "day_of_month": integer("Monthly rules only. Default the due date's day.", min: 1, max: 31),
            "anchor": choice(["dueDate", "completionDate"], "dueDate repeats on schedule; completionDate counts from when it's done. Default dueDate."),
            "end_date": text("YYYY-MM-DD: the last day it repeats.", max: 10),
            "occurrence_limit": integer("Stop after this many occurrences.", min: 1, max: 10_000),
        ]),
        "required": ["frequency"],
        "additionalProperties": false,
    ])

    static func choice(_ values: [String], _ description: String) -> MCPValue {
        .object(["type": "string", "description": .string(description), "enum": .array(values.map(MCPValue.string))])
    }

    static func array(_ item: MCPValue, max: Int) -> MCPValue {
        .object(["type": "array", "items": item, "maxItems": .int(max), "uniqueItems": true])
    }
}

struct MCPToolFailure: Error {
    let code: String
    let message: String

    static func invalid(_ message: String) -> Self { .init(code: "invalid_arguments", message: message) }
    static func missing(_ message: String) -> Self { .init(code: "not_found", message: message) }

    var result: MCPToolResult {
        .init(
            content: [.text(text: message, annotations: nil, _meta: nil)],
            structuredContent: .object(["error": .object(["code": .string(code), "message": .string(message)])]),
            isError: true
        )
    }
}

/// Runtime validation uses the advertised schema, so unknown fields cannot become silent no-ops.
struct MCPArguments {
    let values: [String: MCPValue]

    init(_ values: [String: MCPValue], for tool: OpenlistMCPTool) throws {
        self.values = values
        try Self.validate(.object(values), schema: tool.definition.inputSchema, path: "arguments")
    }

    subscript(_ key: String) -> MCPValue? { values[key] }
    func string(_ key: String) -> String? { values[key]?.stringValue }
    func bool(_ key: String) -> Bool? { values[key]?.boolValue }
    func integer(_ key: String) -> Int? { values[key]?.intValue }
    func uuid(_ key: String) -> UUID? { string(key).flatMap(UUID.init(uuidString:)) }

    func requireUUID(_ key: String) throws -> UUID {
        guard let value = uuid(key) else { throw MCPToolFailure.invalid("\(key) must be a UUID.") }
        return value
    }

    func nonempty(_ key: String) throws -> String {
        guard let value = string(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw MCPToolFailure.invalid("\(key) must not be blank.")
        }
        return value
    }

    func requirePatch(excluding keys: Set<String>) throws {
        guard !Set(values.keys).subtracting(keys).isEmpty else {
            throw MCPToolFailure.invalid("Supply at least one field to update.")
        }
    }

    private static func validate(_ value: MCPValue, schema: MCPValue, path: String) throws {
        guard let schema = schema.objectValue else {
            throw MCPToolFailure.invalid("Invalid tool schema.")
        }
        let types = schema["type"]?.arrayValue?.compactMap(\.stringValue)
            ?? schema["type"]?.stringValue.map { [$0] } ?? []
        let type: String
        switch value {
        case .null: type = "null"
        case .bool: type = "boolean"
        case .int: type = "integer"
        case .string: type = "string"
        case .array: type = "array"
        case .object: type = "object"
        default: type = "unsupported"
        }
        guard types.contains(type) else { throw MCPToolFailure.invalid("\(path) must be \(types.joined(separator: " or ")).") }
        if value == .null { return }
        if let choices = schema["enum"]?.arrayValue, !choices.contains(value) {
            throw MCPToolFailure.invalid("\(path) is not a supported value.")
        }
        switch value {
        case .string(let text):
            let length = text.unicodeScalars.count
            if let min = schema["minLength"]?.intValue, length < min {
                throw MCPToolFailure.invalid("\(path) is too short.")
            }
            if let max = schema["maxLength"]?.intValue, length > max {
                throw MCPToolFailure.invalid("\(path) is too long (maximum \(max) characters).")
            }
            if schema["format"] == "uuid", UUID(uuidString: text) == nil {
                throw MCPToolFailure.invalid("\(path) must be a UUID.")
            }
            if text.unicodeScalars.contains(where: { $0.value == 0 }) {
                throw MCPToolFailure.invalid("\(path) must not contain NUL characters.")
            }
        case .int(let number):
            if let min = schema["minimum"]?.intValue, number < min {
                throw MCPToolFailure.invalid("\(path) must be at least \(min).")
            }
            if let max = schema["maximum"]?.intValue, number > max {
                throw MCPToolFailure.invalid("\(path) must be at most \(max).")
            }
        case .array(let items):
            if let max = schema["maxItems"]?.intValue, items.count > max {
                throw MCPToolFailure.invalid("\(path) contains too many items.")
            }
            if schema["uniqueItems"] == true, Set(items).count != items.count {
                throw MCPToolFailure.invalid("\(path) must not contain duplicates.")
            }
            if let itemSchema = schema["items"] {
                for (index, item) in items.enumerated() {
                    try validate(item, schema: itemSchema, path: "\(path)[\(index)]")
                }
            }
        case .object(let fields):
            let properties = schema["properties"]?.objectValue ?? [:]
            let required = schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
            for key in required where fields[key] == nil {
                throw MCPToolFailure.invalid("\(path).\(key) is required.")
            }
            for (key, field) in fields {
                guard let fieldSchema = properties[key] else {
                    throw MCPToolFailure.invalid("Unknown field \(path).\(key).")
                }
                try validate(field, schema: fieldSchema, path: "\(path).\(key)")
            }
        default: break
        }
    }
}

enum MCPDates {
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        // Keep sub-millisecond updates distinct for optimistic concurrency.
        let seconds = floor(date.timeIntervalSinceReferenceDate)
        let fraction = Int(((date.timeIntervalSinceReferenceDate - seconds) * 1_000_000_000).rounded())
        let whole = formatter.string(from: Date(timeIntervalSinceReferenceDate: seconds))
        return String(whole.dropLast()) + String(format: ".%09dZ", fraction)
    }

    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    static func parse(_ text: String, allowsDay: Bool = true) throws -> (date: Date, includesTime: Bool) {
        if allowsDay, text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
           let date = dayFormatter.date(from: text), day(date) == text {
            return (date, false)
        }
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else {
            throw MCPToolFailure.invalid("Use a valid YYYY-MM-DD date or RFC 3339 timestamp with an explicit time zone.")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        formatter.dateFormat = text.contains(".") ? "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSSXXXXX" : "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        guard let date = formatter.date(from: text) else {
            throw MCPToolFailure.invalid("The timestamp is not a valid calendar date.")
        }
        return (date, true)
    }

    /// A YYYY-MM-DD day, never a timestamp.
    static func parseDay(_ text: String) throws -> Date {
        let parsed = try parse(text)
        guard !parsed.includesTime else { throw MCPToolFailure.invalid("Use a YYYY-MM-DD date.") }
        return parsed.date
    }

    private static var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}
