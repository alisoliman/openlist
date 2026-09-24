import Foundation
import MCP
import OpenlistMCP
import SwiftData

/// All MCP reads and edits stay on the context used by SwiftUI's queries.
@MainActor
final class MCPStoreAdapter {
    let store: Store

    init(store: Store) { self.store = store }

    func call(_ name: String, arguments: [String: MCPValue], allowsWrites: Bool) throws -> MCPToolResult {
        try Task.checkCancellation()
        do {
            guard let tool = OpenlistMCPTool(rawValue: name) else {
                throw MCPToolFailure.invalid("Unknown Openlist tool.")
            }
            guard tool.isReadOnly || allowsWrites else {
                throw MCPToolFailure(code: "read_only", message: "Write access is off. Enable Allow changes in Openlist Settings > AI Agents.")
            }
            let args = try MCPArguments(arguments, for: tool)
            let snapshot = try Snapshot(context: store.context)
            if tool.isReadOnly {
                return try result(execute(tool, args: args, snapshot: snapshot))
            }

            guard !store.isSavingSuspended else {
                throw MCPToolFailure(code: "busy", message: "An editor operation is in progress. Try again after it finishes.")
            }
            // Commit pending UI edits first, so rollback never discards the user's typing.
            try store.persistChanges()
            store.isSavingSuspended = true
            do {
                let response = try result(execute(tool, args: args, snapshot: snapshot))
                store.isSavingSuspended = false
                try store.persistChanges()
                return response
            } catch {
                store.isSavingSuspended = false
                if store.context.hasChanges {
                    store.context.rollback()
                    store.refreshAllReminders()
                }
                store.pendingActivity.removeAll()
                throw error
            }
        } catch let error as MCPToolFailure {
            return error.result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            store.persistenceError = "An AI agent operation could not be saved or read. \(error.localizedDescription)"
            return MCPToolFailure(
                code: "storage_error",
                message: "Openlist could not read or save this operation. Check the storage error in the app before retrying."
            ).result
        }
    }

    private func execute(_ tool: OpenlistMCPTool, args: MCPArguments, snapshot: Snapshot) throws -> MCPValue {
        switch tool {
        case .listLists:
            let lists = snapshot.lists.filter {
                (args.bool("include_archived") == true || !$0.isEffectivelyArchived)
                    && matches(args.string("query"), in: [$0.title, $0.summary])
            }
            return .object(page(lists, args: args, key: "lists") { snapshot.listValue($0) })

        case .getList:
            let list = try snapshot.list(args.requireUUID("list_id"))
            let rows = BlockTree.flatten(snapshot.blocks(in: list.id), respectCollapse: false)
            var value = page(rows, args: args, key: "blocks") { snapshot.rowValue($0) }
            value["list"] = snapshot.listValue(list)
            return .object(value)

        case .listTasks:
            let listID = try args.uuid("list_id").map { try snapshot.list($0).id }
            if let labelID = args.uuid("label_id") { _ = try snapshot.label(labelID) }
            let visible = args.bool("include_archived") == true
                ? Set(snapshot.lists.map(\.id)) : ActiveTaskPolicy(lists: snapshot.lists).activeListIDs
            let tasks = snapshot.blocks.filter { task in
                guard task.isTask, let owningID = task.listID, visible.contains(owningID),
                      listID == nil || owningID == listID,
                      matches(args.string("query"), in: [task.text, task.note]) else { return false }
                if let labelID = args.uuid("label_id"), !task.labelIDs.contains(labelID) { return false }
                switch args.string("status") ?? "open" {
                case "open" where task.isCompleted: return false
                case "completed" where !task.isCompleted: return false
                default: break
                }
                switch args.string("view") ?? "all" {
                case "today":
                    // The app's Today: overdue, due today, planned for today and starred.
                    return task.isCompleted ? task.isCompletedToday
                        : task.isDueOnOrBeforeToday || task.isStarred || isPlannedForToday(task)
                case "overdue": return task.isOverdue
                case "starred": return task.isStarred
                default: return true
                }
            }
            return .object(page(tasks, args: args, key: "tasks") { snapshot.blockValue($0) })

        case .getTask:
            let task = try snapshot.task(args.requireUUID("task_id"))
            let rows = BlockTree.flatten(snapshot.blocks(in: task.listID), root: task.id, respectCollapse: false)
            var value = page(rows, args: args, key: "blocks") { snapshot.rowValue($0) }
            value["task"] = snapshot.blockValue(task)
            return .object(value)

        case .listLabels:
            return .object(page(snapshot.labels, args: args, key: "labels") { snapshot.labelValue($0) })

        case .createList:
            let title = try args.nonempty("title")
            let list = store.createList(title: title)
            if let summary = args.string("summary") { store.setSummary(summary, for: list) }
            return .object(["list": snapshot.listValue(list)])

        case .updateList:
            try args.requirePatch(excluding: ["list_id", "expected_updated_at"])
            let list = try snapshot.list(args.requireUUID("list_id"))
            try checkVersion(args, updatedAt: list.updatedAt)
            if args["is_archived"] != nil { try checkTitleDrafts(in: snapshot.blocks(in: list.id)) }
            if list.isSystemInbox, args["title"] != nil || args.bool("is_archived") == true {
                throw MCPToolFailure.invalid("The system Inbox cannot be renamed or archived.")
            }
            let title = try args["title"].map { _ in try args.nonempty("title") }
            if let title { store.rename(list, to: title) }
            if let summary = args.string("summary") { store.setSummary(summary, for: list) }
            if let archived = args.bool("is_archived"), archived != list.isArchived {
                store.setArchived(archived, for: list)
            }
            return .object(["list": snapshot.listValue(list)])

        case .createTask:
            let title = try args.nonempty("title")
            let patch = try TaskPatch(args: args, snapshot: snapshot)
            let parent = try args.uuid("parent_id").map { try snapshot.block($0) }
            let list: TaskList
            if let id = args.uuid("list_id") ?? parent?.listID {
                list = try snapshot.list(id)
            } else if let inbox = snapshot.lists.first(where: \.isSystemInbox) {
                list = inbox
            } else {
                throw MCPToolFailure.missing("Inbox is unavailable. Finish opening Openlist first.")
            }
            try snapshot.checkDestination(list, parent: parent)
            let task = store.appendBlock(kind: .task, text: title, to: .init(listID: list.id, rootBlockID: parent?.id))
            store.log(.created, title: task.displayTitle, block: task, list: list)
            patch.apply(to: task, store: store)
            return .object(["task": snapshot.blockValue(task)])

        case .updateTask:
            try args.requirePatch(excluding: ["task_id", "expected_updated_at"])
            let task = try snapshot.task(args.requireUUID("task_id"), writable: true)
            try checkTitleDrafts(in: [task])
            try checkVersion(args, updatedAt: task.updatedAt)
            let patch = try TaskPatch(args: args, snapshot: snapshot)
            patch.apply(to: task, store: store)
            return .object(["task": snapshot.blockValue(task)])

        case .setTaskCompleted:
            let task = try snapshot.task(args.requireUUID("task_id"), writable: true)
            try checkTitleDrafts(in: [task] + BlockTree.descendants(of: task.id, in: snapshot.blocks(in: task.listID)))
            try checkVersion(args, updatedAt: task.updatedAt)
            let completed = args.bool("completed") == true
            let previousDue = task.dueDate
            let wasRepeating = task.recurrence != nil
            if completed != task.isCompleted { store.toggleCompletion(task) }
            return .object([
                "task": snapshot.blockValue(task),
                "recurrence_advanced": .bool(completed && wasRepeating && task.dueDate != previousDue && !task.isCompleted),
            ])

        case .moveTask:
            let task = try snapshot.task(args.requireUUID("task_id"), writable: true)
            try checkTitleDrafts(in: [task] + BlockTree.descendants(of: task.id, in: snapshot.blocks(in: task.listID)))
            try checkVersion(args, updatedAt: task.updatedAt)
            let list = try snapshot.list(args.requireUUID("list_id"))
            let parent = try args.uuid("parent_id").map { try snapshot.block($0) }
            try snapshot.checkDestination(list, parent: parent)
            if let parent, parent.id == task.id || BlockTree.isDescendant(parent.id, of: task.id, in: snapshot.blocks(in: task.listID)) {
                throw MCPToolFailure.invalid("A task cannot move inside itself or its descendants.")
            }
            if task.listID != list.id || task.parentID != parent?.id {
                let descendants = BlockTree.descendants(of: task.id, in: snapshot.blocks(in: task.listID))
                if parent == nil {
                    store.moveToList(task, list: list)
                } else {
                    guard store.move(task, toParent: parent?.id, above: nil, in: list.id) else {
                        throw MCPToolFailure.invalid("The task could not be moved to that parent.")
                    }
                    store.log(.moved, title: task.displayTitle, detail: "to \(list.displayTitle)", block: task, list: list)
                }
                for block in [task] + descendants where block.isTask { store.scheduleReminderIfNeeded(for: block) }
            }
            return .object(["task": snapshot.blockValue(task)])

        case .appendBlock:
            let list = try snapshot.list(args.requireUUID("list_id"))
            let parent = try args.uuid("parent_id").map { try snapshot.block($0) }
            try snapshot.checkDestination(list, parent: parent)
            guard let kind = BlockKind(rawValue: args.string("kind") ?? "paragraph") else {
                throw MCPToolFailure.invalid("Unknown block kind.")
            }
            let text = args.string("text") ?? ""
            if kind == .divider {
                guard text.isEmpty else { throw MCPToolFailure.invalid("A divider cannot contain text.") }
            } else {
                _ = try args.nonempty("text")
            }
            let block = store.appendBlock(kind: kind, text: text, to: .init(listID: list.id, rootBlockID: parent?.id))
            store.log(.noteAdded, title: block.displayTitle, block: block, list: list)
            return .object(["block": snapshot.blockValue(block)])

        case .createLabel:
            let name = TaskLabel.normalize(try args.nonempty("name"))
            guard !name.isEmpty, let label = store.findOrCreateLabel(named: name) else {
                throw MCPToolFailure.invalid("The label must contain a name after any # prefix.")
            }
            return .object(["label": snapshot.labelValue(label)])
        }
    }

    private func result(_ value: MCPValue) throws -> MCPToolResult {
        let encoded = try JSONEncoder().encode(value)
        guard encoded.count <= 1_500_000 else {
            throw MCPToolFailure(code: "result_too_large", message: "This result is too large. Reduce limit, or shorten the content in the app. No requested changes were saved.")
        }
        let response = MCPToolResult(
            content: [.text(text: String(decoding: encoded, as: UTF8.self), annotations: nil, _meta: nil)],
            structuredContent: Optional.some(value),
            isError: false
        )
        guard try JSONEncoder().encode(response).count <= 4_000_000 else {
            throw MCPToolFailure(code: "result_too_large", message: "This result is too large. Reduce limit or shorten the content in the app. No requested changes were saved.")
        }
        return response
    }

    private func page<T>(_ items: [T], args: MCPArguments, key: String, transform: (T) -> MCPValue) -> [String: MCPValue] {
        let offset = args.integer("offset") ?? 0
        let start = min(offset, items.count)
        let end = start + min(args.integer("limit") ?? 100, items.count - start)
        return [
            key: .array(items[start..<end].map(transform)),
            "total": .int(items.count),
            "next_offset": end < items.count ? .int(end) : .null,
            "time_zone": .string(TimeZone.current.identifier),
        ]
    }

    /// Planned for a day that has come, as the app's Today and its Dock badge
    /// count a task.
    private func isPlannedForToday(_ task: Block) -> Bool {
        let calendar = Calendar.current
        return task.selectedForDay.map { calendar.startOfDay(for: $0) <= calendar.startOfDay(for: .now) } ?? false
    }

    private func matches(_ query: String?, in fields: [String]) -> Bool {
        guard let query, !query.isEmpty else { return true }
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func checkVersion(_ args: MCPArguments, updatedAt: Date) throws {
        if let expected = args.string("expected_updated_at"), expected != MCPDates.timestamp(updatedAt) {
            throw MCPToolFailure(code: "conflict", message: "This item changed since it was read. Read it again before deciding whether to apply the edit.")
        }
    }

    private func checkTitleDrafts(in blocks: [Block]) throws {
        let editing = Set(store.activeTitleDrafts.values)
        guard !blocks.contains(where: { editing.contains($0.id) }) else {
            throw MCPToolFailure(code: "busy", message: "A task title is being edited in Openlist. Finish editing it before changing that task or its containing list through an agent.")
        }
    }
}

private struct TaskPatch {
    let title: String?
    let note: String?
    let changesDue: Bool
    let due: (date: Date, includesTime: Bool)?
    let changesReminder: Bool
    let reminder: Date?
    let priority: TaskPriority?
    let starred: Bool?
    let labels: [TaskLabel]?

    init(args: MCPArguments, snapshot: Snapshot) throws {
        title = try args["title"].map { _ in try args.nonempty("title") }
        note = args.string("note")
        changesDue = args["due_date"] != nil
        due = try args.string("due_date").map { try MCPDates.parse($0) }
        changesReminder = args["reminder_at"] != nil
        reminder = try args.string("reminder_at").map { try MCPDates.parse($0, allowsDay: false).date }
        priority = args.integer("priority").flatMap(TaskPriority.init(rawValue:))
        starred = args.bool("starred")
        labels = try args["label_ids"]?.arrayValue.map { values in
            let labels = try values.map { value in
                guard let text = value.stringValue, let id = UUID(uuidString: text) else {
                    throw MCPToolFailure.invalid("label_ids must contain UUIDs.")
                }
                return try snapshot.label(id)
            }
            guard Set(labels.map(\.id)).count == labels.count else {
                throw MCPToolFailure.invalid("label_ids must not contain duplicate UUIDs.")
            }
            return labels
        }
    }

    func apply(to task: Block, store: Store) {
        if let title { store.setText(title, for: task) }
        if let note { store.setNote(note, for: task) }
        if changesDue, due?.date != task.dueDate || (due?.includesTime ?? false) != task.includesTime
            || (due == nil && !changesReminder && task.reminderAt != nil) {
            store.setDueDate(due?.date, includesTime: due?.includesTime ?? false, for: task)
        }
        if changesReminder, reminder != task.reminderAt { store.setReminder(reminder, for: task) }
        if let priority, priority != task.priority { store.setPriority(priority, for: task) }
        if let starred, starred != task.isStarred { store.toggleStar(task) }
        if let labels, Set(labels.map(\.id)) != Set(task.labelIDs) {
            store.clearLabels(on: task)
            for label in labels { store.addLabel(label, to: task) }
        }
        store.scheduleReminderIfNeeded(for: task)
    }
}

private struct Snapshot {
    let lists: [TaskList]
    let blocks: [Block]
    let labels: [TaskLabel]
    private let listAliases: [UUID: UUID]

    init(context: ModelContext) throws {
        let records = try context.fetch(FetchDescriptor<TaskList>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.id)]))
        let hierarchy = ListHierarchy(records)
        lists = records.filter { hierarchy.availableIDs.contains($0.id) }
        listAliases = Dictionary(
            records.compactMap { record in record.mergedIntoID.map { (record.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        blocks = try context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil }, sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.id)]))
        labels = try context.fetch(FetchDescriptor<TaskLabel>(sortBy: [SortDescriptor(\.name), SortDescriptor(\.id)]))
    }

    func list(_ id: UUID) throws -> TaskList {
        var canonicalID = id
        var visited: Set<UUID> = []
        while let target = listAliases[canonicalID] {
            guard visited.insert(canonicalID).inserted else {
                throw MCPToolFailure.missing("The Inbox sync reference could not be resolved.")
            }
            canonicalID = target
        }
        guard let value = lists.first(where: { $0.id == canonicalID }) else { throw MCPToolFailure.missing("List not found.") }
        return value
    }

    func block(_ id: UUID) throws -> Block {
        guard let value = blocks.first(where: { $0.id == id }), let listID = value.listID else {
            throw MCPToolFailure.missing("Block not found.")
        }
        _ = try list(listID)
        return value
    }

    func task(_ id: UUID, writable: Bool = false) throws -> Block {
        let value = try block(id)
        guard value.isTask else { throw MCPToolFailure.invalid("This block is not a task.") }
        if writable, let listID = value.listID, try list(listID).isEffectivelyArchived {
            throw MCPToolFailure.invalid("Restore the archived list before changing its tasks.")
        }
        return value
    }

    func label(_ id: UUID) throws -> TaskLabel {
        guard let value = labels.first(where: { $0.id == id }) else { throw MCPToolFailure.missing("Label not found.") }
        return value
    }

    func blocks(in listID: UUID?) -> [Block] { blocks.filter { $0.listID == listID } }

    func checkDestination(_ list: TaskList, parent: Block?) throws {
        guard !list.isEffectivelyArchived else { throw MCPToolFailure.invalid("Restore the archived destination list first.") }
        guard let parent else { return }
        guard parent.listID == list.id, parent.kind.acceptsChildren else {
            throw MCPToolFailure.invalid("The parent must be a text or task block in the destination list.")
        }
        let ancestors = BlockTree.ancestors(of: parent, in: blocks(in: list.id)) + [parent]
        guard !ancestors.contains(where: { $0.isTask && $0.isCompleted }) else {
            throw MCPToolFailure.invalid("Reopen the completed parent task before adding or moving content under it.")
        }
    }

    func listValue(_ list: TaskList) -> MCPValue {
        .object([
            "id": .string(list.id.uuidString), "title": .string(list.title),
            "display_title": .string(list.displayTitle), "summary": .string(list.summary),
            "icon": .string(list.icon), "accent": .string(list.accentRaw),
            "is_inbox": .bool(list.isSystemInbox), "is_archived": .bool(list.isArchived),
            "is_effectively_archived": .bool(list.isEffectivelyArchived),
            "parent_list_id": list.parentListID.map { .string($0.uuidString) } ?? .null,
            "created_at": .string(MCPDates.timestamp(list.createdAt)), "updated_at": .string(MCPDates.timestamp(list.updatedAt)),
        ])
    }

    func labelValue(_ label: TaskLabel) -> MCPValue {
        .object(["id": .string(label.id.uuidString), "name": .string(label.name), "accent": .string(label.accentRaw)])
    }

    func rowValue(_ row: BlockRow) -> MCPValue {
        var value = blockFields(row.block)
        value["depth"] = .int(row.depth)
        return .object(value)
    }

    func blockValue(_ block: Block) -> MCPValue { .object(blockFields(block)) }

    private func blockFields(_ block: Block) -> [String: MCPValue] {
        var value: [String: MCPValue] = [
            "id": .string(block.id.uuidString), "kind": .string(block.kindRaw), "text": .string(block.text),
            "list_id": block.listID.map { .string($0.uuidString) } ?? .null,
            "parent_id": block.parentID.map { .string($0.uuidString) } ?? .null,
            "sort_index": .double(block.sortIndex), "collapsed": .bool(block.isCollapsed),
            "created_at": .string(MCPDates.timestamp(block.createdAt)),
            "updated_at": .string(MCPDates.timestamp(block.updatedAt)),
        ]
        if block.isTask {
            let fields: [String: MCPValue] = [
                "note": .string(block.note), "completed": .bool(block.isCompleted),
                "completed_at": block.completedAt.map { .string(MCPDates.timestamp($0)) } ?? .null,
                "due_date": block.dueDate.map { .string(block.includesTime ? MCPDates.timestamp($0) : MCPDates.day($0)) } ?? .null,
                "includes_time": .bool(block.includesTime),
                "reminder_at": block.reminderAt.map { .string(MCPDates.timestamp($0)) } ?? .null,
                "starred": .bool(block.isStarred), "priority": .int(block.priorityRaw),
                "planned_for": block.selectedForDay.map { .string(MCPDates.day($0)) } ?? .null,
                "label_ids": .array(block.labelIDs.map { .string($0.uuidString) }),
                "recurrence": recurrenceValue(block.recurrence),
            ]
            value.merge(fields) { _, new in new }
        } else if block.kind == .image {
            value["caption"] = .string(block.mediaCaption)
        }
        return value
    }

    private func recurrenceValue(_ rule: Recurrence?) -> MCPValue {
        guard let rule else { return .null }
        return .object([
            "description": .string(rule.displayText), "frequency": .string(rule.frequency.rawValue),
            "interval": .int(rule.interval), "anchor": .string(rule.anchor.rawValue),
            "weekdays": .array(rule.weekdays.sorted().map(MCPValue.int)),
            "day_of_month": rule.dayOfMonth.map(MCPValue.int) ?? .null,
            "end_date": rule.endDate.map { .string(MCPDates.timestamp($0)) } ?? .null,
            "occurrence_limit": rule.occurrenceLimit.map(MCPValue.int) ?? .null,
            "completed_occurrences": .int(rule.completedOccurrences),
        ])
    }
}
