import Foundation

@MainActor
func runVoiceWorkbenchChecks() async throws {
    let previousFixture = ProcessInfo.processInfo.environment["OpenlistVoiceFixture"]
    defer {
        if let previousFixture { setenv("OpenlistVoiceFixture", previousFixture, 1) }
        else { unsetenv("OpenlistVoiceFixture") }
        workbench.closeCapture()
    }
    func fixture(_ text: String) { setenv("OpenlistVoiceFixture", text, 1) }
    func settle() async { for _ in 0..<20 { await Task.yield() } }
    func captured(_ prefix: String) -> [Block] {
        store.blocks(inList: home.id).filter { $0.kind == .task && $0.text.hasPrefix(prefix) }
    }

    settings.afterVoiceCapture = .saveAutomatically
    fixture("Voice window first\nVoice window second")
    workbench.openCapture(listID: home.id, listens: true)
    check(workbench.captureOpen && workbench.voice.phase == .listening, "the toolbar voice action opens the main capture already listening")
    workbench.openCapture(listens: true)
    check(workbench.voice.phase == .listening && captured("Voice window").isEmpty, "retriggering the main voice entry cannot stop or save a recording")
    workbench.voice.stop()
    await settle()
    check(!workbench.captureOpen && captured("Voice window").count == 2, "main-window automatic capture saves all heard tasks and closes")
    check(workbench.canUndo && workbench.tray?.undoable == true, "main-window automatic saves keep normal feedback and Undo")
    workbench.undoLast()
    check(captured("Voice window").isEmpty, "one Undo removes the entire automatic voice batch")

    var followupFailures: [String] = []
    func expectFollowup(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL"): followup: \(message)")
        if !condition { followupFailures.append(message) }
    }
    for alreadyUnderstanding in [false, true] {
        fixture("Voice passive first\nVoice passive second")
        workbench.openCapture(listID: home.id, listens: true)
        if alreadyUnderstanding { workbench.voice.stop() }
        let generation = workbench.voice.generation
        workbench.closeCapture(keepsDraft: true)
        expectFollowup(workbench.captureOpen && workbench.voice.phase == .understanding
                       && workbench.voice.generation == generation && !workbench.voice.listener.isActive,
                       "passive close during \(alreadyUnderstanding ? "understanding" : "listening") stops audio without hiding or cancelling")
        workbench.closeCapture(keepsDraft: true)
        expectFollowup(workbench.captureOpen, "repeated passive close cannot hide pending interpretation")
        await settle()
        expectFollowup(workbench.captureOpen && workbench.spokenTasks.count == 2
                       && workbench.voice.completionMode == .reviewBeforeSaving && captured("Voice passive").isEmpty,
                       "passive close retains interpreted speech for review, not automatic save")
        let heardIDs = workbench.spokenTasks.map(\.id)
        workbench.closeCapture(keepsDraft: true)
        expectFollowup(!workbench.captureOpen, "a later passive close stashes the completed draft")
        workbench.openCapture()
        expectFollowup(workbench.spokenTasks.count == 2 && workbench.spokenTasks.map(\.id) == heardIDs
                       && workbench.captureListID == home.id,
                       "reopening restores the completed speech and destination")
        workbench.closeCapture()
    }
    for alreadyUnderstanding in [false, true] {
        fixture("Voice explicitly cancelled")
        workbench.openCapture(listID: home.id, listens: true)
        let lateStop = workbench.voice.listener.onStop
        if alreadyUnderstanding { workbench.voice.stop() }
        workbench.closeCapture(keepsDraft: false)
        lateStop?("Voice explicitly cancelled late")
        await settle()
        expectFollowup(!workbench.captureOpen && workbench.voice.phase == .idle
                       && captured("Voice explicitly cancelled").isEmpty,
                       "explicit close cancels \(alreadyUnderstanding ? "understanding" : "listening") and suppresses late delivery")
        workbench.openCapture()
        expectFollowup(!workbench.hasCaptureDraft, "explicitly cancelled speech cannot reappear on reopen")
        workbench.closeCapture()
    }
    fixture("Voice escaped after passive close")
    workbench.openCapture(listID: home.id, listens: true)
    let escapedStop = workbench.voice.listener.onStop
    workbench.closeCapture(keepsDraft: true)
    workbench.voice.cancel()
    escapedStop?("Voice escaped after passive close late")
    await settle()
    expectFollowup(workbench.voice.phase == .idle && !workbench.hasCaptureDraft
                   && captured("Voice escaped").isEmpty,
                   "Escape's voice cancel suppresses pending review and late delivery after passive close")
    workbench.closeCapture()
    check(followupFailures.isEmpty, "Voice passive-close regressions: \(followupFailures.joined(separator: "; "))")

    settings.afterVoiceCapture = .reviewBeforeSaving
    fixture("Voice reviewed")
    workbench.openCapture(listID: home.id, listens: true)
    workbench.voice.stop()
    await settle()
    check(workbench.captureOpen && workbench.captureText == "Voice reviewed" && captured("Voice reviewed").isEmpty,
          "the main capture's default review mode does not save until Add")
    workbench.createFromCapture(keepOpen: false)
    check(!workbench.captureOpen && captured("Voice reviewed").count == 1, "reviewed speech follows the ordinary Add action")
    workbench.undoLast()

    settings.afterVoiceCapture = .saveAutomatically
    fixture("Voice separate")
    workbench.openCapture(listID: home.id)
    workbench.captureText = "Original typed draft"
    workbench.toggleVoice()
    workbench.voice.stop()
    await settle()
    check(workbench.captureText == "Original typed draft" && workbench.spokenTasks.count == 1 && captured("Voice separate").isEmpty,
          "speaking over a main-window draft always retains both for review")
    workbench.createFromCapture(keepOpen: false)
    check(workbench.captureOpen && workbench.captureText == "Original typed draft" && workbench.spokenTasks.isEmpty,
          "saving reviewed voice tasks does not close or auto-save the original text")
    workbench.closeCapture(keepsDraft: true)
    workbench.openCapture()
    check(workbench.captureText == "Original typed draft", "the preserved typed draft survives a click away")
    workbench.closeCapture()
    workbench.undoLast()
    workbench.openCapture(listID: home.id)
    let unsaved = SpokenTask(snapshot: CaptureSnapshot(title: "Kept spoken draft"))
    workbench.spokenTasks = [unsaved]
    workbench.closeCapture(keepsDraft: true)
    workbench.openCapture()
    check(workbench.spokenTasks.map(\.id) == [unsaved.id], "a click away also retains unsaved spoken rows")
    workbench.closeCapture()

    let quick = QuickCaptureDraft(store: store, settings: settings, request: QuickCaptureRequest(listID: home.id))
    var closes = 0
    fixture("Voice floating first\nVoice floating second")
    quick.voice.toggle(for: quick, lists: store.allLists(), labels: []) { [weak quick] outcome in
        quick?.complete(outcome, workbench: workbench, keepOpen: false, automatically: true) { _ in closes += 1 }
    }
    quick.voice.stop()
    await settle()
    check(closes == 0 && captured("Voice floating").count == 2 && !quick.hasCaptureDraft && quick.notice != nil && quick.canUndoCapture,
          "floating capture uses the same automatic save path and keeps success and Undo visible")
    check(workbench.canUndo, "floating automatic saves register normal Undo")
    workbench.undoLast()
    check(captured("Voice floating").isEmpty, "floating automatic saves undo as a single batch")
    quick.voice.cancel()

    let unavailable = store.createList(title: "Unavailable voice destination")
    store.setArchived(true, for: unavailable)
    quick.captureListID = unavailable.id
    let partial = [SpokenTask(snapshot: CaptureSnapshot(title: "Voice partial first"), listID: home.id),
                   SpokenTask(snapshot: CaptureSnapshot(title: "Voice partial second"))]
    guard let result = quick.receiveVoice(partial, afterCapture: .saveAutomatically) else { preconditionFailure("automatic save attempted") }
    quick.complete(result, workbench: workbench, keepOpen: false) { _ in closes += 1 }
    check(closes == 0 && quick.notice?.failed == true && quick.spokenTasks.map(\.id) == [partial[1].id],
          "floating partial failure keeps only unsaved rows and the error, without closing")
    check(captured("Voice partial").count == 1 && workbench.canUndo, "partial successes are saved and undoable")
    quick.captureListID = home.id
    quick.complete(quick.addCapture(), workbench: workbench, keepOpen: false) { _ in closes += 1 }
    check(closes == 1 && captured("Voice partial").count == 2, "manual recovery saves only the remainder and closes once")

    quick.captureText = "Keep quick text"
    quick.captureListID = home.id
    quick.apply(QuickCaptureRequest(listens: true))
    check(quick.captureText == "Keep quick text" && quick.captureListID == home.id,
          "a voice request cannot re-aim an existing floating draft")

    quick.show(NXCaptureNotice(text: "A previous success"))
    await settle()
    let failure = NXCaptureNotice(text: "Manual recovery needed", failed: true)
    quick.show(failure)
    try await Task.sleep(for: .milliseconds(2250))
    await settle()
    check(quick.notice == failure, "a previous success timer cannot hide a later save error")
}
