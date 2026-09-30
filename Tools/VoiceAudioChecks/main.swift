// Runs recordings through voice capture end to end, as the microphone
// would: the system's on-device speech model, Apple Intelligence where this
// Mac has it, then `Store.saveSpokenTasks` into a library with lists and
// labels. Checks each task lands in the right list with its day, time,
// repeat, labels, priority and estimate. Recordings are made with `say`,
// or read from OPENLIST_VOICE_RECORDINGS (a folder of <scenario>.<ext>
// files named as below) to try real voices.

import AVFoundation
import Foundation
import SwiftData

var checks = 0
var failures: [String] = []
func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition { failures.append(message) }
}

let schema = Schema([TaskList.self, Block.self, SidebarSection.self, TaskLabel.self, Attachment.self, ActivityEvent.self,
                     SchedulePlacement.self, WorkSession.self, CompletionRecord.self])
let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
let store = Store(context: container.mainContext)
store.context.autosaveEnabled = false
store.bootstrap()
let inbox = store.inboxList()!
let kyoto = store.createList(title: "Kyoto trip")
let work = store.createList(title: "Work")
let groceries = store.createList(title: "Groceries")
_ = store.findOrCreateLabel(named: "travel")
_ = store.findOrCreateLabel(named: "errands")
let vocabulary = SpokenCapture.Vocabulary(lists: [inbox, kyoto, work, groceries], labels: store.allLabels())
let calendar = Calendar.current

struct Scenario {
    var name: String
    var said: String
    /// Checks the tasks filed; `intelligent` says whether Apple Intelligence read them.
    var expect: (_ tasks: [Block], _ intelligent: Bool) -> Void
}

func title(_ task: Block, has words: String...) -> Bool {
    words.allSatisfy { task.text.localizedCaseInsensitiveContains($0) }
}
func isDay(_ date: Date?, offset: Int, hour: Int? = nil, minute: Int = 0) -> Bool {
    guard let date, let expected = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now)) else { return false }
    guard calendar.isDate(date, inSameDayAs: expected) else { return false }
    guard let hour else { return true }
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return parts.hour == hour && parts.minute == minute
}
func weekday(_ date: Date?) -> Int? { date.map { calendar.component(.weekday, from: $0) } }
func labels(_ task: Block) -> [String] { store.labels(for: task).map(\.name).sorted() }

let scenarios = [
    Scenario(name: "call-mum", said: "Remind me to call mom tomorrow at 5 PM.") { tasks, _ in
        check(tasks.count == 1, "call-mum: one task")
        guard let task = tasks.first else { return }
        check(title(task, has: "call", "mom") && !title(task, has: "remind"), "call-mum: titled without the lead-in (\(task.text))")
        check(task.listID == inbox.id, "call-mum: into Inbox, where the capture is aimed")
        check(isDay(task.dueDate, offset: 1, hour: 17) && task.includesTime, "call-mum: due tomorrow at 5pm")
    },
    Scenario(name: "ryokan", said: "Pay the ryokan deposit by Friday on my Kyoto trip list. Tag it travel. It takes 15 minutes.") { tasks, _ in
        check(tasks.count == 1, "ryokan: one task")
        guard let task = tasks.first else { return }
        check(title(task, has: "deposit"), "ryokan: titled (\(task.text))")
        check(task.listID == kyoto.id, "ryokan: into the Kyoto trip list it named")
        check(weekday(task.dueDate) == 6 && !task.includesTime, "ryokan: due Friday")
        check(labels(task) == ["travel"], "ryokan: labelled travel (\(labels(task)))")
        check(task.schedulingEstimateMinutes == 15, "ryokan: takes 15 minutes")
    },
    Scenario(name: "three-tasks", said: "Remind me to call the bank tomorrow at 9, and buy oat milk on my groceries list. Oh, and book the dentist next Tuesday, it's urgent.") { tasks, intelligent in
        guard intelligent else {
            check(tasks.count == 1, "three-tasks: without Apple Intelligence, everything said is one task")
            return
        }
        check(tasks.count == 3, "three-tasks: three tasks (\(tasks.map(\.text)))")
        guard tasks.count == 3 else { return }
        check(title(tasks[0], has: "bank") && tasks[0].listID == inbox.id && isDay(tasks[0].dueDate, offset: 1, hour: 9),
              "three-tasks: the bank tomorrow at 9, in Inbox")
        check(title(tasks[1], has: "milk") && tasks[1].listID == groceries.id && tasks[1].dueDate == nil,
              "three-tasks: oat milk on Groceries, no day (\(tasks[1].text))")
        check(title(tasks[2], has: "dentist") && tasks[2].priority == .high && weekday(tasks[2].dueDate) == 3,
              "three-tasks: the dentist on Tuesday, high priority")
    },
    Scenario(name: "report", said: "Finish the quarterly report for the 3rd of October at 2:30, on my work list. High priority, about 2 hours.") { tasks, _ in
        check(tasks.count == 1, "report: one task")
        guard let task = tasks.first else { return }
        check(title(task, has: "quarterly report"), "report: titled (\(task.text))")
        check(task.listID == work.id, "report: into Work")
        let parts = task.dueDate.map { calendar.dateComponents([.month, .day, .hour, .minute], from: $0) }
        check(parts?.month == 10 && parts?.day == 3 && parts?.hour == 14 && parts?.minute == 30, "report: 3 October at 2:30pm")
        check(task.priority == .high && task.schedulingEstimateMinutes == 120, "report: high priority, two hours")
        check(task.recurrence == nil, "report: “quarterly” names the report, not a repeat")
    },
    Scenario(name: "plants", said: "Every Monday morning, water the plants.") { tasks, _ in
        check(tasks.count == 1, "plants: one task")
        guard let task = tasks.first else { return }
        check(title(task, has: "water", "plants"), "plants: titled (\(task.text))")
        check(task.recurrence?.frequency == .weekly && task.recurrence?.weekdays == [2], "plants: repeats every Monday")
        check(weekday(task.dueDate) == 2 && calendar.component(.hour, from: task.dueDate ?? .distantPast) == 9,
              "plants: first due on a Monday at 9")
    },
    Scenario(name: "flights", said: "Book flights for the Kyoto trip next Friday, and email Priya about the hotel.") { tasks, intelligent in
        guard intelligent else {
            check(tasks.count == 1 && tasks[0].listID == kyoto.id, "flights: without Apple Intelligence, one task, on Kyoto trip")
            return
        }
        check(tasks.count == 2, "flights: two tasks (\(tasks.map(\.text)))")
        guard tasks.count == 2 else { return }
        check(title(tasks[0], has: "flights") && tasks[0].listID == kyoto.id && weekday(tasks[0].dueDate) == 6,
              "flights: on the Kyoto trip list it was said for, on Friday (\(tasks[0].text))")
        check(title(tasks[1], has: "Priya", "hotel") && tasks[1].listID == inbox.id && tasks[1].dueDate == nil,
              "flights: the email about the hotel in Inbox, with no day (\(tasks[1].text))")
    },
    Scenario(name: "parcel", said: "Pick up the parcel from the post office, hashtag errands, low priority.") { tasks, _ in
        check(tasks.count == 1, "parcel: one task")
        guard let task = tasks.first else { return }
        check(title(task, has: "parcel"), "parcel: titled (\(task.text))")
        check(labels(task) == ["errands"] && task.priority == .low, "parcel: errands, low priority")
    },
]

let recordings = ProcessInfo.processInfo.environment["OPENLIST_VOICE_RECORDINGS"].map { URL(fileURLWithPath: $0) }
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OpenlistVoice-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }

func recording(for scenario: Scenario) throws -> URL {
    if let recordings, let found = try FileManager.default.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil)
        .first(where: { $0.deletingPathExtension().lastPathComponent == scenario.name }) {
        return found
    }
    let url = folder.appendingPathComponent("\(scenario.name).aiff")
    let say = Process()
    say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    say.arguments = ["-o", url.path, scenario.said]
    try say.run()
    say.waitUntilExit()
    return url
}

print("Apple Intelligence: \(VoiceIntelligence.current())")
for scenario in scenarios {
    let url = try recording(for: scenario)
    let voice = VoiceCapture()
    var heard: [SpokenTask]?
    voice.onHeard = { heard = $0 }
    voice.start(.file(url), vocabulary: vocabulary)
    let started = Date.now
    while heard == nil {
        if case let .failed(failure) = voice.phase {
            failures.append("\(scenario.name): \(failure.message)")
            break
        }
        if Date.now.timeIntervalSince(started) > 90 {
            failures.append("\(scenario.name): timed out in \(voice.phase)")
            voice.cancel()
            break
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    guard let heard else { continue }
    for task in heard { print("  heard as: \(task.line)\(task.listID.flatMap { store.list(id: $0) }.map { " → \($0.displayTitle)" } ?? "")") }
    let saved = store.saveSpokenTasks(heard, destinationID: inbox.id)
    check(saved.error == nil, "\(scenario.name): saved")
    print("\n\(scenario.name) (\(String(format: "%.1f", Date.now.timeIntervalSince(started)))s\(voice.usedIntelligence ? ", Apple Intelligence" : ""))")
    print("  heard: \(voice.listener.transcript)")
    for task in saved.saved {
        let list = store.list(id: task.listID)?.displayTitle ?? "?"
        let due = task.dueDate.map { $0.formatted(date: .abbreviated, time: task.includesTime ? .shortened : .omitted) } ?? "—"
        let rule = task.recurrence.map { " · repeats \($0.displayText)" } ?? ""
        print("  • \(task.text) → \(list) · \(due)\(rule) · \(labels(task).map { "#" + $0 }.joined(separator: " ")) · "
              + "priority \(task.priority.title) · \(task.schedulingEstimateMinutes) min")
    }
    scenario.expect(saved.saved, voice.usedIntelligence)
}

print("")
if failures.isEmpty {
    print("Voice audio checks passed (\(checks) checks)")
} else {
    for failure in failures { print("✗ \(failure)") }
    print("\(failures.count) of \(checks) voice audio checks failed")
    exit(1)
}
