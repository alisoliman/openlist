import Foundation
import SwiftData

@MainActor
func runVoiceCompletionChecks() throws {
    let suite = "VoiceCompletionChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    check(settings.afterVoiceCapture == .reviewBeforeSaving, "Voice capture defaults to review on a new device")
    settings.afterVoiceCapture = .saveAutomatically
    check(AppSettings(defaults: defaults).afterVoiceCapture == .saveAutomatically, "Automatic voice saving persists")
    settings.afterVoiceCapture = .reviewBeforeSaving
    check(AppSettings(defaults: defaults).afterVoiceCapture == .reviewBeforeSaving, "Review mode persists after disabling automatic saving")
    for invalid in ["", "unknown", "SAVEAUTOMATICALLY"] {
        defaults.set(invalid, forKey: "settings.afterVoiceCapture")
        check(AppSettings(defaults: defaults).afterVoiceCapture == .reviewBeforeSaving, "Invalid voice preferences fall back to review")
    }
    defaults.set(42, forKey: "settings.afterVoiceCapture")
    check(AppSettings(defaults: defaults).afterVoiceCapture == .reviewBeforeSaving, "Wrongly typed preferences cannot enable automatic saving")

    var session = VoiceCaptureSession()
    let cancelled = session.begin(afterCapture: .saveAutomatically, hasDraft: false)
    check(session.beginUnderstanding(run: cancelled), "An intentional stop can begin understanding")
    session.cancel()
    check(session.complete(run: cancelled, hasTasks: true) == nil, "Cancel suppresses a late asynchronous completion")
    check(!session.beginUnderstanding(run: cancelled), "Cancel also suppresses late transcript callbacks")
    let old = session.begin(afterCapture: .saveAutomatically, hasDraft: false)
    let current = session.begin(afterCapture: .reviewBeforeSaving, hasDraft: false)
    check(!session.beginUnderstanding(run: old), "A replaced run cannot interpret or deliver")
    check(session.beginUnderstanding(run: current), "The current run may interpret")
    check(!session.beginUnderstanding(run: current), "A repeated listener callback does not start a second interpretation")
    check(session.complete(run: current, hasTasks: true) == .reviewBeforeSaving, "Review mode is captured when listening starts")
    check(session.complete(run: current, hasTasks: true) == nil, "One run delivers at most once")
    let protected = session.begin(afterCapture: .saveAutomatically, hasDraft: true)
    check(session.beginUnderstanding(run: protected), "Voice can listen while preserving a draft")
    check(session.complete(run: protected, hasTasks: true) == .reviewBeforeSaving, "A pre-existing draft forces review even if cleared during listening")
    let silent = session.begin(afterCapture: .saveAutomatically, hasDraft: false)
    check(session.beginUnderstanding(run: silent), "A silent stop reaches the completion gate")
    check(session.complete(run: silent, hasTasks: false) == nil, "No speech never creates a save request")
    check(session.complete(run: silent, hasTasks: true) == nil, "An empty completion still consumes the run")

    let store = try makeStore()
    let draft = Draft(store: store, settings: settings)
    let inboxID = store.inboxList()!.id
    let target = store.createList(title: "Voice destination")
    let label = store.findOrCreateLabel(named: "capture-label")!
    let single = SpokenTask(snapshot: CaptureSnapshot(title: "Voice single", priority: .high, estimateMinutes: 15),
                            listID: target.id)
    let second = SpokenTask(snapshot: CaptureSnapshot(title: "Voice second", labels: ["spoken-label"]),
                            listID: nil)
    let tasks = [single, second]
    for mode in AppSettings.AfterVoiceCapture.allCases {
        for count in [1, 2] {
            draft.captureText = ""
            draft.spokenTasks = []
            draft.captureListID = inboxID
            draft.captureForToday = true
            draft.captureLabelID = label.id
            let batch = Array(tasks.prefix(count))
            let before = store.recentActivity().filter { $0.kind == .created }.count
            let result = draft.receiveVoice(batch, afterCapture: mode, now: now)
            if mode == .reviewBeforeSaving {
                check(result == nil && draft.hasCaptureDraft, "Review mode retains one or several tasks without saving")
                check(store.recentActivity().filter { $0.kind == .created }.count == before, "Review has no persistence side effects")
            } else {
                guard case let .savedSeveral(saved, _, nil) = result else { preconditionFailure("Automatic mode returns normal capture feedback") }
                check(saved.count == count && !draft.hasCaptureDraft, "Automatic mode saves exactly the recognized tasks")
                check(saved[0].listID == target.id && saved[0].priority == .high && saved[0].schedulingEstimateMinutes == 15,
                      "Automatic saving uses the recognized destination and metadata")
                check(saved.allSatisfy { $0.labelIDs.contains(label.id) && $0.dueDate == Calendar.current.startOfDay(for: .now) },
                      "Automatic saving keeps Today and the capture screen label")
                if count == 2 {
                    check(saved[1].listID == inboxID && saved[1].labelIDs.contains(store.allLabels().first { $0.name == "spoken-label" }!.id),
                          "Unnamed destinations and spoken labels use the normal store path")
                }
                check(store.recentActivity().filter { $0.kind == .created }.count == before + count, "Each automatic save has one creation event")
            }
        }
    }
    draft.captureText = "Keep this typed draft tomorrow"
    draft.spokenTasks = []
    draft.captureListID = inboxID
    check(draft.receiveVoice(tasks, afterCapture: .saveAutomatically, now: now) == nil,
          "A draft changed while listening also prevents automatic saving")
    check(draft.captureText == "Keep this typed draft tomorrow" && draft.spokenTasks.map(\.id) == tasks.map(\.id)
          && draft.captureListID == inboxID, "Review preserves typed text, its destination, and all heard tasks")
    guard case .savedSeveral(_, _, nil) = draft.addCapture() else { preconditionFailure("Explicit Add saves reviewed voice tasks") }
    check(draft.captureText == "Keep this typed draft tomorrow" && draft.spokenTasks.isEmpty,
          "Adding the reviewed voice tasks leaves the original typed draft to continue editing")
    check(draft.receiveVoice([], afterCapture: .saveAutomatically) == nil && draft.captureText == "Keep this typed draft tomorrow",
          "Empty delivery cannot save or clear typed work")

    try runVoiceSaveFailureChecks(settings: settings)
}

@MainActor
private func runVoiceSaveFailureChecks(settings: AppSettings) throws {
    enum FixtureFailure: LocalizedError {
        case rejected
        var errorDescription: String? { "Fixture save rejected" }
    }
    for count in [1, 3] {
        for failureIndex in 0..<count {
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                                                                              cloudKitDatabase: .none)])
            var rejects = true
            var failedAttempts = 0
            let title = "Failure task \(failureIndex)"
            let store = Store(context: container.mainContext) { context in
                if rejects, context.insertedModelsArray.contains(where: { ($0 as? Block)?.text == title }) {
                    failedAttempts += 1
                    throw FixtureFailure.rejected
                }
                try context.save()
            }
            store.bootstrap()
            let draft = Draft(store: store, settings: settings)
            let tasks = (0..<count).map { index in
                SpokenTask(snapshot: CaptureSnapshot(title: "Failure task \(index)"))
            }
            let outcome = draft.receiveVoice(tasks, afterCapture: .saveAutomatically)
            if failureIndex == 0 {
                guard case let .failed(notice) = outcome else { preconditionFailure("Complete save failure is reported") }
                check(notice.failed && notice.text.contains("Fixture save rejected"), "A failed automatic save explains manual recovery")
            } else {
                guard case let .savedSeveral(saved, _, failure) = outcome else { preconditionFailure("Partial save returns successes and error") }
                check(saved.count == failureIndex && failure?.failed == true, "Partial success has normal feedback and an error")
            }
            check(draft.spokenTasks.map(\.id) == Array(tasks[failureIndex...]).map(\.id) && draft.captureText.isEmpty,
                  "Only unsaved tasks remain after an automatic save failure")
            check(failedAttempts == 1, "A failed automatic save never retries itself")
            rejects = false
            guard case let .savedSeveral(recovered, _, nil) = draft.addCapture() else { preconditionFailure("Manual recovery saves the remainder") }
            check(recovered.count == count - failureIndex && draft.spokenTasks.isEmpty, "Manual Add recovers only unsaved tasks")
            check(store.blocks(inList: store.inboxList()!.id).filter { $0.kind == .task }.count == count,
                  "Manual recovery does not duplicate already saved tasks")
        }
    }
}
