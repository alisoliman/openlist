import AppKit
import Foundation

@MainActor
private final class RecorderCheckWindow: NSWindow {
    var fixtureIsKey = true
    override var isKeyWindow: Bool { fixtureIsKey }
}

@MainActor
func runWorkbenchAdjudicationChecks() async throws {
    var failures: [String] = []
    func expect(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL"): \(message)")
        if !condition { failures.append(message) }
    }
    let originalManager = workbench.undoManager
    defer { workbench.undoManager = originalManager }
    settings.afterVoiceCapture = .saveAutomatically
    for hasMainWindow in [true, false] {
        workbench.undoManager = hasMainWindow ? originalManager : nil
        let draft = QuickCaptureDraft(store: store, settings: settings, request: QuickCaptureRequest(listID: home.id))
        let tasks = [SpokenTask(snapshot: CaptureSnapshot(title: "Adjudication floating \(hasMainWindow)"))]
        guard let outcome = draft.receiveVoice(tasks, afterCapture: .saveAutomatically),
              case let .savedSeveral(saved, _, nil) = outcome else { preconditionFailure("Fixture capture did not save") }
        let ids = saved.map(\.id)
        var closes = 0
        draft.complete(outcome, workbench: workbench, keepOpen: false, automatically: true) { _ in closes += 1 }
        expect(closes == 0 && draft.notice?.text.contains("Added") == true && draft.canUndoCapture,
               "1: floating success stays visible with reachable Undo (main window: \(hasMainWindow))")
        if hasMainWindow { expect(workbench.canUndo, "1: floating capture also keeps normal main-window Undo") }
        draft.undoCapture()
        expect(ids.allSatisfy { store.block(id: $0) == nil },
               "1: floating Undo removes its saved batch (main window: \(hasMainWindow))")
        expect(!workbench.log.contains { $0.taskID.map(ids.contains) == true }, "1: floating Undo removes its matching Changes entries")
        draft.endPresentation()
    }
    workbench.undoManager = originalManager

    var temporaryManager: UndoManager? = UndoManager()
    weak var retainedManager = temporaryManager
    workbench.undoManager = temporaryManager
    let retainedDraft = QuickCaptureDraft(store: store, settings: settings, request: QuickCaptureRequest(listID: home.id))
    let retainedTasks = [SpokenTask(snapshot: CaptureSnapshot(title: "Adjudication closed main window"))]
    let retainedOutcome = retainedDraft.receiveVoice(retainedTasks, afterCapture: .saveAutomatically)!
    retainedDraft.complete(retainedOutcome, workbench: workbench, keepOpen: false, automatically: true) { _ in }
    workbench.undoManager = nil
    temporaryManager = nil
    expect(retainedManager != nil && retainedDraft.canUndoCapture, "1: closing the main window cannot release the floating capture's Undo")
    retainedDraft.undoCapture()
    retainedDraft.endPresentation()
    workbench.undoManager = originalManager

    var drafts: [QuickCaptureDraft] = []
    var closeCounts = [Int](repeating: 0, count: 4)
    for index in closeCounts.indices {
        let draft = QuickCaptureDraft(store: store, settings: settings, request: QuickCaptureRequest(listID: home.id))
        let heard = [SpokenTask(snapshot: CaptureSnapshot(title: "Adjudication timer \(index)"))]
        let outcome = draft.receiveVoice(heard, afterCapture: .saveAutomatically)!
        draft.complete(outcome, workbench: workbench, keepOpen: false, automatically: true) { _ in closeCounts[index] += 1 }
        drafts.append(draft)
    }
    drafts[1].captureText = "A later draft"
    drafts[1].captureText = ""
    let laterFailure = NXCaptureNotice(text: "Later manual recovery", failed: true)
    drafts[2].show(laterFailure)
    drafts[3].endPresentation()
    try await Task.sleep(for: .milliseconds(3250))
    expect(closeCounts == [1, 0, 0, 0], "1: success closes once, but an old timer cannot close a newer draft or ended presentation")
    expect(drafts[2].notice == laterFailure, "1: an old success timer cannot erase a later failure")
    drafts.forEach { $0.endPresentation() }

    workbench.undoManager = nil
    let partialDraft = QuickCaptureDraft(store: store, settings: settings, request: QuickCaptureRequest(listID: home.id))
    let unavailable = store.createList(title: "Adjudication unavailable")
    store.setArchived(true, for: unavailable)
    partialDraft.captureListID = unavailable.id
    let partialTasks = [SpokenTask(snapshot: CaptureSnapshot(title: "Adjudication saved subset"), listID: home.id),
                        SpokenTask(snapshot: CaptureSnapshot(title: "Adjudication unsaved remainder"))]
    let partialOutcome = partialDraft.receiveVoice(partialTasks, afterCapture: .saveAutomatically)!
    var partialCloses = 0
    partialDraft.complete(partialOutcome, workbench: workbench, keepOpen: false, automatically: true) { _ in partialCloses += 1 }
    expect(partialCloses == 0 && partialDraft.notice?.failed == true && partialDraft.canUndoCapture
           && partialDraft.spokenTasks.map(\.id) == [partialTasks[1].id],
           "1: partial failure keeps only unsaved tasks and independent Undo for the saved subset")
    partialDraft.undoCapture()
    expect(partialDraft.spokenTasks.map(\.id) == [partialTasks[1].id] && partialDraft.notice?.failed == true,
           "1: undoing a partial success preserves the unsaved recovery rows and failure")
    partialDraft.endPresentation()
    workbench.undoManager = originalManager

    let typedDraft = QuickCaptureDraft(store: store, settings: settings, request: QuickCaptureRequest(listID: home.id))
    typedDraft.captureText = "Adjudication ordinary typed task"
    var typedCloses = 0
    typedDraft.complete(typedDraft.addCapture(), workbench: workbench, keepOpen: false) { _ in typedCloses += 1 }
    expect(typedCloses == 1, "1: ordinary typed Return still saves and closes immediately")

    var releasedDraft: QuickCaptureDraft? = QuickCaptureDraft(store: store, settings: settings, request: QuickCaptureRequest(listID: home.id))
    weak var observedDraft = releasedDraft
    releasedDraft?.show(NXCaptureNotice(text: "Transient success"))
    releasedDraft = nil
    expect(observedDraft == nil, "1: a pending feedback timer does not retain its dismissed draft")

    let hiddenDraft = QuickCaptureDraft(store: store, settings: settings, request: QuickCaptureRequest(listID: home.id))
    var hiddenSaves = 0
    hiddenDraft.voice.onHeard = { [weak hiddenDraft] heard in
        guard let hiddenDraft else { return }
        if hiddenDraft.receiveVoice(heard, afterCapture: hiddenDraft.voice.completionMode) != nil { hiddenSaves += 1 }
    }
    hiddenDraft.voice.start(.fixture("Adjudication completed while hidden"), vocabulary: SpokenCapture.Vocabulary(),
                            afterCapture: .saveAutomatically)
    let staleStop = hiddenDraft.voice.listener.onStop
    hiddenDraft.voice.stop()
    hiddenDraft.endPresentation()
    for _ in 0..<20 { await Task.yield() }
    expect(hiddenSaves == 0 && hiddenDraft.hasCaptureDraft && !hiddenDraft.voice.isActive,
           "3: putting floating capture aside preserves completed understanding for review without hidden autosave")
    hiddenDraft.voice.cancel()
    hiddenDraft.voice.start(.fixture("A new recording"), vocabulary: SpokenCapture.Vocabulary())
    staleStop?("A stale recording")
    expect(hiddenDraft.voice.phase == .listening && hiddenSaves == 0,
           "1/3: an old floating callback cannot stop or save a newer recording")
    hiddenDraft.voice.cancel()

    _ = NSApplication.shared
    let window = RecorderCheckWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                         styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    other.isReleasedWhenClosed = false
    let recorder = NXShortcutRecorder.RecorderView()
    window.contentView = recorder
    var cancelled = 0
    var received = 0
    let typed = QuickCaptureHotKey(route: .typed, allowsRegistration: true) { _, _ in .success {} }
    let global = QuickCaptureHotKey(route: .voice, allowsRegistration: true) { _, _ in .success {} }
    typed.register()
    global.register()
    typed.unregister()
    global.unregister()
    recorder.cancelled = {
        cancelled += 1
        typed.register()
        global.register()
    }
    recorder.received = { _ in received += 1 }
    recorder.begin()
    let ownEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, characters: "k",
                                   charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
    expect(recorder.performKeyEquivalent(with: ownEvent) && received == 1,
           "6: the recorder still receives commands belonging to its own key window")
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
                                windowNumber: other.windowNumber, context: nil, characters: "k",
                                charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
    expect(!recorder.performKeyEquivalent(with: event) && received == 1,
           "6: shortcut recording cannot consume commands belonging to another window")
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: other)
    expect(cancelled == 0, "6: another window's resignation does not cancel the recorder")
    window.fixtureIsKey = false
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    expect(cancelled == 1 && typed.isRegistered && global.isRegistered,
           "6: own-window blur ends recording and restores both suspended shortcut registrations")
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    expect(cancelled == 1, "6: repeated blur cannot restore registrations twice")
    typed.unregister()
    global.unregister()
    window.fixtureIsKey = true
    recorder.begin()
    window.contentView = nil
    expect(cancelled == 2 && typed.isRegistered && global.isRegistered,
           "6: removing the recorder also restores both suspended registrations")
    window.fixtureIsKey = false
    other.close()
    window.close()
    check(failures.isEmpty, "Workbench adjudication regressions: \(failures.joined(separator: "; "))")
}
