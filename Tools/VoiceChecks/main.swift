// Checks voice capture's reading and filing, without a microphone or a
// model: what's said, read into tasks with the list, date, time, repeat,
// labels, priority and estimate said (`SpokenCapture`); a model's split read
// against what was actually said (`VoiceTaskInterpreter.tasks`); and the
// tasks heard filed into their lists (`Store.saveSpokenTasks`, the capture
// draft). Transcripts are written as the system's speech model writes them.
// `run-voice-audio-checks.sh` runs recordings through the real models.

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

let calendar = Calendar.current
// A Wednesday.
let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 10, minute: 10))!
func day(_ date: Date?) -> DateComponents? {
    date.map { calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: $0) }
}

let store = try makeStore()
let inbox = store.inboxList()!
let kyoto = store.createList(title: "Kyoto trip")
let work = store.createList(title: "Work")
let groceries = store.createList(title: "Groceries")
let family = store.createList(title: "Family")
_ = store.findOrCreateLabel(named: "travel")
_ = store.findOrCreateLabel(named: "errands")
let vocabulary = SpokenCapture.Vocabulary(lists: [inbox, kyoto, work, groceries, family], labels: store.allLabels())

func heard(_ transcript: String) -> SpokenTask {
    guard let task = SpokenCapture.fallback(transcript, vocabulary: vocabulary, reference: now).first else {
        preconditionFailure("“\(transcript)” reads as a task")
    }
    return task
}

// MARK: - One task, read from what was said

do {
    let mum = heard("Remind me to call mom tomorrow at 5 PM.")
    check(mum.snapshot.title == "Call mom" && day(mum.snapshot.date)?.day == 24 && day(mum.snapshot.date)?.hour == 17
          && mum.snapshot.includesTime && mum.listID == nil, "The lead-in goes, the day and time are read")

    let deposit = heard("Add pay the ryokan deposit to my Kyoto trip list by Friday, tag it travel, it takes 15 minutes.")
    check(deposit.snapshot.title == "Pay the ryokan deposit" && deposit.listID == kyoto.id
          && day(deposit.snapshot.date)?.day == 25 && !deposit.snapshot.includesTime
          && deposit.snapshot.labels == ["travel"] && deposit.snapshot.estimateMinutes == 15 && deposit.snapshot.priority == .none,
          "A list, label and duration said in words are read, and the request's “add” goes with them")

    let plants = heard("Every Monday morning water the plants.")
    check(plants.snapshot.title == "Water the plants" && plants.snapshot.recurrence?.frequency == .weekly
          && day(plants.snapshot.date)?.weekday == 2 && day(plants.snapshot.date)?.hour == 9,
          "A repeat said aloud repeats")

    let priya = heard("Um, so I should probably email Priya about the scorecard.")
    check(priya.snapshot.title == "Email Priya about the scorecard" && priya.snapshot.date == nil,
          "Filler before the task goes")

    let report = heard("Put finish the quarterly report on my work list for the 3rd of October at 2:30, high priority, about 2 hours.")
    check(report.snapshot.title == "Finish the quarterly report" && report.listID == work.id
          && day(report.snapshot.date)?.month == 10 && day(report.snapshot.date)?.day == 3 && day(report.snapshot.date)?.hour == 14
          && day(report.snapshot.date)?.minute == 30 && report.snapshot.priority == .high && report.snapshot.estimateMinutes == 120,
          "“the 3rd of October”, a spoken “2:30” in the afternoon, priority and hours")

    let dentist = heard("Book the dentist next Tuesday. It's urgent.")
    check(dentist.snapshot.title == "Book the dentist" && dentist.snapshot.priority == .high
          && day(dentist.snapshot.date)?.weekday == 3 && dentist.snapshot.date! > now, "“It's urgent” is high priority")

    check(heard("Pick up the dry cleaning, low priority.").snapshot.priority == .low, "Low priority")
    check(heard("Renew the passport, it's not urgent.").snapshot.priority == .low, "“Not urgent” is low, not urgent")
    check(heard("Call the bank ASAP.").snapshot.title == "Call the bank" && heard("Call the bank ASAP.").snapshot.priority == .high,
          "ASAP is high priority")
    check(heard("Add call grandma to Family.").listID == family.id && heard("Add call grandma to Family.").snapshot.title == "Call grandma",
          "After “add”, a list's name alone at the end is where it goes")
    check(heard("Add oat milk to groceries.").listID == groceries.id, "A list's name heard in the plural or lower case")
    check(heard("Drive to work tomorrow.").listID == nil && heard("Drive to work tomorrow.").snapshot.title == "Drive to work",
          "Without “add” or “list”, a list's name is part of the task")
    let flights = heard("Book flights for the Kyoto trip next Tuesday.")
    check(flights.listID == kyoto.id && flights.snapshot.title == "Book flights for the Kyoto trip",
          "A list's name of more than a word, said with the task, is where it goes, and stays in its title")
    check(heard("Label the boxes for the move.").snapshot.labels.isEmpty
          && heard("Label the boxes for the move.").snapshot.title == "Label the boxes for the move",
          "Labelling something is a task, not a label")
    let parcel = heard("Hashtag errands, pick up the parcel.")
    check(parcel.snapshot.labels == ["errands"] && parcel.snapshot.title == "Pick up the parcel", "“Hashtag” names a label")
    let tagged = heard("Book the flights, tag it travel and errands.")
    check(tagged.snapshot.labels == ["travel", "errands"] && tagged.snapshot.title == "Book the flights",
          "A second label after “and” when it's one of the library's")
    let soon = heard("Water the plants in 15 minutes.")
    check(soon.snapshot.estimateMinutes == 0 && soon.snapshot.date != nil, "“In 15 minutes” is when, not how long")
    check(heard("Write the report, it'll take an hour and a half.").snapshot.estimateMinutes == 90, "An hour and a half")
    check(heard("Tidy the garage, it takes half an hour.").snapshot.estimateMinutes == 30, "Half an hour")
    check(heard("Call the plumber at 9.").snapshot.includesTime && day(heard("Call the plumber at 9.").snapshot.date)?.hour == 9,
          "A spoken 9 stays in the morning")
    check(heard("Pick up Sam at 3.").snapshot.includesTime && day(heard("Pick up Sam at 3.").snapshot.date)?.hour == 15,
          "A spoken 3 is in the afternoon")
    check(heard("Feed the cat at 5 o'clock.").snapshot.includesTime && day(heard("Feed the cat at 5 o'clock.").snapshot.date)?.hour == 17,
          "“5 o'clock” is at 5 in the afternoon")
    check(SpokenCapture.fallback("Um, uh.", vocabulary: vocabulary, reference: now).isEmpty, "Filler alone is no task")

    for task in [mum, deposit, plants, priya, report, dentist, parcel, tagged] {
        check(task.fitsField(parsesDates: true, reference: now), "“\(task.line)” reads back as the task it came from")
    }
    check(!mum.fitsField(parsesDates: false, reference: now), "With dates not read from text, a dated task stays a row")
    check(deposit.line == "Pay the ryokan deposit Friday #travel ~15m", "The capture line puts the tokens after the title")
}

// MARK: - Apple Intelligence's split, read against what was said

do {
    let said = "Remind me to call mom tomorrow at 5 PM, and I need to buy milk and eggs. Oh, and book the dentist next Tuesday. It's urgent."
    let split = [
        HeardTask(title: "Call mom", said: "call mom tomorrow at 5 pm", when: "tomorrow 5pm"),
        HeardTask(title: "Buy milk and eggs", said: "buy milk and eggs", when: "tomorrow"),
        HeardTask(title: "Book the dentist", said: "book the dentist next Tuesday, it's urgent", when: "next Tuesday"),
        // The instructions' example, repeated by the model.
        HeardTask(title: "Call the plumber", said: "call the plumber tomorrow at 9", when: "tomorrow 9am"),
        HeardTask(title: "call mom", said: "call mom", when: nil),
    ]
    let tasks = VoiceTaskInterpreter.tasks(from: split, transcript: said, vocabulary: vocabulary, reference: now)
    check(tasks.map(\.snapshot.title) == ["Call mom", "Buy milk and eggs", "Book the dentist"],
          "Each to-do said is a task, once; one never said is dropped")
    check(tasks[0].snapshot.includesTime && day(tasks[0].snapshot.date)?.hour == 17, "Each task's own words give its time")
    check(tasks[1].snapshot.date == nil, "In English, a day the model made up for a task is ignored")
    check(tasks[2].snapshot.priority == .high && tasks[0].snapshot.priority == .none, "Priority is the task's it was said about")

    // A sentence that only says how long or how urgent is the to-do before
    // it's, even when the model made it a to-do of its own, and a closing
    // "It's urgent" the last to-do's.
    let modified = VoiceTaskInterpreter.tasks(
        from: [HeardTask(title: "Pay Ryokan deposit", said: "Dad paid the Ryokan deposit to my Kyoto trip list by Friday, tagged travel", when: "by Friday"),
               HeardTask(title: "Wait 15 minutes", said: "It takes 15 minutes", when: "by Friday"),
               HeardTask(title: "Book the dentist", said: "book the dentist next Tuesday", when: nil)],
        transcript: "Dad paid the Ryokan deposit to my Kyoto trip list by Friday, tagged travel. It takes 15 minutes. Oh, and book the dentist next Tuesday. It's urgent.",
        vocabulary: vocabulary, reference: now)
    check(modified.map(\.snapshot.title) == ["Pay Ryokan deposit", "Book the dentist"], "A how-long sentence is no task of its own")
    check(modified[0].listID == kyoto.id && modified[0].snapshot.labels == ["travel"] && modified[0].snapshot.estimateMinutes == 15
          && day(modified[0].snapshot.date)?.day == 25 && modified[0].snapshot.priority == .none,
          "…but the task before it's, with the list, label and day said with it")
    check(modified[1].snapshot.priority == .high && day(modified[1].snapshot.date)?.weekday == 3,
          "A closing “It's urgent” is the last task's")
    let fuller = VoiceTaskInterpreter.tasks(
        from: [HeardTask(title: "Book flights", said: "Book flights for the Kyoto trip next Friday", when: "next Friday"),
               HeardTask(title: "Email Priya", said: "email Priya about the hotel", when: "next Friday")],
        transcript: "Book flights for the Kyoto trip next Friday, and email Priya about the hotel.",
        vocabulary: vocabulary, reference: now)
    check(fuller.map(\.snapshot.title) == ["Book flights for the Kyoto trip", "Email Priya about the hotel"],
          "A title the model cut short keeps the rest of what was said about the task")
    check(fuller[0].listID == kyoto.id && fuller[1].listID == nil && fuller[1].snapshot.date == nil,
          "…each with its own list and day")
    check(heard("Finish the report at 230.").snapshot.includesTime && day(heard("Finish the report at 230.").snapshot.date)?.hour == 14
          && day(heard("Finish the report at 230.").snapshot.date)?.minute == 30, "“at 230” is 2:30 in the afternoon")

    let one = VoiceTaskInterpreter.tasks(
        from: [HeardTask(title: "Pay the ryokan deposit", said: "pay the ryokan deposit", when: nil)],
        transcript: "Add pay the ryokan deposit to my Kyoto trip list by Friday, it's urgent, tag it travel.",
        vocabulary: vocabulary, reference: now)
    check(one.count == 1 && one[0].listID == kyoto.id && one[0].snapshot.priority == .high && one[0].snapshot.labels == ["travel"]
          && day(one[0].snapshot.date)?.day == 25, "A single task is read from everything said")

    let french = VoiceTaskInterpreter.tasks(
        from: [HeardTask(title: "Appeler le plombier", said: "appeler le plombier demain à 9 heures", when: "tomorrow 9am")],
        transcript: "Rappelle-moi d'appeler le plombier demain à 9 heures.", vocabulary: vocabulary, reference: now,
        translatesDates: true)
    check(french.first?.snapshot.title == "Appeler le plombier" && day(french.first?.snapshot.date)?.hour == 9,
          "In another language, the model's English day and time are read")

    let leaked = VoiceTaskInterpreter.tasks(
        from: [HeardTask(title: "Pick up the parcel", said: "pick up the parcel", when: nil)],
        transcript: "Buy stamps.", vocabulary: vocabulary, reference: now)
    check(leaked.isEmpty, "Nothing the speaker didn't say")
}

// MARK: - Filing what was heard

@Observable @MainActor
final class Draft: NXCaptureDraft {
    @ObservationIgnored let store: Store
    @ObservationIgnored let settings: AppSettings
    var captureText = ""
    var captureListID: UUID?
    var captureForToday = false
    var captureLabelID: UUID?
    var spokenTasks: [SpokenTask] = []

    init(store: Store, settings: AppSettings) {
        self.store = store
        self.settings = settings
        captureListID = store.inboxList()?.id
    }
}

do {
    let suite = "VoiceChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let draft = Draft(store: store, settings: AppSettings(defaults: defaults))

    draft.captureText = "half typed"
    let deposit = heard("Add pay the ryokan deposit to my Kyoto trip list by Friday, tag it travel.")
    draft.take([deposit], now: now)
    check(draft.captureText == "half typed" && draft.captureListID == inbox.id && draft.spokenTasks.map(\.id) == [deposit.id],
          "Starting voice over a typed draft preserves its text and destination for review")
    let more = heard("Buy stamps.")
    draft.take([more], now: now)
    check(draft.captureText == "half typed" && draft.spokenTasks.map(\.id) == [deposit.id, more.id],
          "Another voice capture never discards tasks already awaiting review")

    draft.captureText = ""
    draft.spokenTasks = []
    draft.take([deposit], now: now)
    check(draft.spokenTasks.isEmpty && draft.captureText == "Pay the ryokan deposit Friday #travel" && draft.captureListID == kyoto.id,
          "A single task heard is the capture's text, aimed at the list it named")

    // Several wait as rows and file together.
    draft.captureText = ""
    draft.captureListID = inbox.id
    let said = [heard("Pay the ryokan deposit on my Kyoto trip list, it's urgent."), heard("Buy oat milk tomorrow."),
                heard("Send the invoice on the work list, takes 20 minutes.")]
    draft.take(said, now: now)
    check(draft.captureText.isEmpty && draft.spokenTasks.count == 3, "Several tasks heard wait for Return together")
    guard case let .savedSeveral(blocks, _, failure) = draft.addCapture() else { preconditionFailure("Return adds the tasks heard") }
    check(failure == nil && draft.spokenTasks.isEmpty && blocks.map(\.text) == ["Pay the ryokan deposit", "Buy oat milk", "Send the invoice"],
          "Every task heard is added, in the order said")
    check(blocks[0].listID == kyoto.id && blocks[0].priority == .high, "Into the list it named, with its priority")
    check(blocks[1].listID == inbox.id && day(blocks[1].dueDate)?.day == 24 && !blocks[1].includesTime,
          "A task naming no list goes where the capture is aimed, with its day")
    check(blocks[2].listID == work.id && blocks[2].schedulingEstimateMinutes == 20, "With its estimate")
    check(store.recentActivity().filter { event in blocks.contains { $0.id == event.blockID } }.map(\.kind) == [.created, .created, .created],
          "Each is one creation in history")

    // A list gone since, today's capture and a label screen's label.
    let old = store.createList(title: "Old trip")
    let archived = SpokenCapture.Vocabulary(lists: [old], labels: [])
    let stale = SpokenCapture.task(from: "Pack the bags on the old trip list", vocabulary: archived, reference: now)!
    store.setArchived(true, for: old)
    let label = store.findOrCreateLabel(named: "errands")!
    draft.captureForToday = true
    draft.captureLabelID = label.id
    draft.take([stale, heard("Buy stamps.")], now: now)
    guard case let .savedSeveral(filed, _, nil) = draft.addCapture() else { preconditionFailure("An archived list falls back") }
    check(filed[0].listID == inbox.id && filed.allSatisfy { $0.labelIDs.contains(label.id) }
          && filed.allSatisfy { $0.dueDate == calendar.startOfDay(for: .now) },
          "A list archived since sends its task where the capture is aimed; today's capture and a label screen's label apply")

    // A destination that can't take them keeps them, with why.
    draft.captureForToday = false
    draft.captureLabelID = nil
    draft.captureListID = old.id
    draft.take([heard("Water the ferns."), heard("Buy compost.")], now: now)
    guard case let .failed(notice) = draft.addCapture() else { preconditionFailure("An archived destination takes nothing") }
    check(notice.failed && notice.text.hasPrefix("“Water the ferns” wasn’t added.") && draft.spokenTasks.count == 2,
          "Tasks that can't be added stay, and the card says why")
}

await runVoiceAdjudicationChecks()
try runVoiceCompletionChecks()
try await runVoiceSessionChecks()
runCaptureGestureChecks()
runPhoneCaptureEntryChecks()
runVoiceShortcutChecks()

print("Voice checks passed (\(checks) checks)")
