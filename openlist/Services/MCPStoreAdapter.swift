import Foundation
import MCP
import OpenlistMCP
import SwiftData

/// All MCP reads and edits stay on the context used by SwiftUI's queries.
@MainActor
final class MCPStoreAdapter {
    let store: Store
    var calendar: (any MCPCalendarAccess)?

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
            let snapshot = try Snapshot(context: store.context, defaultMinutes: store.calendarDefaultEstimateMinutes)
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
                        : task.isDueOnOrBeforeToday || task.isStarred || task.isPlannedForToday
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
            if list.isSystemInbox, args["title"] != nil || args.bool("is_archived") == true {
                throw MCPToolFailure.invalid("The system Inbox cannot be renamed or archived.")
            }
            let title = try args["title"].map { _ in try args.nonempty("title") }
            if let title { store.rename(list, to: title) }
            if let summary = args.string("summary") { store.setSummary(summary, for: list) }
            if let archived = args.bool("is_archived"), archived != list.isArchived {
                store.setArchived(archived, for: list)
            }
            if let hours = args.string("hours"), hours != list.availabilityCategoryRaw {
                store.setAvailabilityCategory(hours, for: list)
            }
            return .object(["list": snapshot.listValue(list)])

        case .createTask:
            let title = try args.nonempty("title")
            let patch = try TaskPatch(args: args, snapshot: snapshot, task: nil)
            let parent = try args.uuid("parent_id").map { try snapshot.block($0) }
            let list: TaskList
            if let id = args.uuid("list_id") ?? parent?.listID {
                list = try snapshot.list(id)
            } else if let inbox = snapshot.lists.first(where: \.isSystemInbox) {
                list = inbox
            } else {
                throw MCPToolFailure.missing("Inbox is unavailable. Finish opening Openlist first.")
            }
            try snapshot.checkDestination(list, parent: parent, placing: .task)
            let task = store.appendBlock(kind: .task, text: title, to: .init(listID: list.id, rootBlockID: parent?.id))
            store.log(.created, title: task.displayTitle, block: task, list: list)
            patch.apply(to: task, store: store)
            return .object(["task": snapshot.blockValue(task)])

        case .updateTask:
            try args.requirePatch(excluding: ["task_id", "expected_updated_at"])
            let task = try snapshot.task(args.requireUUID("task_id"), writable: true)
            try checkVersion(args, updatedAt: task.updatedAt)
            let patch = try TaskPatch(args: args, snapshot: snapshot, task: task)
            if task.isCompleted, patch.plans {
                throw MCPToolFailure.invalid("Reopen the task before planning it.")
            }
            patch.apply(to: task, store: store)
            return .object(["task": snapshot.blockValue(task)])

        case .setTaskCompleted:
            let task = try snapshot.task(args.requireUUID("task_id"), writable: true)
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
            try checkVersion(args, updatedAt: task.updatedAt)
            let list = try snapshot.list(args.requireUUID("list_id"))
            let parent = try args.uuid("parent_id").map { try snapshot.block($0) }
            if let parent, parent.id == task.id || BlockTree.isDescendant(parent.id, of: task.id, in: snapshot.blocks(in: task.listID)) {
                throw MCPToolFailure.invalid("A task cannot move inside itself or its descendants.")
            }
            try snapshot.checkDestination(list, parent: parent, placing: .task, height: snapshot.height(of: task))
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
            guard let kind = BlockKind(rawValue: args.string("kind") ?? "paragraph") else {
                throw MCPToolFailure.invalid("Unknown block kind.")
            }
            try snapshot.checkDestination(list, parent: parent, placing: kind)
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

        case .listCalendar:
            let first = try args.string("start_date").map { try MCPDates.parseDay($0) } ?? Calendar.current.startOfDay(for: .now)
            let days = args.integer("days") ?? 7
            guard let end = Calendar.current.date(byAdding: .day, value: days, to: first) else {
                throw MCPToolFailure.invalid("The range could not be read.")
            }
            let span = DateInterval(start: first, end: end)
            let slots = try snapshot.slots().filter { $0.end > span.start && $0.start < span.end }
            // Busy times come from the running app; null says they're unknown, not free.
            let busy = calendar.map { calendar in
                MCPValue.array(calendar.busyTimes(in: span).sorted { $0.start < $1.start }.map { time in
                    .object([
                        "title": .string(time.title), "start": .string(MCPDates.timestamp(time.start)),
                        "end": .string(MCPDates.timestamp(time.end)),
                        "all_day": .bool(time.end.timeIntervalSince(time.start) >= 20 * 3600),
                    ])
                })
            }
            return .object([
                "start_date": .string(MCPDates.day(first)), "days": .int(days),
                "slots": .array(slots.map { snapshot.slotValue($0, withTask: true) }),
                "busy": busy ?? .null,
                "default_duration_minutes": .int(snapshot.defaultMinutes),
                "time_zone": .string(TimeZone.current.identifier),
            ])

        case .scheduleTask:
            let task = try snapshot.task(args.requireUUID("task_id"), writable: true)
            try checkVersion(args, updatedAt: task.updatedAt)
            guard !task.isCompleted else { throw MCPToolFailure.invalid("Reopen the task before planning it.") }
            let minutes = args.integer("duration_minutes") ?? snapshot.durationMinutes(of: task)
            let slot: DateInterval
            if let text = args.string("start") {
                let start = try MCPDates.parse(text, allowsDay: false).date
                // A minute's grace, for a start read as "now" a moment ago.
                guard start >= Date.now.addingTimeInterval(-60) else {
                    throw MCPToolFailure.invalid("start must not be in the past.")
                }
                slot = DateInterval(start: start, duration: TimeInterval(minutes * 60))
            } else {
                guard let calendar else {
                    throw MCPToolFailure(code: "unavailable", message: "Openlist's calendar isn't running. Give a start time.")
                }
                guard let found = calendar.freeSlot(for: task, minutes: minutes) else {
                    throw MCPToolFailure(code: "no_free_slot", message: "No free slot \(minutes) minutes long this week or next inside the list's hours. Give a start time or a shorter duration_minutes.")
                }
                slot = found
            }
            for placement in try snapshot.placements(of: task) { store.removePlacement(placement) }
            guard let placed = store.setPlacement(for: task, start: slot.start, end: slot.end, isPinned: true) else {
                throw MCPToolFailure.invalid("The task could not be planned.")
            }
            return .object(["task": snapshot.blockValue(task), "slot": snapshot.slotValue(placed)])

        case .unscheduleTask:
            let task = try snapshot.task(args.requireUUID("task_id"), writable: true)
            try checkVersion(args, updatedAt: task.updatedAt)
            var slots = try snapshot.placements(of: task)
            if let slotID = args.uuid("slot_id") {
                slots = slots.filter { $0.id == slotID }
                guard !slots.isEmpty else { throw MCPToolFailure.missing("That slot isn't one of the task's.") }
            }
            for slot in slots { store.removePlacement(slot) }
            return .object(["task": snapshot.blockValue(task), "removed": .int(slots.count)])

        case .updateBlock:
            try args.requirePatch(excluding: ["block_id", "expected_updated_at"])
            let block = try snapshot.block(args.requireUUID("block_id"))
            try checkVersion(args, updatedAt: block.updatedAt)
            guard !block.isTask else { throw MCPToolFailure.invalid("Use openlist_update_task for tasks.") }
            guard block.kind != .divider, block.kind != .image else {
                throw MCPToolFailure.invalid("Dividers and images have no text or kind to change.")
            }
            try snapshot.checkWritable(block)
            let text = try args["text"].map { _ in try args.nonempty("text") }
            if let raw = args.string("kind"), let kind = BlockKind(rawValue: raw), kind != block.kind {
                // The list document's rules: only tasks and list items sit
                // under a line or have lines under them.
                if !OutlinePolicy.nests(kind), block.parentID != nil || snapshot.height(of: block) > 0 {
                    throw MCPToolFailure.invalid("Only tasks and list items go under a line or have lines under them. Move the line or the lines under it first.")
                }
                if kind == .task, snapshot.isUnderCompletedTask(block) {
                    throw MCPToolFailure.invalid("Reopen the completed task above before turning a line under it into a task.")
                }
                store.changeKind(block, to: kind)
            }
            if let text { store.setText(text, for: block) }
            return .object(["block": snapshot.blockValue(block)])

        case .trashBlock:
            let block = try snapshot.block(args.requireUUID("block_id"))
            try checkVersion(args, updatedAt: block.updatedAt)
            try snapshot.checkWritable(block)
            let trashed: MCPValue = .object(["id": .string(block.id.uuidString), "title": .string(block.displayTitle), "kind": .string(block.kindRaw)])
            guard store.trashBlocks([block]) else {
                throw MCPToolFailure(code: "storage_error", message: store.trashError ?? "The content could not be moved to Trash.")
            }
            return .object(["trashed": trashed])
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

    private func matches(_ query: String?, in fields: [String]) -> Bool {
        guard let query, !query.isEmpty else { return true }
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func checkVersion(_ args: MCPArguments, updatedAt: Date) throws {
        if let expected = args.string("expected_updated_at"), expected != MCPDates.timestamp(updatedAt) {
            throw MCPToolFailure(code: "conflict", message: "This item changed since it was read. Read it again before deciding whether to apply the edit.")
        }
    }
}

private extension Block {
    /// Planned for a day that has come, as the app's Today and its Dock badge
    /// count a task.
    var isPlannedForToday: Bool {
        let calendar = Calendar.current
        return selectedForDay.map { calendar.startOfDay(for: $0) <= calendar.startOfDay(for: .now) } ?? false
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
    let changesDuration: Bool
    /// Nil returns to the default.
    let duration: Int?
    let changesRepeat: Bool
    let repeatRule: Recurrence?
    let plannedForToday: Bool?
    let changesDeferral: Bool
    let deferredUntil: Date?
    let keepTogether: Bool?
    let trackAway: Bool?

    /// Picks the task for a day, which a completed task can't be.
    var plans: Bool { plannedForToday == true || deferredUntil != nil }

    init(args: MCPArguments, snapshot: Snapshot, task: Block?) throws {
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
        changesDuration = args["duration_minutes"] != nil
        duration = args.integer("duration_minutes")
        changesRepeat = args["repeat"] != nil
        // Null stops repeating. (MCPValue takes nil as its own null, so this doesn't map one.)
        if let rule = args["repeat"], rule != .null {
            repeatRule = try Self.rule(rule, replacing: task?.recurrence)
        } else {
            repeatRule = nil
        }
        plannedForToday = args.bool("planned_for_today")
        changesDeferral = args["deferred_until"] != nil
        deferredUntil = try args.string("deferred_until").map { text in
            let day = try MCPDates.parseDay(text)
            guard day >= Calendar.current.startOfDay(for: .now) else {
                throw MCPToolFailure.invalid("deferred_until must be today or later.")
            }
            return day
        }
        if plannedForToday != nil, changesDeferral {
            throw MCPToolFailure.invalid("Use planned_for_today or deferred_until, not both.")
        }
        keepTogether = args.bool("keep_together")
        trackAway = args.bool("track_away")
    }

    /// A repeat rule from its fields, keeping the count of occurrences
    /// already done under the rule it replaces.
    private static func rule(_ value: MCPValue, replacing existing: Recurrence?) throws -> Recurrence {
        let fields = value.objectValue ?? [:]
        guard let frequency = fields["frequency"]?.stringValue.flatMap(Recurrence.Frequency.init(rawValue:)) else {
            throw MCPToolFailure.invalid("repeat.frequency is required.")
        }
        var rule = Recurrence(frequency: frequency, interval: fields["interval"]?.intValue ?? 1)
        if let weekdays = fields["weekdays"]?.arrayValue {
            guard frequency == .weekly else { throw MCPToolFailure.invalid("repeat.weekdays applies to weekly rules only.") }
            rule.weekdays = Set(weekdays.compactMap(\.intValue))
        }
        if let day = fields["day_of_month"]?.intValue {
            guard frequency == .monthly else { throw MCPToolFailure.invalid("repeat.day_of_month applies to monthly rules only.") }
            rule.dayOfMonth = day
        }
        rule.anchor = fields["anchor"]?.stringValue.flatMap(Recurrence.Anchor.init(rawValue:)) ?? .dueDate
        rule.endDate = try fields["end_date"]?.stringValue.map { Recurrence.endDate(onDay: try MCPDates.parseDay($0)) }
        rule.occurrenceLimit = fields["occurrence_limit"]?.intValue
        rule.completedOccurrences = existing?.completedOccurrences ?? 0
        return rule
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
        if changesDuration, (duration ?? 0) != task.schedulingEstimateMinutes { store.setTaskEstimate(duration ?? 0, for: task) }
        // After the due date, which a rule repeats from.
        if changesRepeat, repeatRule?.anchored(to: task.dueDate) != task.recurrence { store.setRecurrence(repeatRule, for: task) }
        if let keepTogether, keepTogether != task.keepsSessionsTogether { store.setKeepTogether(keepTogether, for: task) }
        if let trackAway, trackAway != task.tracksAwayFromMac { store.setTracksAway(trackAway, for: task) }
        if let plannedForToday, plannedForToday != task.isPlannedForToday || plannedForToday && task.deferredUntil != nil {
            if plannedForToday { store.selectForToday(task) } else { store.deselectForToday(task) }
        }
        if changesDeferral {
            if let deferredUntil {
                if task.deferredUntil.map({ !Calendar.current.isDate($0, inSameDayAs: deferredUntil) }) ?? true {
                    store.deferTask(task, to: deferredUntil)
                }
            } else if task.deferredUntil != nil {
                store.clearDeferral(task)
            }
        }
        store.scheduleReminderIfNeeded(for: task)
    }
}

private struct Snapshot {
    let lists: [TaskList]
    let blocks: [Block]
    let labels: [TaskLabel]
    /// Minutes a task without its own duration is planned for.
    let defaultMinutes: Int
    private let listAliases: [UUID: UUID]
    private let context: ModelContext

    init(context: ModelContext, defaultMinutes: Int) throws {
        self.context = context
        self.defaultMinutes = defaultMinutes
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

    /// A line in a list that isn't archived, which can change.
    func checkWritable(_ block: Block) throws {
        if let listID = block.listID, try list(listID).isEffectivelyArchived {
            throw MCPToolFailure.invalid("Restore the archived list before changing its content.")
        }
    }

    /// Whether a completed task is above `block` in its list document.
    func isUnderCompletedTask(_ block: Block) -> Bool {
        BlockTree.ancestors(of: block, in: blocks(in: block.listID)).contains { $0.isTask && $0.isCompleted }
    }

    func durationMinutes(of task: Block) -> Int {
        task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : defaultMinutes
    }

    /// The task's slots for its current occurrence, read afresh so a write's
    /// result shows the slots it left, earliest first.
    func placements(of task: Block) throws -> [SchedulePlacement] {
        let id = task.id
        return try context.fetch(FetchDescriptor<SchedulePlacement>(predicate: #Predicate { $0.taskID == id }, sortBy: [SortDescriptor(\.start)]))
            .filter { !$0.isDeleted && $0.occurrenceID == task.occurrenceID && $0.end > $0.start }
    }

    /// Every slot the calendar draws for planned work: open tasks' current
    /// occurrences, in lists that aren't archived, earliest first.
    func slots() throws -> [SchedulePlacement] {
        let open = Dictionary(blocks.filter { task in
            task.isTask && !task.isCompleted && task.listID.flatMap { try? list($0) }.map { !$0.isEffectivelyArchived } == true
        }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return try context.fetch(FetchDescriptor<SchedulePlacement>(sortBy: [SortDescriptor(\.start)])).filter {
            !$0.isDeleted && $0.end > $0.start && open[$0.taskID]?.occurrenceID == $0.occurrenceID
        }
    }

    func slotValue(_ slot: SchedulePlacement, withTask: Bool = false) -> MCPValue {
        var value: [String: MCPValue] = [
            "id": .string(slot.id.uuidString), "start": .string(MCPDates.timestamp(slot.start)),
            "end": .string(MCPDates.timestamp(slot.end)), "pinned": .bool(slot.isPinned),
        ]
        if withTask, let task = blocks.first(where: { $0.id == slot.taskID }) {
            value["task_id"] = .string(task.id.uuidString)
            value["title"] = .string(task.displayTitle)
            value["list_id"] = task.listID.map { .string($0.uuidString) } ?? .null
        }
        return .object(value)
    }

    /// Checks that a `kind` of line, with `height` levels of lines under it,
    /// can go under `parent` in `list`, by the list document's own rules
    /// (`OutlinePolicy`): anything at the root; under a line, only a task or
    /// list item, and only under a task or list item, two levels deep at most.
    func checkDestination(_ list: TaskList, parent: Block?, placing kind: BlockKind, height: Int = 0) throws {
        guard !list.isEffectivelyArchived else { throw MCPToolFailure.invalid("Restore the archived destination list first.") }
        guard let parent else { return }
        guard parent.listID == list.id, OutlinePolicy.nests(parent.kind) else {
            throw MCPToolFailure.invalid("The parent must be a task or list item in the destination list.")
        }
        guard OutlinePolicy.nests(kind) else {
            throw MCPToolFailure.invalid("Only tasks and list items go under a task or list item. Omit parent_id to add this block at the document root.")
        }
        let ancestors = BlockTree.ancestors(of: parent, in: blocks(in: list.id))
        guard ancestors.count + 1 + height <= OutlinePolicy.maximumDepth else {
            let moved = height > 0 ? ", counting the lines under the task being moved" : ""
            throw MCPToolFailure.invalid("Lines nest two levels deep at most\(moved). Choose a parent nearer the document root.")
        }
        guard !(ancestors + [parent]).contains(where: { $0.isTask && $0.isCompleted }) else {
            throw MCPToolFailure.invalid("Reopen the completed parent task before adding or moving content under it.")
        }
    }

    /// How many levels of lines sit under `block`: 0 for none.
    func height(of block: Block) -> Int {
        BlockTree.flatten(blocks(in: block.listID), root: block.id, respectCollapse: false).map { $0.depth + 1 }.max() ?? 0
    }

    func listValue(_ list: TaskList) -> MCPValue {
        .object([
            "id": .string(list.id.uuidString), "title": .string(list.title),
            "display_title": .string(list.displayTitle), "summary": .string(list.summary),
            "icon": .string(list.icon), "accent": .string(list.accentRaw),
            "is_inbox": .bool(list.isSystemInbox), "is_archived": .bool(list.isArchived),
            "is_effectively_archived": .bool(list.isEffectivelyArchived), "hours": .string(list.availabilityCategoryRaw),
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
                "duration_minutes": .int(durationMinutes(of: block)),
                "duration_is_default": .bool(block.schedulingEstimateMinutes == 0),
                "deferred_until": block.deferredUntil.map { .string(MCPDates.day($0)) } ?? .null,
                "keep_together": .bool(block.keepsSessionsTogether),
                "track_away": .bool(block.tracksAwayFromMac),
                "calendar_slots": .array(((try? placements(of: block)) ?? []).map { slotValue($0) }),
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
