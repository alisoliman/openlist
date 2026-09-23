import Foundation
import Observation
import SwiftData
import os

var checks = 0
func check(_ value: @autoclosure () throws -> Bool, _ message: String) {
    checks += 1
    guard (try? value()) == true else { fatalError("FAIL: \(message)") }
}
func ms(_ start: ContinuousClock.Instant) -> Double {
    let elapsed = start.duration(to: .now).components
    return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
}
let container = try ModelContainer(for: Block.self, TaskList.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
let context = ModelContext(container)
context.autosaveEnabled = false
let list = TaskList(title: "Project collection")
let archived = TaskList(title: "Project collection")
archived.isArchived = true
let alias = TaskList(title: "Merged project")
alias.mergedIntoID = list.id
let lists = [list, archived, alias]
for value in lists { context.insert(value) }
var blocks: [Block] = []
func add(_ title: String, kind: BlockKind = .task, parent: Block? = nil, in listID: UUID? = nil) -> Block {
    let value = Block(kind: kind, text: title, listID: listID ?? list.id, parentID: parent?.id, sortIndex: Double(blocks.count))
    value.createdAt = Date(timeIntervalSince1970: 1)
    value.updatedAt = Date(timeIntervalSince1970: 2)
    context.insert(value)
    blocks.append(value)
    return value
}
for _ in 0..<205 { _ = add("Duplicate needle") }
let collapsed = add("Ancestor context")
collapsed.isCollapsed = true
collapsed.isCompleted = true
let nested = add("Nested heading", kind: .heading2, parent: collapsed)
nested.isCollapsed = true
let paragraph = add("Exact needle paragraph", kind: .paragraph, parent: nested)
let noteTask = add("Note only match")
noteTask.note = String(repeating: "🧑🏽‍💻 Context café. ", count: 80) + "needle target résumé" + String(repeating: " ending", count: 50)
let archivedTask = add("Archived needle", in: archived.id)
let completed = add("Completed needle")
completed.isCompleted = true
let unrelated = add("Unrelated")
let orphan = add("Orphan needle", in: UUID())
let unfiled = add("Unfiled needle")
unfiled.listID = nil
try context.save()

func project(_ options: SearchOptions, source: [Block]? = nil) throws -> [SearchHit] {
    try SearchProjection(corpus: SearchCorpus(blocks: source ?? blocks, lists: lists), options: options).hits
}
let options = SearchOptions(query: "needle")
let allHits = try project(options)
check(allHits.count == 211, "all matches are counted beyond the old 80 cap")
check(Set(allHits.map(\.id)).count == allHits.count, "duplicate titles retain independent IDs")
check(allHits == (try project(options, source: blocks.reversed())), "tied order is independent of source fetch order")
check(allHits.first { $0.id == .block(paragraph.id) }?.context.contains("Ancestor context › Nested heading") == true, "paragraph exposes ancestor context")
check(allHits.first { $0.id == .block(paragraph.id) }?.context.contains("Completed") == true, "completed ancestor is explicit")
let noteHit = allHits.first { $0.id == .block(noteTask.id) }!
check(noteHit.field == .note && noteHit.snippet.contains("needle target résumé") && noteHit.snippet.hasPrefix("…"), "deep note match gets useful snippet and exact field")
check(try project(SearchOptions(query: " "), source: blocks).isEmpty, "whitespace query shows no corpus")
check(try project(SearchOptions(query: "\n needle \t")).count == allHits.count, "query trims all outer whitespace")
check(try project(SearchOptions(query: "needle", scope: .lists)).isEmpty, "list scope excludes content")
check(try project(SearchOptions(query: "needle", scope: .notes)).map(\.id) == [.block(paragraph.id)], "notes scope retains existing non-task semantics")
let tasksOnly = try project(SearchOptions(query: "needle", scope: .tasks))
check(!tasksOnly.contains { $0.id == .block(paragraph.id) } && tasksOnly.contains { $0.id == noteHit.id }, "task notes remain task-scope matches")
let noArchived = try project(SearchOptions(query: "needle", includesArchived: false))
check(!noArchived.contains { $0.id == .block(archivedTask.id) }, "archive option filters content")
let noCompleted = try project(SearchOptions(query: "needle", includesCompleted: false))
check(!noCompleted.contains { $0.id == .block(completed.id) || $0.id == .block(paragraph.id) }, "completion option excludes completed ancestors and tasks")
check(try project(SearchOptions(query: "project", scope: .lists)).count == 2, "list results include archive and omit merged alias")
check(try project(SearchOptions(query: "project", scope: .lists, includesArchived: false)).count == 1, "list archive option is explicit")
let listHits = try project(SearchOptions(query: "project", scope: .lists))
check(listHits.first { $0.id == .list(list.id) }?.context == "List" && listHits.first { $0.id == .list(archived.id) }?.context == "List · Archived",
      "list hits say they're a list rather than repeating their own name")
check(listHits.allSatisfy { $0.emoji == nil && $0.symbol == "square.2.layers.3d" }, "list hits use the layers symbol")
let child = TaskList(title: "Needle child list")
child.parentListID = list.id
let childHit = try SearchProjection(corpus: SearchCorpus(blocks: [], lists: lists + [child]), options: SearchOptions(query: "child list")).hits
check(childHit.first?.context == "List · Project collection", "a nested list hit names where it sits")
check(allHits.first { $0.id == .block(completed.id) }?.context == "📋 Project collection · Completed", "task context puts its state after its place")
for (haystack, needle) in [("café", "CAFE"), ("cafe\u{301}", "CAFÉ"), ("résumé", "resume"), ("ＡＢＣ", "abc"), ("🧑🏽‍💻 note", "🧑🏽‍💻")] {
    check(SearchProjection.matches(haystack, needle), "Unicode match \(needle)")
    check(SearchProjection.snippet(haystack, matching: needle).contains(haystack), "snippet keeps complete graphemes")
}

var selection = SearchResultSelection()
let ids = allHits.map(\.id)
selection.reconcile(ids)
check(selection.limit == 80 && selection.selected == ids.first, "first page and selection")
selection.move(1, in: ids)
check(selection.keyboardDestination(focused: ids[0]) == ids[1], "Tab-focused A then Down to B makes Return activate B before focus transfer")
selection.reconcile(ids, reset: true)
for index in 1..<ids.count {
    selection.move(1, in: ids)
    check(selection.selected == ids[index] && selection.limit > index, "Down reaches result \(index + 1) including page boundaries")
}
selection.move(1, in: ids)
check(selection.selected == ids.last, "Down stops at final result")
selection.move(-1, in: ids)
check(selection.selected == ids[ids.count - 2], "Up moves backward")
selection.reconcile(Array(ids.prefix(3)))
check(selection.selected == ids.first, "deletion or filter change reconciles stale selection")
selection.reconcile(ids, reset: true)
selection.loadMore(total: ids.count)
check(selection.limit == 160, "explicit pagination preserves honest count")

let reveal = try ContentReveal.resolve(.block(paragraph.id), query: "needle", blocks: blocks, lists: lists)
check(reveal.listID == list.id && reveal.taskID == nil && reveal.blockID == paragraph.id, "non-task targets full owner document")
check(reveal.ancestorIDs == [nested.id, collapsed.id], "nested reveal includes exact collapsed path")
let ordinaryRows = BlockTree.hidingCompletedTasks(in: BlockTree.flatten(blocks.filter { $0.listID == list.id }))
check(!ordinaryRows.contains { $0.id == paragraph.id }, "baseline hides completed collapsed target below fold")
let visible = BlockTree.hidingCompletedTasks(in: BlockTree.flatten(blocks.filter { $0.listID == list.id }, expanding: reveal.ancestorIDs), revealing: reveal.visiblePath)
check(visible.contains { $0.id == paragraph.id && $0.depth == 2 }, "reveal exposes target at original hierarchy")
check(visible.firstIndex { $0.id == paragraph.id }! > 80, "reveal fixture is below fold")
check(!visible.contains { $0.id == completed.id }, "other completed branch remains hidden")
check(collapsed.isCollapsed && collapsed.isCompleted && nested.isCollapsed && archived.isArchived && !context.hasChanges, "reveal projection never rewrites stored status or collapse")
let taskReveal = try ContentReveal.resolve(noteHit.id, field: noteHit.field, query: "needle", blocks: blocks, lists: lists)
check(taskReveal.taskID == noteTask.id && taskReveal.field == .note, "task note reveals exact inspector field")
let navigator = Navigator()
navigator.reveal(reveal)
check(navigator.route == .list(list.id) && navigator.openTaskID == nil && navigator.selection == [paragraph.id], "reveal navigation selects exact paragraph and closes inspector")
navigator.reveal(taskReveal)
check(navigator.openTaskID == noteTask.id && navigator.contentReveal == taskReveal, "same-list task reveal replaces previous request")
let activation = navigator.searchActivation
navigator.closeTask()
check(navigator.contentReveal == nil && navigator.searchActivation == activation, "closing inspector ends temporary reveal")
navigator.reveal(reveal)
navigator.go(to: .today)
check(navigator.contentReveal == nil, "navigation ends temporary expansion")
navigator.goBack()
check(navigator.contentReveal == nil, "back does not persist temporary reveal")
for destination in [SearchDestination.block(UUID()), .block(orphan.id), .block(unfiled.id), .list(UUID()), .list(alias.id)] {
    do { _ = try ContentReveal.resolve(destination, blocks: blocks, lists: lists); check(false, "missing hit must fail explicitly") }
    catch { check(!error.localizedDescription.isEmpty, "missing hit has understandable unavailable message") }
}

let formerTitle = paragraph.text
paragraph.text = "Replaced content"
do { _ = try ContentReveal.resolve(.block(paragraph.id), query: "needle", blocks: blocks, lists: lists); check(false, "changed hit cannot reveal unrelated content") }
catch { check(error is ContentReveal.Unavailable, "stale text explains result is no longer matching") }
paragraph.note = "needle moved to note"
let movedField = try ContentReveal.resolve(.block(paragraph.id), field: .text, query: "needle", blocks: blocks, lists: lists)
check(movedField.field == .note, "resolver follows the live matching field after editing")
paragraph.text = formerTitle
paragraph.note = ""
list.summary = "Hidden description needle"
let summaryRequest = try ContentReveal.resolve(.list(list.id), field: .summary, query: "needle", blocks: blocks, lists: lists)
navigator.go(to: .list(list.id))
navigator.reveal(summaryRequest)
check(navigator.route == .list(list.id) && navigator.contentReveal?.revealsSummary(for: list.id) == true, "same-page summary reveal temporarily exposes hidden description")
let userShowsSummary = false
check(userShowsSummary || summaryRequest.revealsSummary(for: list.id), "reveal visibility composes with hidden local preference")
navigator.finishReveal()
check(!userShowsSummary && navigator.contentReveal == nil && list.summary == "Hidden description needle", "finishing summary reveal preserves preference and content")
let missingParent = add("Orphan parent target", kind: .paragraph)
missingParent.parentID = UUID()
let orphanRequest = try ContentReveal.resolve(.block(missingParent.id), blocks: blocks, lists: lists)
check(orphanRequest.ancestorIDs.isEmpty && BlockTree.flatten(blocks).contains { $0.id == missingParent.id && $0.depth == 0 }, "orphan parent is projected visibly at root")
let cycleA = add("Cycle A", kind: .paragraph)
let cycleB = add("Cycle B", kind: .paragraph, parent: cycleA)
cycleA.parentID = cycleB.id
cycleA.isCollapsed = true
cycleB.isCollapsed = true
let cycleRequest = try ContentReveal.resolve(.block(cycleA.id), blocks: blocks, lists: lists)
check(BlockTree.flatten(blocks, expanding: cycleRequest.ancestorIDs).contains { $0.id == cycleA.id }, "cycle-safe reveal reaches deterministic projected root or child")

func observes(_ mutate: () -> Void, _ message: String) {
    let changed = OSAllocatedUnfairLock(initialState: false)
    withObservationTracking { _ = SearchCorpus(blocks: blocks, lists: lists) } onChange: { changed.withLock { $0 = true } }
    mutate()
    check(changed.withLock { $0 }, message)
}
observes({ unrelated.text = "Live needle" }, "nonmatch title becoming a match invalidates snapshot")
observes({ unrelated.note = "Live note needle" }, "nonmatch note changes invalidate snapshot")
observes({ list.title = "Renamed collection" }, "list rename invalidates context")
observes({ archived.isArchived = false }, "archive updates invalidate snapshot")
observes({ collapsed.isCompleted = false }, "ancestor completion invalidates snapshot")
observes({ paragraph.parentID = collapsed.id }, "reparent updates invalidate ancestor context")

let session = SearchSession()
session.update(corpus: SearchCorpus(blocks: blocks, lists: lists))
for query in ["needle", "absent", "project", "needle", "Live needle"] { session.update(options: SearchOptions(query: query)) }
for _ in 0..<1000 where session.isSearching { try await Task.sleep(for: .milliseconds(2)) }
check(!session.isSearching && session.hits.map(\.id) == [.block(unrelated.id)], "latest rapid query wins over superseded responses")
unrelated.text = "No longer matches"
unrelated.note = ""
session.update(corpus: SearchCorpus(blocks: blocks, lists: lists))
for _ in 0..<1000 where session.isSearching { try await Task.sleep(for: .milliseconds(2)) }
check(session.hits.isEmpty, "same-query corpus edits remove stale hit")
unrelated.note = "Live needle"
session.update(corpus: SearchCorpus(blocks: blocks, lists: lists))
for _ in 0..<1000 where session.isSearching { try await Task.sleep(for: .milliseconds(2)) }
check(session.hits.map(\.id) == [.block(unrelated.id)] && session.hits.first?.field == .note, "same-query live note edit adds hit")
context.delete(unrelated)
do { _ = try ContentReveal.resolve(.block(unrelated.id), blocks: blocks, lists: lists); check(false, "deleted retained hit must fail") }
catch { check(true, "deleted retained hit is unavailable") }
session.update(corpus: SearchCorpus(blocks: blocks, lists: lists))
for _ in 0..<1000 where session.isSearching { try await Task.sleep(for: .milliseconds(2)) }
check(session.hits.isEmpty, "deleted hit leaves current search")

// The last answer stays listed while a newer query runs, so typing narrows
// the list instead of blanking it.
session.update(options: SearchOptions(query: "needle"))
for _ in 0..<1000 where session.isSearching { try await Task.sleep(for: .milliseconds(2)) }
let settled = session.hits
check(!settled.isEmpty && session.hitsOptions == SearchOptions(query: "needle") && !session.isSlow, "a settled search lists its answer")
session.update(options: SearchOptions(query: "needle target"))
check(session.isSearching && session.hits == settled && session.hitsOptions == SearchOptions(query: "needle"),
      "the previous answer stays listed, marked as older, until the new one arrives")
for _ in 0..<1000 where session.isSearching { try await Task.sleep(for: .milliseconds(2)) }
check(session.hitsOptions == SearchOptions(query: "needle target") && session.hits.map(\.id) == [noteHit.id], "the new answer replaces the old")
session.update(options: SearchOptions(query: " "))
check(session.hits.isEmpty && !session.isSearching && session.hitsOptions.needle.isEmpty, "clearing the query clears the list at once")

// Open tasks carry their due date for the subtitle; finished ones don't.
let dueTask = Block(kind: .task, text: "Due soon", listID: list.id)
dueTask.dueDate = Date(timeIntervalSince1970: 1_800_000_000)
let doneDue = Block(kind: .task, text: "Due and done", listID: list.id)
doneDue.dueDate = dueTask.dueDate
doneDue.isCompleted = true
let dueHits = try SearchProjection(corpus: SearchCorpus(blocks: [dueTask, doneDue], lists: lists), options: SearchOptions(query: "due")).hits
check(dueHits.first { $0.id == .block(dueTask.id) }?.dueDate == dueTask.dueDate, "open task hits carry their due date")
check(dueHits.first { $0.id == .block(doneDue.id) }?.dueDate == nil, "completed task hits show no due date")

// Same saved 10k corpus and query mix as the pre-change benchmark. Timings are
// evidence, not hardware-dependent pass/fail thresholds.
let performanceContainer = try ModelContainer(for: Block.self, TaskList.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
let performanceContext = ModelContext(performanceContainer)
performanceContext.autosaveEnabled = false
let performanceList = TaskList(title: "Synthetic project")
performanceContext.insert(performanceList)
for i in 0..<10_000 {
    let item = Block(kind: i % 4 == 0 ? .paragraph : .task,
        text: "Project \(i) — Review café 🧑🏽‍💻 notes and prepare the next milestone for the design team.", listID: performanceList.id)
    item.note = i % 3 == 0 ? String(repeating: "Planning context and meeting notes. ", count: 12) + "needle \(i)" : ""
    item.isCompleted = i % 5 == 0
    item.updatedAt = Date(timeIntervalSince1970: Double(i))
    performanceContext.insert(item)
}
try performanceContext.save()
let performanceBlocks = try performanceContext.fetch(FetchDescriptor<Block>())
let snapshotStart = ContinuousClock.now
let corpus = SearchCorpus(blocks: performanceBlocks, lists: [performanceList])
print("10k snapshot_main_ms=\(String(format: "%.2f", ms(snapshotStart)))")
for query in ["project", "needle 9999", "absent query", "café"] {
    var times: [Double] = []
    var count = 0
    for _ in 0..<7 {
        let start = ContinuousClock.now
        count = try await Task.detached { try SearchProjection(corpus: corpus, options: SearchOptions(query: query)).hits.count }.value
        times.append(ms(start))
    }
    print("10k worker query=\(query) total=\(count) median_ms=\(String(format: "%.2f", times.sorted()[3])) max_ms=\(String(format: "%.2f", times.max()!))")
    if query == "project" { check(count == 10_001, "10k matching blocks plus matching list are all reachable") }
}
session.update(corpus: corpus)
let rapidStart = ContinuousClock.now
for query in ["p", "pr", "pro", "proj", "project", "needle 9999"] { session.update(options: SearchOptions(query: query)); await Task.yield() }
for _ in 0..<2000 where session.isSearching { try await Task.sleep(for: .milliseconds(2)) }
check(session.hits.count == 1 && session.hits.first?.snippet.contains("needle 9999") == true, "10k rapid typing publishes only latest query")
print("10k rapid_latest_ms=\(String(format: "%.2f", ms(rapidStart)))")
let obsolete = Task.detached { try SearchProjection(corpus: corpus, options: SearchOptions(query: "project")) }
obsolete.cancel()
do { _ = try await obsolete.value; check(false, "cancelled projection must stop") }
catch is CancellationError { check(true, "cancelled projection stops cooperatively") }
session.cancel()
print("✅ \(checks) search checks passed (complete results, reveal, observation, cancellation, 10k corpus)")
