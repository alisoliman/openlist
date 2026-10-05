import Foundation

@MainActor
func runVoiceSessionChecks() async throws {
    await runVoiceSceneDepartureChecks()
    let suite = "VoiceSessionChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = try makeStore()
    let settings = AppSettings(defaults: defaults)
    settings.afterVoiceCapture = .saveAutomatically
    let draft = Draft(store: store, settings: settings)
    let vocabulary = SpokenCapture.Vocabulary(lists: store.allLists(), labels: [])
    let voice = VoiceCapture()
    var deliveries = 0
    var saves = 0
    func listen(_ text: String, mode: AppSettings.AfterVoiceCapture = .saveAutomatically) {
        voice.onHeard = { tasks in
            deliveries += 1
            if draft.receiveVoice(tasks, afterCapture: voice.completionMode) != nil { saves += 1 }
        }
        voice.start(.fixture(text), vocabulary: vocabulary, afterCapture: mode, hasDraft: draft.hasCaptureDraft)
    }
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    listen("Water the ferns")
    check(voice.phase == .listening && saves == 0, "Opening voice capture starts listening without saving")
    let lateStop = voice.listener.onStop
    voice.stop()
    check(voice.phase == .understanding, "Stopping immediately protects the pending interpretation from retriggers")
    lateStop?("Buy compost")
    await settle()
    check(deliveries == 1 && saves == 1, "Repeated stop callbacks deliver and save only once")
    lateStop?("Buy compost")
    await settle()
    check(deliveries == 1, "A callback after completion cannot duplicate a save")

    listen("Never save after cancel")
    let cancelledStop = voice.listener.onStop
    voice.stop()
    voice.cancel()
    cancelledStop?("Late cancelled words")
    await settle()
    check(deliveries == 1 && saves == 1 && voice.phase == .idle, "Cancellation beats both queued interpretation and late listener completion")

    listen("Old recording")
    let oldStop = voice.listener.onStop
    voice.cancel()
    listen("Current recording")
    oldStop?("Old recording")
    check(voice.phase == .listening, "A callback from a previous recording cannot interrupt the current one")
    voice.stop()
    await settle()
    check(deliveries == 2 && saves == 2, "Only the new run saves")

    listen("   \n  ")
    voice.stop()
    await settle()
    check(voice.phase == .failed(.nothingHeard) && deliveries == 2 && saves == 2, "Silence reports a failure without saving")
    voice.cancel()
    voice.onHeard = { _ in deliveries += 1 }
    voice.start(.fixtureFailure(.microphoneDenied), vocabulary: vocabulary, afterCapture: .saveAutomatically)
    voice.stop()
    await settle()
    check(voice.phase == .failed(.microphoneDenied) && deliveries == 2, "Permission failure never calls the save path")
    let deniedStop = voice.listener.onStop
    voice.dismissFailure()
    deniedStop?("Late words after a permission failure")
    await settle()
    check(deliveries == 2 && voice.phase == .idle, "Dismissing a permission failure cannot revive a late completion")

    voice.cancel()
    listen("Review this task", mode: .reviewBeforeSaving)
    settings.afterVoiceCapture = .saveAutomatically
    voice.stop()
    await settle()
    check(deliveries == 3 && saves == 2 && draft.hasCaptureDraft, "Changing settings during a run cannot silently turn review into save")
    draft.captureText = ""
    draft.spokenTasks = []
    voice.cancel()
}

@MainActor
func runVoiceSceneDepartureChecks() async {
    var failures: [String] = []
    func expect(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL"): followup: \(message)")
        if !condition { failures.append(message) }
    }
    func settle() async { for _ in 0..<20 { await Task.yield() } }
    for isBackground in [false, true] {
        for alreadyUnderstanding in [false, true] {
            let voice = VoiceCapture()
            var reviewed: [String] = []
            var saves = 0
            voice.onHeard = { tasks in
                if voice.completionMode == .saveAutomatically { saves += 1 }
                else { reviewed += tasks.map { $0.snapshot.title } }
            }
            voice.start(.fixture("Review on return"), vocabulary: SpokenCapture.Vocabulary(), afterCapture: .saveAutomatically)
            if alreadyUnderstanding { voice.stop() }
            let generation = voice.generation
            voice.sceneDepartedActive(isBackground: isBackground)
            expect(voice.phase == .understanding && voice.generation == generation && !voice.listener.isActive,
                   "scene departure stops audio without cancelling \(alreadyUnderstanding ? "understanding" : "listening")")
            voice.sceneDepartedActive(isBackground: true)
            await settle()
            expect(reviewed == ["Review on return"] && saves == 0 && !voice.isActive,
                   "\(isBackground ? "background" : "inactive") during \(alreadyUnderstanding ? "understanding" : "listening") delivers once for review, never background save")
        }
    }
    let preparing = VoiceCapture()
    var deliveries = 0
    preparing.onHeard = { _ in deliveries += 1 }
    preparing.start(.fixture("", preparing: true), vocabulary: SpokenCapture.Vocabulary(), afterCapture: .saveAutomatically)
    let generation = preparing.generation
    let lateStop = preparing.listener.onStop
    preparing.sceneDepartedActive(isBackground: false)
    expect(preparing.phase == .preparing(progress: nil) && preparing.generation == generation,
           "inactive permission prompt leaves preparation running")
    lateStop?("Permission granted")
    await settle()
    expect(deliveries == 1 && preparing.completionMode == .saveAutomatically,
           "inactive preparation does not override active-app Done auto-save")
    preparing.cancel()
    preparing.onHeard = { _ in deliveries += 1 }
    preparing.start(.fixture("", preparing: true), vocabulary: SpokenCapture.Vocabulary(), afterCapture: .saveAutomatically)
    let cancelledStop = preparing.listener.onStop
    preparing.sceneDepartedActive(isBackground: true)
    cancelledStop?("Late prepared speech")
    await settle()
    expect(preparing.phase == .idle && deliveries == 1, "background cancels preparation and rejects late completion")

    let voice = VoiceCapture()
    var mode: AppSettings.AfterVoiceCapture?
    voice.onHeard = { _ in mode = voice.completionMode }
    voice.start(.fixture("Explicit Done"), vocabulary: SpokenCapture.Vocabulary(), afterCapture: .saveAutomatically)
    voice.stop()
    await settle()
    expect(mode == .saveAutomatically, "active-app explicit Done still auto-saves")
    mode = nil
    voice.start(.fixture("Cancelled departure"), vocabulary: SpokenCapture.Vocabulary(), afterCapture: .saveAutomatically)
    let cancelledDelivery = voice.listener.onStop
    voice.sceneDepartedActive(isBackground: false)
    voice.cancel()
    cancelledDelivery?("Late cancelled speech")
    await settle()
    expect(mode == nil && voice.phase == .idle, "explicit cancellation beats scene-departure review and late delivery")
    check(failures.isEmpty, "Voice scene-departure regressions: \(failures.joined(separator: "; "))")
}
