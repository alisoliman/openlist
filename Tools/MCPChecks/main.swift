import AppKit
import Foundation
import MCP
import OpenlistMCP
import SwiftData

var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) {
    checks += 1
    do {
        guard try condition() else { fatalError("FAIL: \(message)") }
    } catch {
        fatalError("FAIL: \(message): \(error)")
    }
}

let storeURL = URL(fileURLWithPath: CommandLine.arguments[1])
let phase = CommandLine.arguments[3]
let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self, WorkSession.self, CompletionRecord.self, SchedulePlacement.self])
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL)])
let store = Store(context: container.mainContext)
store.context.autosaveEnabled = false
let adapter = MCPStoreAdapter(store: store)

func call(_ tool: OpenlistMCPTool, _ args: [String: MCPValue] = [:], writes: Bool = true) throws -> [String: MCPValue] {
    let result = try adapter.call(tool.rawValue, arguments: args, allowsWrites: writes)
    check(result.isError == false, "\(tool.rawValue) succeeds: \(result.content)")
    let value = result.structuredContent!.objectValue!
    if case .text(let text, _, _) = result.content.first {
        let structuredJSON = try JSONEncoder().encode(result.structuredContent!)
        let normalized = try JSONDecoder().decode(MCPValue.self, from: structuredJSON)
        check(try JSONDecoder().decode(MCPValue.self, from: Data(text.utf8)) == normalized, "\(tool.rawValue) text and structured results agree")
    } else {
        fatalError("Missing text compatibility result")
    }
    return value
}

func rejects(_ tool: OpenlistMCPTool, _ args: [String: MCPValue], code: String = "invalid_arguments", writes: Bool = true) throws {
    let result = try adapter.call(tool.rawValue, arguments: args, allowsWrites: writes)
    check(result.isError == true, "\(tool.rawValue) rejects invalid input")
    check(result.structuredContent?.objectValue?["error"]?.objectValue?["code"] == .string(code), "failure has code \(code)")
}

func failureMessage(_ tool: OpenlistMCPTool, _ args: [String: MCPValue]) throws -> String {
    let result = try adapter.call(tool.rawValue, arguments: args, allowsWrites: true)
    return result.structuredContent?.objectValue?["error"]?.objectValue?["message"]?.stringValue ?? ""
}

func id(_ value: [String: MCPValue], _ key: String) -> UUID {
    UUID(uuidString: value[key]!.objectValue!["id"]!.stringValue!)!
}
func uuid(_ id: UUID) -> MCPValue { .string(id.uuidString) }

final class FixtureTokenStore: MCPTokenStorage {
    var token: String
    var reads = 0
    var rotations = 0
    var fails = false
    var rotationFails = false
    init(token: String) { self.token = token }
    func loadOrCreate() throws -> String {
        reads += 1
        if fails { throw MCPCredentialError(message: "Fixture credential unavailable") }
        return token
    }
    func rotate() throws -> String {
        rotations += 1
        if rotationFails { throw MCPCredentialError(message: "Fixture token rotation unavailable") }
        token = try MCPKeychainTokenStore.generateToken()
        return token
    }
}

if phase == "prepare" {
    store.bootstrap()
    let inbox = store.inboxList()!
    var saved = 0
    store.onDidSave = { saved += 1 }
    let readOnly = OpenlistMCPTool.catalog(allowsWrites: false)
    check(readOnly.count == 5 && readOnly.allSatisfy { $0.annotations.readOnlyHint == true }, "default catalog contains only reads")
    check(OpenlistMCPTool.catalog(allowsWrites: true).count == 13, "write catalog includes every supported tool")
    check(OpenlistMCPTool.setTaskCompleted.definition.annotations.idempotentHint == false, "recurring completion does not claim idempotency")
    check(OpenlistMCPTool.allCases.allSatisfy { $0.definition.annotations.openWorldHint == false }, "tools stay within Openlist")
    for tool in OpenlistMCPTool.allCases where !tool.isReadOnly {
        try rejects(tool, [:], code: "read_only", writes: false)
    }
    try rejects(.listLists, ["include_archived": "true"])
    try rejects(.listTasks, ["status": "done"])
    try rejects(.listTasks, ["limit": 0])
    try rejects(.listTasks, ["limit": 201])
    try rejects(.listTasks, ["offset": -1])
    try rejects(.listTasks, ["offset": 0.5])
    try rejects(.listTasks, ["unknown_field": true])
    try rejects(.getTask, ["task_id": "not-a-uuid"])
    try rejects(.getList, ["list_id": uuid(UUID())], code: "not_found")
    try rejects(.createList, ["title": " \n "])
    try rejects(.createTask, ["title": "Task", "label_ids": [uuid(UUID())]], code: "not_found")
    try rejects(.createTask, ["title": "Task", "due_date": "2026-02-30"])
    try rejects(.createTask, ["title": "Task", "due_date": "2026-02-30T13:00:00Z"])
    try rejects(.createTask, ["title": "Task", "due_date": "2026-09-12T13:00:00"])
    try rejects(.createTask, ["title": "Task", "reminder_at": "2026-09-12"])
    try rejects(.createTask, ["title": "Task", "priority": 4])
    try rejects(.createTask, ["title": "Task", "title_typo": "Wrong"])
    check(store.blocks(inList: inbox.id).isEmpty, "invalid writes leave no partial tasks")

    let workID = id(try call(.createList, ["title": "MCP work", "summary": "A document"]), "list")
    let otherID = id(try call(.createList, ["title": "Other destination"]), "list")
    let work = store.list(id: workID)!
    let labelID = id(try call(.createLabel, ["name": "#Focus"]), "label")
    check(try call(.listLabels)["labels"]!.arrayValue!.count == 1, "label discovery returns created labels")
    check(try call(.listLists, ["query": "mcp work"])["lists"]!.arrayValue!.count == 1, "list discovery searches titles")
    let sameLabel = id(try call(.createLabel, ["name": "focus"]), "label")
    check(labelID == sameLabel, "label creation is case-insensitive and idempotent")
    let literalID = id(try call(.createTask, ["title": "Read tomorrow #literal"]), "task")
    check(store.block(id: literalID)!.text == "Read tomorrow #literal" && store.block(id: literalID)!.dueDate == nil, "structured capture never parses literal titles")
    check(store.block(id: literalID)!.listID == inbox.id, "omitted list defaults to Inbox")
    _ = try call(.setTaskCompleted, ["task_id": uuid(literalID), "completed": true])
    check(try call(.listTasks, ["view": "today", "status": "completed"])["tasks"]!.arrayValue!.count == 1, "Today includes tasks completed today even without a due date")
    let plannedID = id(try call(.createTask, ["title": "Planned for today"]), "task")
    let laterID = id(try call(.createTask, ["title": "Planned for tomorrow"]), "task")
    let startOfToday = Calendar.current.startOfDay(for: .now)
    store.block(id: plannedID)!.selectedForDay = startOfToday
    store.block(id: laterID)!.selectedForDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)
    let todayTasks = try call(.listTasks, ["view": "today"])["tasks"]!.arrayValue!
    check(todayTasks.contains { $0.objectValue?["id"] == uuid(plannedID) && $0.objectValue?["planned_for"] == .string(MCPDates.day(startOfToday)) }
          && !todayTasks.contains { $0.objectValue?["id"] == uuid(laterID) },
          "Today includes open tasks planned for today, as the app's does, and says the day they're planned for")
    let rootID = id(try call(.createTask, [
        "title": "Build prototype", "list_id": uuid(workID),
        "due_date": "2030-03-10", "note": "Fixture note",
        "priority": 3, "starred": true, "label_ids": [uuid(labelID)],
    ]), "task")
    let root = store.block(id: rootID)!
    check(root.priority == .high && root.isStarred && root.labelIDs == [labelID], "metadata is applied through the app Store")
    check(!root.includesTime && MCPDates.day(root.dueDate!) == "2030-03-10", "date-only scheduling preserves local calendar day")
    let childID = id(try call(.createTask, ["title": "Child", "parent_id": uuid(rootID)]), "task")
    check(store.block(id: childID)!.listID == workID && store.block(id: childID)!.parentID == rootID, "parent-only capture inherits the parent's list")
    let noteID = id(try call(.appendBlock, [
        "list_id": uuid(workID), "parent_id": uuid(childID), "text": "Nested context", "kind": "bullet",
    ]), "block")
    check(try store.taskActivity(for: noteID).contains { $0.kind == .noteAdded && $0.title == "Nested context" }, "MCP standalone text block preserves its existing noteAdded activity")
    root.isCollapsed = true
    store.save()
    let detail = try call(.getTask, ["task_id": uuid(rootID), "limit": 1])
    check(detail["blocks"]!.arrayValue!.count == 1 && detail["total"] == 2 && detail["next_offset"] == 1, "collapsed task details paginate all descendants")
    let listPage = try call(.getList, ["list_id": uuid(workID)])
    check(listPage["blocks"]!.arrayValue!.map { $0.objectValue!["depth"]! } == [0, 1, 2], "list reading preserves complete outline depth")
    // Lines go where the list document puts them: only tasks and list items
    // nest, under a task or list item, two levels deep at most.
    try rejects(.appendBlock, ["list_id": uuid(workID), "parent_id": uuid(childID), "text": "Nested heading", "kind": "heading2"])
    try rejects(.appendBlock, ["list_id": uuid(workID), "parent_id": uuid(rootID), "text": "Nested text"])
    try rejects(.appendBlock, ["list_id": uuid(workID), "parent_id": uuid(rootID), "kind": "divider", "text": ""])
    try rejects(.appendBlock, ["list_id": uuid(workID), "parent_id": uuid(noteID), "text": "Third level", "kind": "numbered"])
    try rejects(.createTask, ["title": "Third level", "parent_id": uuid(noteID)])
    let sectionID = id(try call(.appendBlock, ["list_id": uuid(workID), "text": "Section", "kind": "heading1"]), "block")
    let proseID = id(try call(.appendBlock, ["list_id": uuid(workID), "text": "Prose"]), "block")
    try rejects(.createTask, ["title": "Under a heading", "parent_id": uuid(sectionID)])
    try rejects(.appendBlock, ["list_id": uuid(workID), "parent_id": uuid(proseID), "text": "Under text", "kind": "bullet"])
    let spareID = id(try call(.createTask, ["title": "Spare", "list_id": uuid(workID)]), "task")
    let spareChildID = id(try call(.createTask, ["title": "Spare child", "parent_id": uuid(spareID)]), "task")
    try rejects(.moveTask, ["task_id": uuid(rootID), "list_id": uuid(workID), "parent_id": uuid(spareID)])
    try rejects(.moveTask, ["task_id": uuid(spareID), "list_id": uuid(workID), "parent_id": uuid(childID)])
    try rejects(.moveTask, ["task_id": uuid(spareChildID), "list_id": uuid(workID), "parent_id": uuid(noteID)])
    let tooDeep = try failureMessage(.appendBlock, ["list_id": uuid(workID), "parent_id": uuid(noteID), "text": "Third level", "kind": "numbered"])
    let movedTooDeep = try failureMessage(.moveTask, ["task_id": uuid(spareID), "list_id": uuid(workID), "parent_id": uuid(childID)])
    check(tooDeep.hasPrefix("Lines nest two levels deep at most.") && !tooDeep.contains("moved")
          && movedTooDeep.contains("counting the lines under the task being moved"),
          "the depth failure names a moved task's lines only when a task with lines is moved")
    let looseID = id(try call(.createTask, ["title": "Loose", "list_id": uuid(workID)]), "task")
    _ = try call(.moveTask, ["task_id": uuid(looseID), "list_id": uuid(workID), "parent_id": uuid(spareChildID)])
    check(store.block(id: looseID)!.parentID == spareChildID, "a move under a subtask still lands two levels deep")
    let itemID = id(try call(.appendBlock, ["list_id": uuid(workID), "parent_id": uuid(spareID), "text": "Packing", "kind": "numbered"]), "block")
    _ = try call(.createTask, ["title": "Under a list item", "parent_id": uuid(itemID)])
    check(try call(.getTask, ["task_id": uuid(spareID)])["blocks"]!.arrayValue!.map { $0.objectValue!["depth"]! } == [0, 1, 0, 1],
          "tasks and list items nest under a task or list item, as in the list document")
    check(try call(.listTasks, ["label_id": uuid(labelID)])["tasks"]!.arrayValue!.count == 1, "label filter finds the task")
    check(try call(.listTasks, ["query": "FIXTURE NOTE"])["tasks"]!.arrayValue!.count == 1, "search includes task notes case-insensitively")
    check(try call(.listTasks, ["offset": .int(Int.max)])["tasks"]!.arrayValue!.isEmpty, "extreme offsets neither overflow nor repeat results")
    try rejects(.getTask, ["task_id": uuid(noteID)])
    try rejects(.updateTask, ["task_id": uuid(rootID)])
    try rejects(.updateTask, ["task_id": uuid(rootID), "expected_updated_at": "stale", "title": "Wrong"], code: "conflict")
    try rejects(.updateTask, ["task_id": uuid(rootID), "title": "Wrong", "due_date": "invalid"])
    check(root.text == "Build prototype", "invalid combined update does not apply a partial title")

    let rich = NSMutableAttributedString(string: root.text)
    RichTextCodec.toggleTrait(.boldFontMask, in: rich, range: NSRange(location: 0, length: 5), kind: .task)
    store.setContent(root, attributed: rich)
    store.save()
    let version = MCPDates.timestamp(root.updatedAt)
    _ = try call(.updateTask, [
        "task_id": uuid(rootID), "title": "Build working prototype", "expected_updated_at": .string(version),
        "due_date": "2030-03-10T16:00:00+02:00", "reminder_at": "2030-03-10T13:45:00Z",
    ])
    let font = store.attributedContent(of: root).attribute(.font, at: 0, effectiveRange: nil) as! NSFont
    check(NSFontManager.shared.traits(of: font).contains(.boldFontMask), "remote retitling preserves inline styling")
    check(root.includesTime && MCPDates.timestamp(root.dueDate!) == "2030-03-10T14:00:00.000000000Z", "zoned timestamp resolves to the correct instant")
    let remoteHistory = try store.taskActivity(for: rootID)
    check(remoteHistory.contains { $0.kind == .renamed && $0.change?.before?.title == "Build prototype" && $0.change?.after?.title == "Build working prototype" }, "MCP title patch records committed old and new title")
    check(remoteHistory.contains { $0.kind == .scheduled && $0.change?.after?.includesTime == true }, "MCP schedule patch records explicit time precision")
    _ = try call(.updateTask, ["task_id": uuid(rootID), "due_date": "2030-03-11T14:00:00Z"])
    check(MCPDates.timestamp(root.reminderAt!) == "2030-03-11T13:45:00.000000000Z", "rescheduling shifts the existing reminder")
    _ = try call(.updateTask, ["task_id": uuid(rootID), "due_date": .null, "label_ids": [], "starred": false, "priority": 0])
    check(root.dueDate == nil && root.reminderAt == nil && root.labelIDs.isEmpty && !root.isStarred && root.priority == .none, "explicit clearing preserves false, zero, [] and null semantics")
    _ = try call(.updateTask, ["task_id": uuid(rootID), "reminder_at": "2030-03-11T13:45:00Z"])
    check(root.dueDate == nil && NotificationService.shared.scheduled.contains(rootID), "an undated task can have an independent reminder")
    _ = try call(.updateTask, ["task_id": uuid(rootID), "priority": 0])
    check(root.reminderAt != nil, "omitting due_date preserves an independent reminder")
    _ = try call(.updateTask, ["task_id": uuid(rootID), "due_date": .null])
    check(root.reminderAt == nil && !NotificationService.shared.scheduled.contains(rootID), "clearing an already-empty due date also cancels an independent reminder")
    let unchanged = root.updatedAt
    let unchangedHistory = try store.taskActivity(for: rootID).map(\.id)
    _ = try call(.updateTask, ["task_id": uuid(rootID), "due_date": .null, "priority": 0, "label_ids": []])
    check(root.updatedAt == unchanged, "repeating an identical patch does not alter the task")
    check(try store.taskActivity(for: rootID).map(\.id) == unchangedHistory, "MCP no-op retry adds no history")
    _ = try call(.updateTask, [
        "task_id": uuid(rootID), "due_date": .null, "reminder_at": "2030-03-12T13:45:00Z",
    ])
    check(root.dueDate == nil && MCPDates.timestamp(root.reminderAt!) == "2030-03-12T13:45:00.000000000Z", "an explicit reminder overrides due-date clearing in the same patch")
    let versionWithIndependentReminder = root.updatedAt
    _ = try call(.updateTask, [
        "task_id": uuid(rootID), "due_date": .null, "reminder_at": "2030-03-12T13:45:00Z",
    ])
    check(root.updatedAt == versionWithIndependentReminder, "repeating an explicit independent reminder does not clear and recreate it")
    _ = try call(.updateTask, ["task_id": uuid(rootID), "due_date": .null, "reminder_at": .null])
    try rejects(.moveTask, ["task_id": uuid(rootID), "list_id": uuid(workID), "parent_id": uuid(childID)])
    try rejects(.createTask, ["title": "Wrong list", "list_id": uuid(otherID), "parent_id": uuid(rootID)])
    let childVersionBeforeMove = MCPDates.timestamp(store.block(id: childID)!.updatedAt)
    let noteVersionBeforeMove = MCPDates.timestamp(store.block(id: noteID)!.updatedAt)
    _ = try call(.moveTask, ["task_id": uuid(rootID), "list_id": uuid(otherID)])
    check([rootID, childID, noteID].allSatisfy { store.block(id: $0)!.listID == otherID }, "cross-list move carries the entire mixed subtree")
    check(try store.taskActivity(for: childID).first?.change?.before?.listID == workID && store.taskActivity(for: childID).first?.change?.after?.listID == otherID, "MCP parent move records each task's actual destination")
    check(MCPDates.timestamp(store.block(id: childID)!.updatedAt) != childVersionBeforeMove, "moving a parent across lists updates its child's optimistic version")
    check(MCPDates.timestamp(store.block(id: noteID)!.updatedAt) != noteVersionBeforeMove, "moving a parent across lists also versions note descendants")
    try rejects(.updateTask, [
        "task_id": uuid(childID), "note": "Stale destination edit",
        "expected_updated_at": .string(childVersionBeforeMove),
    ], code: "conflict")
    let childVersionAfterMove = store.block(id: childID)!.updatedAt
    _ = try call(.moveTask, ["task_id": uuid(rootID), "list_id": uuid(otherID)])
    check(store.block(id: childID)!.updatedAt == childVersionAfterMove, "an unchanged destination does not invalidate descendant versions")
    _ = try call(.setTaskCompleted, ["task_id": uuid(rootID), "completed": true])
    check(root.isCompleted && store.block(id: childID)!.isCompleted, "parent completion follows the app's subtree rules")
    try rejects(.createTask, ["title": "Hidden child", "parent_id": uuid(childID)])
    _ = try call(.setTaskCompleted, ["task_id": uuid(rootID), "completed": false])
    check(!root.isCompleted, "completed task can be reopened")
    store.setDueDate(try MCPDates.parse("2030-03-10").date, for: root)
    store.setRecurrence(.daily, for: root)
    let repeatVersion = MCPDates.timestamp(root.updatedAt)
    let repeated = try call(.setTaskCompleted, [
        "task_id": uuid(rootID), "completed": true, "expected_updated_at": .string(repeatVersion),
    ])
    check(repeated["recurrence_advanced"] == true && !root.isCompleted && !store.block(id: childID)!.isCompleted, "recurrence advances and resets subtasks instead of becoming completed")
    check(try store.taskActivity(for: rootID).first?.change?.advancesOccurrence == true, "MCP recurring completion explains the next occurrence")
    try rejects(.setTaskCompleted, ["task_id": uuid(rootID), "completed": true, "expected_updated_at": .string(repeatVersion)], code: "conflict")
    _ = try call(.updateList, ["list_id": uuid(otherID), "is_archived": true])
    check(try call(.listTasks, ["list_id": uuid(otherID)])["tasks"]!.arrayValue!.isEmpty, "archived tasks disappear from active task results")
    check(try call(.listTasks, ["list_id": uuid(otherID), "include_archived": true])["tasks"]!.arrayValue!.count == 2, "archived content remains explicitly readable")
    try rejects(.updateTask, ["task_id": uuid(rootID), "note": "Wrong"])
    try rejects(.createTask, ["list_id": uuid(otherID), "title": "Wrong"])
    _ = try call(.updateList, ["list_id": uuid(otherID), "is_archived": false])
    try rejects(.updateList, ["list_id": uuid(inbox.id), "is_archived": true])
    try rejects(.updateList, ["list_id": uuid(inbox.id), "title": "Renamed"])
    check(work.title == "MCP work" && saved > 0, "mutations preserve unrelated content and publish successful saves")

    // An oversized result must roll back only the agent's edit, not pending UI typing.
    root.note = String(repeating: "x", count: 1_600_000)
    root.text = "User's pending title"
    try rejects(.updateTask, ["task_id": uuid(rootID), "title": "Agent title"], code: "result_too_large")
    check(store.block(id: rootID)!.text == "User's pending title", "rollback retains the UI edits committed before the agent operation")
    let restored = store.block(id: rootID)!
    restored.note = String(repeating: "\"", count: 700_000)
    try rejects(.updateTask, ["task_id": uuid(rootID), "title": "Escaped oversized result"], code: "result_too_large")
    check(store.block(id: rootID)!.text == "User's pending title", "the exact encoded response limit is checked before committing")
    store.block(id: rootID)!.note = "Persistent fixture note"
    store.save()

    let token = try MCPKeychainTokenStore.generateToken()
    let anotherToken = try MCPKeychainTokenStore.generateToken()
    check(token.count == 64 && token != anotherToken, "tokens contain 256 bits of fresh secure randomness")
    check(MCPDates.timestamp(Date(timeIntervalSinceReferenceDate: 800_000_000.0001)) != MCPDates.timestamp(Date(timeIntervalSinceReferenceDate: 800_000_000.0002)), "optimistic versions distinguish sub-millisecond edits")
    let server = LocalMCPServer(port: 0, token: token, tools: OpenlistMCPTool.catalog(allowsWrites: true), version: "checks") { name, arguments in
        try await adapter.call(name, arguments: arguments, allowsWrites: true)
    }
    let port = try await server.start()
    func request(_ payload: MCPValue, bearer: String? = nil) async throws -> MCPValue {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearer ?? token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("2025-11-25", forHTTPHeaderField: "MCP-Protocol-Version")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        check((response as! HTTPURLResponse).statusCode == 200, "real MCP HTTP request succeeds")
        return try JSONDecoder().decode(MCPValue.self, from: data)
    }
    let initialized = try await request(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
        "protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "store-checks", "version": "1"],
    ]])
    check(initialized.objectValue?["result"]?.objectValue?["serverInfo"]?.objectValue?["name"] == "Openlist", "real MCP handshake identifies the packaged app server")
    let wire = try await request(["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": [
        "name": .string(OpenlistMCPTool.createTask.rawValue), "arguments": ["title": "Created over MCP HTTP", "list_id": uuid(workID)],
    ]])
    check(wire.objectValue?["result"]?.objectValue?["isError"] == false, "wire-level tool call succeeds")
    check(store.blocks(inList: workID).contains { $0.text == "Created over MCP HTTP" }, "HTTP mutations immediately reach the UI's main context")
    let helperReplies = try await helperRoundTrip(
        executable: URL(fileURLWithPath: CommandLine.arguments[4]),
        endpoint: "http://127.0.0.1:\(port)/mcp", token: token,
        listID: workID, directory: storeURL.deletingLastPathComponent()
    )
    check(helperReplies.count == 3 && helperReplies.compactMap { $0.objectValue?["id"]?.intValue } == [10, 11, 12], "native stdio replies are only JSON-RPC responses; notifications stay silent")
    check(helperReplies.last?.objectValue?["result"]?.objectValue?["isError"] == false, "native stdio tool call succeeds end to end")
    check(store.blocks(inList: workID).contains { $0.text == "Created through packaged stdio" }, "bundled launcher writes immediately reach the UI's context")
    await server.stop()

    let defaultsName = "solimanali.openlist.mcp-check.\(CommandLine.arguments[2])"
    let defaults = UserDefaults(suiteName: defaultsName)!
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let settings = AppSettings(defaults: defaults)
    #if OPENLIST_DEV
    let expectedPort = 45874
    let expectedServerName = "openlist-dev"
    #else
    let expectedPort = 45873
    let expectedServerName = "openlist"
    #endif
    check(!settings.mcpEnabled && !settings.mcpAllowsWrites && settings.mcpPort == expectedPort, "MCP is opt-in and uses the correct production or development port")
    settings.mcpPort = Int(port)
    let credential = FixtureTokenStore(token: token)
    let integration = MCPIntegration(store: store, settings: settings, tokenStore: credential)
    integration.start(storageAvailable: true)
    await integration.waitForTransition()
    check(integration.status == .off && credential.reads == 0, "disabled startup never reads or creates a credential")
    integration.setEnabled(true)
    await integration.waitForTransition()
    check(integration.isRunning && credential.reads == 1, "enabling access starts the actual listener")
    let catalog = try await request(["jsonrpc": "2.0", "id": 3, "method": "tools/list"])
    check(catalog.objectValue!["result"]!.objectValue!["tools"]!.arrayValue!.count == 5, "read-only permission controls the real wire catalog")
    let config = try integration.configuration(for: .stdio, bundleURL: URL(fileURLWithPath: "/Applications/Openlist with spaces.app"))
    let configServers = try JSONDecoder().decode(MCPValue.self, from: Data(config.utf8)).objectValue!["mcpServers"]!.objectValue!
    check(Set(configServers.keys) == Set([expectedServerName]), "stdio configuration has a distinct production or development entry")
    let fields = configServers[expectedServerName]!.objectValue!
    check(fields["command"] == "/Applications/Openlist with spaces.app/Contents/MacOS/openlist-mcp", "stdio configuration quotes paths safely, including spaces")
    check(fields["env"]!.objectValue!["OPENLIST_MCP_TOKEN"] == .string(token), "generated configuration uses the active credential")
    let httpConfig = try integration.configuration(for: .vscode)
    let httpServers = try JSONDecoder().decode(MCPValue.self, from: Data(httpConfig.utf8)).objectValue!["servers"]!.objectValue!
    check(Set(httpServers.keys) == Set([expectedServerName]), "HTTP configuration has a distinct production or development entry")
    let httpFields = httpServers[expectedServerName]!.objectValue!
    check(httpFields["type"] == "http" && httpFields["url"] == .string(integration.url), "VS Code configuration has the correct HTTP shape")
    integration.setAllowsWrites(true)
    await integration.waitForTransition()
    let writeCatalog = try await request(["jsonrpc": "2.0", "id": 4, "method": "tools/list"])
    check(writeCatalog.objectValue!["result"]!.objectValue!["tools"]!.arrayValue!.count == 13, "write permission restarts with the expanded catalog")
    integration.restart(rotatingToken: true)
    await integration.waitForTransition()
    check(integration.isRunning && credential.rotations == 1 && credential.token != token, "reset rotates the token and restarts the listener")
    var stale = URLRequest(url: URL(string: integration.url)!)
    stale.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (_, unauthorized) = try await URLSession.shared.data(for: stale)
    check((unauthorized as! HTTPURLResponse).statusCode == 401, "old client credentials are revoked after reset")
    _ = try await request(["jsonrpc": "2.0", "id": 5, "method": "ping"], bearer: credential.token)
    let tokenBeforeQueuedReset = credential.token
    integration.restart(rotatingToken: true)
    integration.setAllowsWrites(false)
    await integration.waitForTransition()
    check(integration.isRunning && credential.rotations == 2 && credential.token != tokenBeforeQueuedReset, "a permission change cannot cancel a queued token reset")
    stale.setValue("Bearer \(tokenBeforeQueuedReset)", forHTTPHeaderField: "Authorization")
    let (_, rejectedQueuedToken) = try await URLSession.shared.data(for: stale)
    check((rejectedQueuedToken as! HTTPURLResponse).statusCode == 401, "a superseded reset still revokes the previous credential")

    let tokenBeforeFailedReset = credential.token
    let rotationsBeforeFailure = credential.rotations
    credential.rotationFails = true
    integration.restart(rotatingToken: true)
    await integration.waitForTransition()
    if case .failed(let message) = integration.status {
        check(message.contains("Fixture token rotation unavailable"), "token reset failures surface explicitly")
    } else {
        fatalError("Token reset failure reported success")
    }
    credential.rotationFails = false
    integration.restart()
    await integration.waitForTransition()
    check(integration.isRunning && credential.rotations == rotationsBeforeFailure + 2 && credential.token != tokenBeforeFailedReset, "Retry completes a failed reset instead of reusing the old credential")
    stale.setValue("Bearer \(tokenBeforeFailedReset)", forHTTPHeaderField: "Authorization")
    let (_, rejectedRetriedToken) = try await URLSession.shared.data(for: stale)
    check((rejectedRetriedToken as! HTTPURLResponse).statusCode == 401, "retrying a reset revokes the credential that could not initially be replaced")

    let tokenBeforeDisabledReset = credential.token
    integration.restart(rotatingToken: true)
    integration.setEnabled(false)
    await integration.waitForTransition()
    check(integration.status == .off && credential.token == tokenBeforeDisabledReset, "disabling access defers a queued reset without creating a credential")
    integration.setEnabled(true)
    await integration.waitForTransition()
    check(integration.isRunning && credential.token != tokenBeforeDisabledReset, "reenabling access completes a previously requested token reset")
    integration.setAllowsWrites(true)
    await integration.waitForTransition()
    integration.setEnabled(false)
    integration.setEnabled(true)
    integration.setEnabled(false)
    await integration.waitForTransition()
    check(integration.status == .off && !settings.mcpEnabled, "rapid enable/disable changes leave no orphaned enabled state")
    do {
        _ = try await URLSession.shared.data(from: URL(string: integration.url)!)
        fatalError("Disabled endpoint remained responsive")
    } catch {
        check(true, "disabling closes the listening port")
    }
    let readsBeforeFallback = credential.reads
    integration.start(storageAvailable: false)
    integration.setEnabled(true)
    await integration.waitForTransition()
    if case .failed = integration.status {
        check(credential.reads == readsBeforeFallback, "a temporary store never opens agent access or reads a credential")
    } else {
        fatalError("Temporary store was exposed")
    }
    credential.fails = true
    integration.start(storageAvailable: true)
    await integration.waitForTransition()
    if case .failed(let message) = integration.status {
        check(message.contains("Fixture credential unavailable"), "credential failures surface explicitly in settings")
    } else {
        fatalError("Credential failure reported success")
    }
    integration.setEnabled(false)
    await integration.waitForTransition()
    let reloaded = AppSettings(defaults: defaults)
    check(!reloaded.mcpEnabled && reloaded.mcpAllowsWrites && reloaded.mcpPort == Int(port), "connection preferences persist across settings instances")
    let alias = TaskList(title: "Another Mac's Inbox", isSystemInbox: true)
    alias.createdAt = inbox.createdAt.addingTimeInterval(1000)
    store.context.insert(alias)
    try store.reconcileSystemRecords()
    store.save()
    let chainedAlias = TaskList(title: "Late Inbox alias", isSystemInbox: true)
    chainedAlias.mergedIntoID = alias.id
    store.context.insert(chainedAlias)
    store.save()
    let visibleLists = try call(.listLists, ["include_archived": true])["lists"]!.arrayValue!
    check(visibleLists.filter { $0.objectValue?["is_inbox"] == true }.count == 1, "MCP discovery hides retained iCloud Inbox aliases")
    check(id(try call(.getList, ["list_id": uuid(chainedAlias.id)]), "list") == inbox.id, "A cached MCP list ID resolves through chained Inbox aliases")
    let aliasedCaptureID = id(try call(.createTask, [
        "title": "Aliased Inbox capture", "list_id": uuid(chainedAlias.id),
    ]), "task")
    check(store.block(id: aliasedCaptureID)?.listID == inbox.id, "MCP writes through a stale Inbox ID use canonical ownership")
    let aliasedTasks = try call(.listTasks, ["list_id": uuid(chainedAlias.id)])["tasks"]!.arrayValue!
    check(aliasedTasks.contains { $0.objectValue?["id"] == uuid(aliasedCaptureID) }, "MCP task filtering resolves stale Inbox IDs before matching canonical tasks")
    check(store.persistenceError == nil, "MCP writes commit to the isolated disk store")
} else if phase == "reopen" {
    let all = try store.context.fetch(FetchDescriptor<Block>())
    check(all.contains { $0.text == "Created over MCP HTTP" }, "a separate process reopens HTTP-created data")
    check(all.contains { $0.text == "Created through packaged stdio" }, "a separate process reopens data created through the native launcher")
    let task = all.first { $0.note == "Persistent fixture note" }!
    check(task.text == "User's pending title" && task.recurrence?.frequency == .daily, "rollback and recurrence remain durable")
    check(all.contains { $0.text == "Nested context" && $0.listID == task.listID }, "subtree move remains durable")
    check(all.contains { $0.text == "Aliased Inbox capture" && $0.listID == store.inboxList()?.id }, "MCP captures through iCloud aliases remain canonical after reopening")
    check(store.allLabels().count == 1, "label creation remains durable")

    let readonly = try ModelContainer(for: schema, configurations: [
        ModelConfiguration(schema: schema, url: storeURL, allowsSave: false),
    ])
    let failingStore = Store(context: readonly.mainContext)
    let failingAdapter = MCPStoreAdapter(store: failingStore)
    let before = failingStore.blocks(inList: store.inboxList()!.id).count
    let failed = try failingAdapter.call(OpenlistMCPTool.createTask.rawValue, arguments: ["title": "Cannot be saved"], allowsWrites: true)
    check(failed.isError == true && failingStore.persistenceError != nil, "a real disk-save failure is never acknowledged as success")
    check(!failingStore.context.hasChanges && failingStore.blocks(inList: store.inboxList()!.id).count == before, "failed persistence rolls back the agent insertion")
}

print("\(checks) MCP store/protocol checks passed (\(phase))")
