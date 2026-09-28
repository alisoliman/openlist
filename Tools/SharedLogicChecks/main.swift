// Checks the UI-free logic the Mac screens and the iOS companion share:
// Today's set and orders, the Inbox triage queue, the task query language,
// the atomic capture and its draft, a list page's rows, and the phone's
// compact wording. Where logic moved out of a Mac view, a copy of the view's
// old code stands beside it, so the Mac is shown to draw exactly what it did.

import Foundation
import Observation
import SwiftData

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}

let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self,
                     SchedulePlacement.self, WorkSession.self, CompletionRecord.self])
var containers: [ModelContainer] = []
func makeStore() throws -> Store {
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    containers.append(container)
    let store = Store(context: container.mainContext)
    store.context.autosaveEnabled = false
    store.bootstrap()
    return store
}

func makeLibrary(_ store: Store) throws -> NextLibrary {
    NextLibrary(lists: try store.context.fetch(FetchDescriptor<TaskList>(predicate: TaskList.availablePredicate)),
                sections: store.allSections(), labels: store.allLabels(),
                tasks: try store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil && $0.kindRaw == "task" })))
}

let calendar = Calendar.current
let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 10, minute: 10))!
/// `days` from `now`'s day at the hour and minute.
func at(_ days: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    calendar.date(byAdding: .day, value: days, to: calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)!)!
}
func titles(_ blocks: [Block]) -> [String] { blocks.map(\.text) }

// MARK: - Today

// The Mac's `NXTodayPage.model` before its rules moved to `TodayAgenda`.
func legacyToday(_ tasks: [Block], closing: [UUID: Bool], isPlanned: (Block) -> Bool, now: Date)
    -> (overdue: [Block], due: [Block], planned: [Block], starred: [Block], done: [Block], progress: (Int, Int), clear: Bool) {
    let visible = tasks.filter { !$0.isCompleted || closing[$0.id] != nil }
    func offset(_ task: Block) -> Int? { task.dueDate.map { NXFormat.dayOffset($0, now: now) } }
    let overdue = visible.filter { (offset($0) ?? 0) < 0 }
    let due = visible.filter { offset($0) == 0 }
    let planned = visible.filter { isPlanned($0) && (offset($0) ?? 1) > 0 }
    let starred = visible.filter { $0.isStarred && (offset($0) ?? 1) > 0 && !isPlanned($0) }
    let doneToday = tasks
        .filter { $0.isCompleted && $0.completedAt.map { NXFormat.dayOffset($0, now: now) == 0 } == true }
        .sorted(by: Block.byCompletionDate)
    let open = overdue.count + due.count + planned.count + starred.count
    return (overdue, due, planned, starred, doneToday, (doneToday.count, doneToday.count + open), open == 0)
}

do {
    let store = try makeStore()
    let home = store.createList(title: "Home")
    func task(_ title: String, parent: Block? = nil, _ configure: (Block) -> Void = { _ in }) -> Block {
        let block = store.appendBlock(kind: .task, text: title, to: DocumentContext(listID: home.id, rootBlockID: parent?.id))
        configure(block)
        return block
    }
    let tap = task("Fix the dripping bathroom tap") { $0.dueDate = at(-1, 0) }
    let retro = task("Close out Q2 retro actions") { $0.dueDate = at(-3, 0) }
    let nishiki = task("Reserve the Nishiki market tour") { $0.dueDate = at(-2, 9); $0.includesTime = true }
    let planters = task("Ask Mika to water the planters") { $0.dueDate = at(0, 0); $0.recurrence = .daily }
    let deposit = task("Pay the ryokan deposit") { $0.dueDate = at(0, 18); $0.includesTime = true }
    let scorecard = task("Update the design role scorecard") { $0.dueDate = at(0, 13); $0.includesTime = true }
    let filters = task("Order new water filters") { $0.dueDate = at(0, 16, 30); $0.includesTime = true }
    let feedback = task("Write interview feedback for Priya") { $0.selectedForDay = at(0, 0) }
    let earlier = task("Morning call") { $0.dueDate = at(0, 8); $0.includesTime = true }
    let carried = task("Planned yesterday, due Friday") { $0.selectedForDay = at(-1, 0); $0.dueDate = at(2, 0) }
    let tomorrowPlan = task("Planned for tomorrow") { $0.selectedForDay = at(1, 0) }
    let ryokan = task("Book the ryokan") { $0.isStarred = true }
    let overstory = task("Finish The Overstory") { $0.isStarred = true; $0.dueDate = at(3, 0) }
    let starPlanned = task("Starred and planned") { $0.isStarred = true; $0.selectedForDay = at(0, 0) }
    let starLate = task("Starred and late") { $0.isStarred = true; $0.dueDate = at(-1, 0) }
    let later = task("Due next week") { $0.dueDate = at(5, 0) }
    let standup = task("Standup notes") { $0.isCompleted = true; $0.completedAt = at(0, 9, 46) }
    let kasuga = task("Reply to Kasuga") { $0.isCompleted = true; $0.completedAt = at(0, 8, 28) }
    let yesterday = task("Done yesterday") { $0.isCompleted = true; $0.completedAt = at(-1, 17) }
    let closing = task("Ticked a moment ago") { $0.dueDate = at(0, 0); $0.isCompleted = true; $0.completedAt = at(0, 10, 9) }
    let subtask = task("Compare Gion vs Arashiyama", parent: ryokan) { $0.dueDate = at(0, 0) }
    store.save()
    let tasks = [tap, retro, nishiki, planters, deposit, scorecard, filters, feedback, earlier, carried, tomorrowPlan, ryokan,
                 overstory, starPlanned, starLate, later, standup, kasuga, yesterday, closing, subtask]

    let agenda = TodayAgenda(tasks: tasks, closing: [closing.id], now: now)
    check(titles(agenda.overdue) == titles([tap, retro, nishiki, starLate]),
          "Overdue is every task due on an earlier day, starred or not, in the order given")
    check(titles(agenda.due) == titles([planters, deposit, scorecard, filters, earlier, closing, subtask]),
          "Due today goes by day, so a time already past today is still due today; subtasks count too")
    check(titles(agenda.planned) == titles([feedback, carried, starPlanned]),
          "Planned is picked for today or an earlier day, with no due date or a later one")
    check(!agenda.planned.contains { $0.id == tomorrowPlan.id } && !agenda.due.contains { $0.id == later.id },
          "A task planned for tomorrow, or due next week, isn't Today's")
    check(titles(agenda.starred) == titles([ryokan, overstory]), "Starred leaves out planned, overdue and due tasks")
    check(titles(agenda.doneToday) == titles([closing, standup, kasuga]), "Done today is most recently done first")
    check(!agenda.doneToday.contains { $0.id == yesterday.id }, "A task done yesterday isn't done today")
    check(agenda.progress == (3, 3 + 16) && agenda.openCount == 16 && !agenda.isClear, "Progress counts done today out of all of Today")
    check(titles(agenda.scheduled) == titles(agenda.overdue + agenda.due + agenda.planned),
          "In outline order the run above Starred is the groups one after another")
    check(!TodayAgenda(tasks: tasks, now: now).due.contains { $0.id == closing.id },
          "A done task out of its dwell leaves the open groups")
    check(TodayAgenda(tasks: [standup, kasuga, later], now: now).isClear, "Only done or later tasks leave Today clear")

    // The phone's order: most late first, then by time of day, a calendar
    // slot ahead of a timed due date, then the untimed in the order given.
    let slots = [feedback.id: at(0, 11, 30), overstory.id: at(0, 15), later.id: at(1, 9)]
    let phone = TodayAgenda(tasks: tasks, closing: [closing.id], now: now, order: .schedule, time: { slots[$0.id] })
    check(titles(phone.overdue) == titles([retro, nishiki, tap, starLate]), "Overdue runs most late first, ties in the order given")
    // The untimed keep the order the tasks came in: planters, carried, starPlanned, closing, subtask.
    check(titles(phone.scheduled) == titles([retro, nishiki, tap, starLate, earlier, feedback, scorecard, filters, deposit,
                                             planters, carried, starPlanned, closing, subtask]),
          "The phone's run: overdue, then 08:00, the 11:30 slot, 13:00, 16:30, 18:00, then the untimed")
    check(titles(phone.starred) == titles([overstory, ryokan]), "A starred task placed today leads the untimed starred")
    check(Set(phone.due.map(\.id)) == Set(agenda.due.map(\.id)) && Set(phone.planned.map(\.id)) == Set(agenda.planned.map(\.id))
          && phone.progress == agenda.progress,
          "The order never changes what Today holds")

    // The Mac's groups are exactly what its old code drew, across midnight too.
    for moment in [now, at(0, 0), at(0, 23, 59), at(1, 0, 1), at(-1, 12)] {
        let plannedOn = { (task: Block) in
            task.selectedForDay.map { calendar.startOfDay(for: $0) <= calendar.startOfDay(for: moment) } ?? false
        }
        let old = legacyToday(tasks, closing: [closing.id: true], isPlanned: plannedOn, now: moment)
        let new = TodayAgenda(tasks: tasks, closing: [closing.id], now: moment)
        check(titles(new.overdue) == titles(old.overdue) && titles(new.due) == titles(old.due)
              && titles(new.planned) == titles(old.planned) && titles(new.starred) == titles(old.starred)
              && titles(new.doneToday) == titles(old.done) && new.progress == old.progress && new.isClear == old.clear,
              "TodayAgenda draws the Mac's Today exactly as NXTodayPage did")
        let custom = TodayAgenda(tasks: tasks, now: moment, isPlanned: { $0.id == later.id })
        let customOld = legacyToday(tasks, closing: [:], isPlanned: { $0.id == later.id }, now: moment)
        check(titles(custom.planned) == titles(customOld.planned) && titles(custom.starred) == titles(customOld.starred),
              "The workbench's own planned rule decides Planned")
    }
    check(carried.isPlanned(on: now) && feedback.isPlanned(on: now) && !tomorrowPlan.isPlanned(on: now)
          && tomorrowPlan.isPlanned(on: at(1)) && !ryokan.isPlanned(on: now),
          "A task is planned from the day it was picked for")
}

// MARK: - Library and Inbox queue

do {
    let store = try makeStore()
    let inbox = store.inboxList()!
    let home = store.createList(title: "Home")
    let errands = store.createList(title: "Errands")
    func task(_ title: String, in list: TaskList, parent: Block? = nil, created: Date, _ configure: (Block) -> Void = { _ in }) -> Block {
        let block = store.appendBlock(kind: .task, text: title, to: DocumentContext(listID: list.id, rootBlockID: parent?.id))
        block.createdAt = created
        configure(block)
        return block
    }
    let gift = task("Gift ideas for Mika’s birthday", in: inbox, created: at(-4))
    _ = task("Ask Jun what she'd like", in: inbox, parent: gift, created: at(-4, 13))
    let books = task("Return the library books", in: inbox, created: at(-2)) { $0.isCompleted = true; $0.completedAt = at(-1) }
    let renew = task("Renew the loan", in: inbox, parent: books, created: at(-3))
    let dentist = task("Call the dentist back", in: inbox, created: at(-1))
    let photos = task("Send Jun the photos", in: inbox, created: at(0, 9))
    _ = task("Already done", in: inbox, created: at(0, 8)) { $0.isCompleted = true; $0.completedAt = at(0, 9) }
    _ = task("Filed away", in: home, created: at(-5))
    store.save()
    let library = try makeLibrary(store)
    check(titles(library.inboxQueue(kept: [], closing: [])) == titles([gift, renew, dentist, photos]),
          "The queue is open Inbox tasks, oldest first, a subtask carried by its open parent's card, one under done tasks its own")
    check(titles(library.inboxQueue(kept: [dentist.id], closing: [photos.id])) == titles([gift, renew]),
          "Kept tasks and tasks still closing leave the queue")
    check(titles(library.keptInbox(kept: [dentist.id, photos.id])) == titles([dentist, photos]),
          "Kept tasks are open Inbox tasks set aside, oldest first")
    check(library.isUnderOpenTask(library.tasks(in: inbox.id).first { $0.parentID == gift.id }!) && !library.isUnderOpenTask(renew),
          "Only an open task above one carries it")

    // Tasks in the order the lists show them, each under its own Sort.
    let later = task("Due later", in: errands, created: at(-1)) { $0.dueDate = at(3) }
    let soon = task("Due soon", in: errands, created: at(-1)) { $0.dueDate = at(1) }
    let under = task("Under the soon one", in: errands, parent: soon, created: at(-1))
    let undated = task("No date", in: errands, created: at(-1))
    store.setSorting(.dueDate, for: errands)
    let child = store.createChildList(in: home)!
    let sorted = try makeLibrary(store)
    let ordered = sorted.tasksInOutlineOrder(blocks: try store.context.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.trashID == nil })))
    check(titles(ordered.filter { $0.listID == errands.id }) == titles([soon, under, later, undated]),
          "A list's tasks follow its Sort, each carrying its subtasks")
    check(sorted.lists.map(\.id).prefix(1) == [inbox.id]
          && ordered.map(\.listID).firstIndex(of: errands.id)! > ordered.map(\.listID).lastIndex(of: inbox.id)!,
          "Lists come in sidebar order, Inbox first")
    check(sorted.outline([home]).map(\.depth) == [0, 1] && sorted.outline([home]).last?.id == child.id,
          "A nested list follows its parent, one level down")
    check(sorted.destinations.allSatisfy { !$0.isSystemInbox } && sorted.inbox?.id == inbox.id, "Inbox is never a destination")
}

// MARK: - Task query

do {
    let store = try makeStore()
    let kyoto = store.createList(title: "Weekend in Kyoto")
    let home = store.createList(title: "Home")
    let gtd = store.createList(title: "Getting things done")
    let travel = store.findOrCreateLabel(named: "travel")!
    let focus = store.findOrCreateLabel(named: "focus")!
    let deep = store.findOrCreateLabel(named: "Deep work")!
    func task(_ title: String, in list: TaskList, _ configure: (Block) -> Void = { _ in }) -> Block {
        let block = store.appendBlock(kind: .task, text: title, to: DocumentContext(listID: list.id))
        configure(block)
        return block
    }
    let passports = task("Renew passports", in: kyoto) { $0.dueDate = at(3, 0); $0.labelIDs = [travel.id] }
    let tour = task("Reserve the Nishiki market tour", in: kyoto) { $0.dueDate = at(-2, 0); $0.labelIDs = [travel.id] }
    let ryokan = task("Book the ryokan", in: kyoto) { $0.isStarred = true; $0.labelIDs = [travel.id]; $0.note = "Café near Gion" }
    let deposit = task("Pay deposit", in: kyoto) { $0.dueDate = at(0, 8); $0.includesTime = true; $0.labelIDs = [travel.id] }
    let passes = task("Pick up JR passes", in: kyoto) {
        $0.dueDate = at(4, 0); $0.labelIDs = [travel.id]; $0.isCompleted = true; $0.completedAt = at(0, 9)
    }
    let tap = task("Fix tap", in: home) { $0.dueDate = at(-1, 0); $0.priority = .high }
    let week = task("Plan the week", in: home) { $0.selectedForDay = at(0, 0) }
    let review = task("Write review", in: gtd) { $0.labelIDs = [focus.id] }
    store.save()
    let library = try makeLibrary(store)
    let pool = [passports, tour, ryokan, deposit, passes, tap, week, review]
    let query = TaskQuery(lists: library.lists, labels: library.labels)
    func run(_ text: String, _ q: TaskQuery = query, searchesNotes: Bool = false) -> [String] {
        titles(q.apply(text, to: pool, now: now, searchesNotes: searchesNotes))
    }

    check(query.key(for: kyoto) == "kyoto" && query.key(for: home) == "home" && query.key(for: library.inbox!) == "inbox",
          "Each list claims its last title word, and Inbox is inbox")
    check(query.key(for: gtd) == "done", "Without status words a list may claim done, as on the Mac")
    check(query.key(for: travel) == "#travel" && query.key(for: deep) == "#deep-work", "Labels are #name, spaces as dashes")
    check(query.vocab.contains { $0.word == "weekend" && $0.listID == kyoto.id }, "Longer title words name the list too")
    let parsed = query.parse("#travel overdue Kyoto nishiki")
    check(parsed.segments.map(\.kind) == [.label, nil, .date, nil, .list, nil, nil]
          && parsed.segments[4].listID == kyoto.id && parsed.segments[0].labelID == travel.id && parsed.segments[4].text == "Kyoto",
          "Segments keep the typed text and name their list or label")
    check(parsed.filter.labels == [travel.id] && parsed.filter.due == ["overdue"] && parsed.filter.lists == [kyoto.id]
          && parsed.filter.text == ["nishiki"], "The filter collects each kind of word")
    check(query.parse("#tra").ghost == "vel" && query.parse("ove").ghost == "rdue" && query.parse("overdue ").ghost.isEmpty
          && query.parse("today").ghost.isEmpty, "The ghost completes the last word, and nothing once it's whole")

    check(run("#travel") == titles([passports, tour, ryokan, deposit, passes]), "A label keeps its tasks, done ones too without status words")
    check(run("today") == titles([deposit]), "Today is by day: a time already past today is still today")
    check(run("overdue") == titles([tour, tap]), "Overdue is an earlier day")
    check(run("week") == titles([passports, deposit, passes]) && run("undated") == titles([ryokan, week, review])
          && run("tomorrow").isEmpty && run("later").isEmpty, "The other date words go by day offset")
    check(run("starred") == titles([ryokan]) && run("high") == titles([tap]), "Flags match their field")
    check(run("planned") == titles([week]), "Planned is picked for today, by default")
    check(titles(query.apply("planned", to: pool, now: now, isPlanned: { $0.id == passports.id })) == titles([passports]),
          "The Mac's workbench decides planned")
    check(run("kyoto overdue") == titles([tour]) && run("home kyoto").count == 7 && run("#travel #focus").count == 6,
          "Lists and labels match any of theirs; kinds combine")
    check(run("starred high").isEmpty, "Flags all have to match")
    check(run("RYOKAN") == titles([ryokan]) && run("gion").isEmpty, "Free words match the title only, as the Mac's Tasks")
    check(run("gion", searchesNotes: true) == titles([ryokan]) && run("cafe", searchesNotes: true) == titles([ryokan])
          && run("CAFÉ near", searchesNotes: true) == titles([ryokan]),
          "Find also reads the note, ignoring case and accents")

    let find = TaskQuery(lists: library.lists, labels: library.labels, readsStatus: true)
    check(find.key(for: gtd) == "getting-things-done", "With status words, done is reserved")
    check(find.parse("#travel done").segments.last?.kind == .status && find.parse("done").filter.status == ["done"],
          "Done is a status word on the phone")
    check(run("#travel", find) == titles([passports, tour, ryokan, deposit]) && run("#travel done", find).count == 5,
          "Find holds open tasks until done lets the done ones in")
    check(query.parse("done").segments.first?.kind == .list, "The Mac's field never reads done as status")

    check(TaskQuery.toggle("today", in: "#travel ") == "#travel today " && TaskQuery.toggle("today", in: "#travel Today ") == "#travel "
          && TaskQuery.toggle("today", in: "") == "today " && TaskQuery.toggle("today", in: "today") == "",
          "A chip adds or removes its word, leaving room to type")
    check(TaskQuery.words(in: "#Travel  Today") == ["#travel", "today"], "Words are lower-cased and split on spaces")
}

// MARK: - Capture

@Observable @MainActor
final class PhoneDraft: NXCaptureDraft {
    @ObservationIgnored let store: Store
    @ObservationIgnored let settings: AppSettings
    var captureText = ""
    var captureListID: UUID?
    var captureForToday = false
    var captureLabelID: UUID?

    init(store: Store, settings: AppSettings) {
        self.store = store
        self.settings = settings
        captureListID = store.inboxList()?.id
    }
}

do {
    let store = try makeStore()
    let kyoto = store.createList(title: "Weekend in Kyoto")
    let parse = CaptureParse("Buy yen for the trip fri 6pm ~15m #travel !high", reference: now)
    let snapshot = parse.snapshot()
    check(snapshot.title == "Buy yen for the trip" && snapshot.priority == .high && snapshot.estimateMinutes == 15
          && snapshot.labels == ["travel"] && snapshot.includesTime, "The snapshot carries the priority and estimate its tokens name")
    check(CaptureParse("Plain").snapshot().priority == .none && CaptureParse("Plain").snapshot().estimateMinutes == 0,
          "No tokens, no priority and the device's default estimate")
    check(CaptureParse("Long one ~2h !1").snapshot().estimateMinutes == 120 && CaptureParse("Long one ~2h !1").snapshot().priority == .low,
          "Hours become minutes")

    var saves = 0
    store.onDidSave = { saves += 1 }
    _ = try store.saveCapture(CaptureSnapshot(title: "Baseline"), destinationID: kyoto.id)
    let baseline = saves
    saves = 0
    let saved = try store.saveCapture(snapshot, destinationID: kyoto.id)
    check(saves == baseline, "Priority and estimate cost no saves of their own")
    check(saved.priority == .high && saved.schedulingEstimateMinutes == 15 && !store.context.hasChanges,
          "The capture saves its priority and estimate with it")
    let reader = ModelContext(store.context.container)
    let savedID = saved.id
    let stored = try reader.fetch(FetchDescriptor<Block>(predicate: #Predicate { $0.id == savedID })).first
    check(stored?.priorityRaw == TaskPriority.high.rawValue && stored?.schedulingEstimateMinutes == 15,
          "What's committed already holds the priority and estimate")
    check(store.recentActivity().filter { $0.blockID == saved.id }.map(\.kind) == [.created],
          "The capture is one creation in history")
    var huge = CaptureSnapshot(title: "Huge")
    huge.estimateMinutes = 1_000_000
    let capped = try store.saveCapture(huge, destinationID: nil)
    check(capped.schedulingEstimateMinutes == 60 * 24 * 28, "An estimate stays within the calendar's four-week limit")

    let suite = "SharedLogicChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let draft = PhoneDraft(store: store, settings: settings)
    draft.captureText = "Call mum tomorrow !2 ~45m #family"
    draft.captureListID = kyoto.id
    saves = 0
    guard case let .saved(block, opened) = draft.addCapture() else { preconditionFailure("The draft saves") }
    check(saves == baseline && block.priority == .medium && block.schedulingEstimateMinutes == 45 && block.listID == kyoto.id
          && opened.isEmpty && block.dueDate.map { NXFormat.dayOffset($0) } == 1 && store.labels(for: block).map(\.name) == ["family"],
          "A draft saves its task, date, label, priority and estimate in one capture")
    draft.captureText = "#travel ~15m"
    let before = store.blocks(inList: kyoto.id).count
    guard case .untitled = draft.addCapture() else { preconditionFailure("Tokens alone save nothing") }
    check(store.blocks(inList: kyoto.id).count == before && draft.captureText == "#travel ~15m",
          "Tokens alone save nothing and keep the draft")
    let archived = store.createList(title: "Old trip")
    store.setArchived(true, for: archived)
    draft.captureText = "Pack"
    draft.captureListID = archived.id
    guard case let .failed(notice) = draft.addCapture() else { preconditionFailure("An archived list takes no capture") }
    check(notice.failed && notice.text.hasPrefix("Task wasn’t added.") && draft.captureText == "Pack",
          "A capture that can't be added says why and keeps the draft")
    draft.captureListID = nil
    draft.captureForToday = true
    let label = store.findOrCreateLabel(named: "errands")!
    draft.captureLabelID = label.id
    draft.captureText = "Buy stamps"
    guard case let .saved(today, _) = draft.addCapture() else { preconditionFailure("The draft saves to Inbox") }
    check(today.listID == store.inboxList()?.id && today.dueDate == calendar.startOfDay(for: .now) && today.labelIDs == [label.id],
          "No list is Inbox; a draft for today is due today, and a label screen's label joins")
    let ids = [store.inboxList()!.id, kyoto.id]
    draft.captureListID = archived.id
    draft.cycleCaptureDestination(by: -1, among: ids)
    check(draft.captureListID == kyoto.id, "From a list no longer offered, Shift-Tab starts at the last")
    draft.cycleCaptureDestination(by: 1, among: ids)
    check(draft.captureListID == ids[0], "Tab wraps round to Inbox")
}

// MARK: - List page rows

// The Mac's `OutlineEditor.visibleRows` and `NextListScreen.completedGroups`
// before their projections moved to `BlockTree`.
func legacyTaskOutline(_ rows: [BlockRow]) -> [BlockRow] {
    var result: [BlockRow] = []
    var path: [(depth: Int, taskDepth: Int)] = []
    for var row in rows {
        while let last = path.last, last.depth >= row.depth { path.removeLast() }
        guard row.block.isTask else { continue }
        let taskDepth = path.last.map { $0.taskDepth + 1 } ?? 0
        path.append((row.depth, taskDepth))
        row.depth = taskDepth
        result.append(row)
    }
    return result
}

func legacyVisibleRows(_ live: [Block], sorting: ListSorting, tasksOnly: Bool, reveal: ContentReveal?, kept keptVisible: Set<UUID>) -> [BlockRow] {
    func projectedRows(expanding: Set<UUID>) -> [BlockRow] {
        BlockTree.sortingTaskRuns(in: BlockTree.flatten(live, expanding: expanding.union(reveal?.ancestorIDs ?? [])), by: sorting)
    }
    let kept = (reveal?.visiblePath ?? []).union(keptVisible)
    let unfolding = Set(live.lazy.filter { !OutlinePolicy.folds($0.kind) && $0.isCollapsed }.map(\.id))
    if tasksOnly {
        let rows = legacyTaskOutline(projectedRows(expanding: unfolding))
        return BlockTree.hidingCompletedTasks(in: rows, revealing: kept
            .union(BlockTree.completedTasksHoldingOpenTasks(in: live, atTaskLevel: true)))
    }
    let rows = projectedRows(expanding: unfolding)
    let unfolded = reveal?.blockID.map { Set(BlockTree.enclosingSections(of: $0, in: rows)) } ?? []
    return BlockTree.hidingCompletedTasks(in: BlockTree.hidingCollapsedSections(in: rows, revealing: unfolded),
                                          revealing: kept.union(BlockTree.completedTasksHoldingOpenTasks(in: live)))
}

func legacyCompleted(_ tasks: [Block], closing: [UUID: Bool], inDocument: Set<UUID>, tasksOnly: Bool, block: (UUID) -> Block?) -> [Block] {
    let byID = tasksOnly ? Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) : [:]
    return tasks.filter {
        $0.isCompleted && closing[$0.id] == nil && !inDocument.contains($0.id)
            && ($0.parentID == nil || tasksOnly && !BlockTree.hasTaskAncestor($0) { byID[$0] ?? block($0) })
    }
        .sorted(by: Block.byCompletionDate)
}

do {
    let store = try makeStore()
    let list = store.createList(title: "Weekend in Kyoto")
    func line(_ kind: BlockKind, _ text: String, under parent: Block? = nil, _ configure: (Block) -> Void = { _ in }) -> Block {
        let block = store.appendBlock(kind: kind, text: text, to: DocumentContext(listID: list.id, rootBlockID: parent?.id))
        configure(block)
        return block
    }
    let heading = line(.heading1, "Before we go")
    let passports = line(.task, "Renew passports") { $0.dueDate = at(3) }
    let ryokan = line(.task, "Book the ryokan") { $0.isCollapsed = true }
    let gion = line(.task, "Compare Gion vs Arashiyama", under: ryokan) { $0.isCompleted = true; $0.completedAt = at(0, 9) }
    let kasuga = line(.task, "Email Kasuga", under: ryokan)
    let notes = line(.paragraph, "Some notes")
    let packing = line(.bullet, "Packing")
    let adapters = line(.task, "Pack adapters", under: packing)
    let old = line(.task, "Old packing list") { $0.isCompleted = true; $0.completedAt = at(-1) }
    let parent = line(.task, "Done parent") { $0.isCompleted = true; $0.completedAt = at(0, 8) }
    let open = line(.task, "Still open", under: parent)
    let deposit = line(.task, "Pay the ryokan deposit") { $0.dueDate = at(0, 18); $0.includesTime = true }
    let laterHeading = line(.heading2, "Later") { $0.isCollapsed = true }
    let after = line(.task, "After the folded heading") { $0.dueDate = at(1) }
    store.save()
    let live = store.blocks(inList: list.id)

    let tasksRows = BlockTree.visibleRows(of: live, sorting: .manual, tasksOnly: true)
    check(tasksRows.map(\.id) == [passports, ryokan, adapters, parent, open, deposit, after].map(\.id),
          "Tasks shows only tasks: a folded task hides its subtasks, a heading folds nothing, a done top-level task leaves unless it holds an open one")
    check(tasksRows.map(\.depth) == [0, 0, 0, 0, 1, 0, 0], "Each task is as deep as the tasks above it")
    check(tasksRows[1].isCollapsed && tasksRows[1].hasChildren, "A folded task says so, for its chevron")
    let documentRows = BlockTree.visibleRows(of: live, sorting: .manual, tasksOnly: false)
    check(documentRows.map(\.id) == [heading, passports, ryokan, notes, packing, adapters, parent, open, deposit, laterHeading].map(\.id),
          "The document shows every kind, hides a folded heading's section and the settled done tasks")
    check(BlockTree.visibleRows(of: live, sorting: .manual, tasksOnly: false, revealing: after.id).last?.id == after.id,
          "A revealed line shows through the heading folding it")

    // Local folds never write the synced one.
    let folded = BlockTree.visibleRows(of: live, sorting: .manual, tasksOnly: true, expanding: [ryokan.id], collapsing: [parent.id, packing.id])
    check(folded.map(\.id) == [passports, ryokan, gion, kasuga, adapters, parent, deposit, after].map(\.id),
          "A viewer's own folds open a folded task and fold an open one; a list item never folds")
    check(folded.first { $0.id == parent.id }?.isCollapsed == true && !parent.isCollapsed && ryokan.isCollapsed && !store.context.hasChanges,
          "Folding on the viewer leaves the stored folds alone")
    check(folded.first { $0.id == gion.id }?.depth == 1, "A done subtask stays struck where it was ticked")

    let page = BlockTree.listPage(live, sorting: list.sorting)
    check(page.rows == tasksRows && page.completed.map(\.id) == [old.id] && page.openCount == 7,
          "The phone's page: Tasks rows, the done fold without what the rows still draw, and seven open")
    let closingPage = BlockTree.listPage(live, sorting: list.sorting, closing: [old.id])
    check(closingPage.rows.contains { $0.id == old.id } && closingPage.completed.isEmpty && closingPage.openCount == 8,
          "A task still closing stays where it was and counts as open")
    let documentPage = BlockTree.listPage(live, sorting: list.sorting, tasksOnly: false)
    check(documentPage.rows == documentRows && documentPage.completed.map(\.id) == [old.id], "The document page too")
    check(BlockTree.taskOutline(BlockTree.flatten(live, respectCollapse: false)).map(\.depth)
          == [0, 0, 1, 1, 0, 0, 0, 1, 0, 0], "taskOutline re-depths the tasks under the tasks above")

    // The Mac's projection is exactly the old one, in every presentation.
    let reveals: [ContentReveal?] = [
        nil,
        ContentReveal(destination: .block(gion.id), listID: list.id, taskID: gion.id, ancestorIDs: [ryokan.id], field: .text, query: ""),
        ContentReveal(destination: .block(after.id), listID: list.id, taskID: after.id, ancestorIDs: [], field: .text, query: ""),
    ]
    for tasksOnly in [true, false] {
        for sorting in [ListSorting.manual, .dueDate, .alphabetical] {
            for reveal in reveals {
                for kept in [[], [old.id]] as [Set<UUID>] {
                    let new = BlockTree.visibleRows(of: live, sorting: sorting, tasksOnly: tasksOnly,
                                                    expanding: reveal?.ancestorIDs ?? [],
                                                    keeping: (reveal?.visiblePath ?? []).union(kept), revealing: reveal?.blockID)
                    check(new == legacyVisibleRows(live, sorting: sorting, tasksOnly: tasksOnly, reveal: reveal, kept: kept),
                          "BlockTree.visibleRows draws what OutlineEditor did")
                }
            }
            let tasks = live.filter(\.isTask)
            for drawn in [[], [parent.id, old.id]] as [Set<UUID>] {
                let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let new = BlockTree.completedFold(of: tasks, drawn: drawn, closing: [old.id], tasksOnly: tasksOnly) {
                    byID[$0] ?? store.block(id: $0)
                }
                let legacy = legacyCompleted(tasks, closing: [old.id: true], inDocument: drawn, tasksOnly: tasksOnly) { store.block(id: $0) }
                check(new.map(\.id) == legacy.map(\.id), "The done fold lists what the Mac's Completed group did")
            }
        }
    }
}

// MARK: - Compact wording

do {
    var tokyo = Calendar(identifier: .gregorian)
    tokyo.locale = Locale(identifier: "en_US")
    tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    func day(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, year: Int = 2026) -> Date {
        tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    let wednesday = day(9, 23, 10, 10)
    func due(_ date: Date?, timed: Bool = false, done: Bool = false) -> CompactText.Due? {
        CompactText.due(date, includesTime: timed, isCompleted: done, now: wednesday, calendar: tokyo)
    }
    check(due(day(9, 20)) == .init(text: "3d late", tone: .late, dayOffset: -3), "An earlier day is Nd late")
    check(due(day(9, 22, 23, 59), timed: true)?.text == "1d late", "Late goes by day")
    check(due(day(9, 23, 8), timed: true) == .init(text: "08:00", tone: .today, dayOffset: 0),
          "A time already past today is today's time, not late")
    check(due(day(9, 23, 18), timed: true)?.text == "18:00" && due(day(9, 23))?.text == "Today", "Today is its time, or Today")
    check(due(day(9, 24)) == .init(text: "Tomorrow", tone: .upcoming, dayOffset: 1) && due(day(9, 24, 0, 30), timed: true)?.text == "Tomorrow",
          "Tomorrow, in the calendar's own time zone")
    check([25, 26, 27, 29].map { due(day(9, $0))!.text } == ["Fri", "Sat", "Sun", "Tue"], "Within the week, a bare weekday")
    check(due(day(9, 30))?.text == "Wed 30 Sep" && due(day(10, 2))?.text == "Fri 2 Oct", "Past the week, weekday, day and month")
    check(due(day(1, 2, year: 2027))?.text == "Sat 2 Jan 2027", "Another year's day names the year")
    check(due(nil) == nil && due(day(9, 20), done: true) == nil, "Undated or done, no due text")
    check(CompactText.day(day(9, 22), now: wednesday, calendar: tokyo) == "Yesterday"
          && CompactText.day(day(9, 1), now: wednesday, calendar: tokyo) == "Tue 1 Sep", "Days behind read as days too")
    check(CompactText.captureWhen(day(9, 25, 18), includesTime: true, now: wednesday, calendar: tokyo) == "Fri 25, 18:00"
          && CompactText.captureWhen(day(9, 23), includesTime: false, now: wednesday, calendar: tokyo) == "Today"
          && CompactText.captureWhen(day(9, 24, 9), includesTime: true, now: wednesday, calendar: tokyo) == "Tomorrow, 09:00"
          && CompactText.captureWhen(day(10, 2, 7, 5), includesTime: true, now: wednesday, calendar: tokyo) == "Fri 2 Oct, 07:05",
          "The capture chip names the day, with its date, then the time")
    check(CompactText.estimate(15) == "15 min" && CompactText.estimate(90) == "90 min", "Estimates in minutes")
    func ago(_ seconds: TimeInterval) -> Date { wednesday.addingTimeInterval(-seconds) }
    let ages: [String] = ([2 * 3600, 5 * 3600, 26 * 3600, 4 * 86_400] as [TimeInterval]).map { CompactText.age(of: ago($0), now: wednesday) }
    check(ages == ["2h", "5h", "1d", "4d"], "Inbox ages are whole hours and days")
    check(CompactText.age(of: ago(180), now: wednesday) == "now" && CompactText.age(of: ago(17 * 60), now: wednesday) == "15m"
          && CompactText.age(of: wednesday.addingTimeInterval(60), now: wednesday) == "now", "Under an hour, fives of minutes")
    check(CompactText.ageChange(of: ago(17 * 60), after: wednesday) == wednesday.addingTimeInterval(3 * 60),
          "The age next changes on the next five minutes")
    let spans: [TimeInterval] = [4 * 86_400, 5 * 3600, 2 * 3600, 3600, 30 * 3600, 2 * 86_400, 12 * 60, 90, 30]
    let words: [String] = spans.map { CompactText.ago(ago($0), now: wednesday) }
    check(words == ["4 days ago", "5 hours ago", "2 hours ago", "1 hour ago", "yesterday", "2 days ago", "12 minutes ago",
                    "1 minute ago", "just now"], "Ago in words, in the same hours and days as the age")
    check(CompactText.captured(ago(4 * 86_400), now: wednesday) == "Captured 4 days ago", "The triage card's line")
    var london = tokyo
    london.locale = Locale(identifier: "en_GB")
    check(CompactText.day(day(10, 2), now: wednesday, calendar: london) == "Fri 2 \(london.shortMonthSymbols[9])"
          && CompactText.weekday(day(9, 26), calendar: london) == london.shortWeekdaySymbols[6],
          "Day and month names come from the calendar's locale")
}

print("Passed \(checks) shared logic checks")
