import AppKit
import Carbon
import Foundation

@MainActor
func runVoiceAdjudicationChecks() async {
    var failures: [String] = []
    func expect(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL"): \(message)")
        if !condition { failures.append(message) }
    }
    func settle() async { for _ in 0..<20 { await Task.yield() } }

    let navigator = PhoneNavigator()
    let original = CaptureRequest(listID: UUID(), dueToday: true)
    navigator.open(.capture(original))
    navigator.open(.capture(CaptureRequest()))
    expect(navigator.sheet == .capture(original) && navigator.captureListenRequestID == nil,
           "2: repeated typed capture preserves the sheet without requesting voice")
    navigator.open(.capture(CaptureRequest(listens: true)))
    expect(navigator.sheet == .capture(original) && navigator.captureListenRequestID == original.id,
           "2: explicit voice reaches the existing sheet without changing its request or destination")
    navigator.captureListenRequestID = nil
    navigator.open(.capture(CaptureRequest(listens: true)))
    expect(navigator.captureListenRequestID == original.id, "2: a later explicit request can be consumed independently")
    navigator.dismissSheet()
    expect(navigator.captureListenRequestID == nil, "2: dismissal clears pending intent so it cannot reach a new draft")

    let vocabulary = SpokenCapture.Vocabulary()
    let voice = VoiceCapture()
    var delivered: [String] = []
    var mode: AppSettings.AfterVoiceCapture?
    func listen(_ text: String) {
        voice.onHeard = { tasks in
            delivered += tasks.map { $0.snapshot.title }
            mode = voice.completionMode
        }
        voice.start(.fixture(text), vocabulary: vocabulary, afterCapture: .saveAutomatically)
    }
    listen("Keep completed speech")
    voice.stop()
    voice.applicationResignedActive()
    await settle()
    expect(delivered == ["Keep completed speech"] && mode == .saveAutomatically,
           "3: app deactivation preserves an intentional stop and queued understanding")
    delivered = []
    listen("Keep interrupted speech")
    voice.applicationResignedActive()
    await settle()
    expect(delivered == ["Keep interrupted speech"] && mode == .reviewBeforeSaving && !voice.isActive,
           "3: app switching stops listening and retains words for review instead of background recording")
    delivered = []
    listen("Cancel this speech")
    let staleStop = voice.listener.onStop
    voice.stop()
    voice.cancel()
    voice.applicationResignedActive()
    staleStop?("Late cancelled speech")
    await settle()
    expect(delivered.isEmpty && voice.phase == .idle, "3: explicit cancel still invalidates pending and late results")

    expect(CaptureShortcut.defaultVoice == CaptureShortcut(keyCode: 49, modifiers: [.control, .shift, .option]),
           "4: the initial voice key avoids the Control-Option-Space input-source binding")
    let nextSource = CaptureShortcut(keyCode: 49, modifiers: [.control, .option])
    func symbolic(_ enabled: Bool) -> [String: Any] {
        [kHISymbolicHotKeyCode as String: 49,
         kHISymbolicHotKeyModifiers as String: controlKey | optionKey,
         kHISymbolicHotKeyEnabled as String: enabled]
    }
    expect(QuickCaptureHotKey.validationFailure(for: nextSource, systemHotKeys: [symbolic(true)], mainMenu: nil) != nil,
           "4: enabled symbolic system hotkeys are rejected before Carbon registration")
    expect(QuickCaptureHotKey.validationFailure(for: nextSource, systemHotKeys: [symbolic(false)], mainMenu: nil) == nil,
           "4: disabled symbolic hotkeys do not reserve a user's custom binding")
    let menu = NSMenu(title: "Fixture")
    let parent = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: "File")
    parent.submenu = submenu
    menu.addItem(parent)
    let item = NSMenuItem(title: "Fixture command", action: nil, keyEquivalent: "k")
    item.keyEquivalentModifierMask = [.control, .command]
    submenu.addItem(item)
    let menuShortcut = CaptureShortcut(keyCode: 40, modifiers: [.control, .command], keyLabel: "k")
    expect(QuickCaptureHotKey.validationFailure(for: menuShortcut, systemHotKeys: [], mainMenu: menu) != nil,
           "4: nested main-menu key equivalents remain reserved even while disabled")
    item.keyEquivalentModifierMask = [.shift, .command]
    expect(QuickCaptureHotKey.validationFailure(for: menuShortcut, systemHotKeys: [], mainMenu: menu) == nil,
           "4: another menu modifier combination does not collide")
    item.keyEquivalent = "K"
    item.keyEquivalentModifierMask = [.command]
    let uppercase = CaptureShortcut(keyCode: 40, modifiers: [.shift, .command], keyLabel: "k")
    expect(QuickCaptureHotKey.validationFailure(for: uppercase, systemHotKeys: [], mainMenu: menu) == .menuCollision,
           "4: uppercase menu equivalents also reserve Shift")
    var enabledEntries: [[String: Any]] = []
    var registrations = 0
    var releases = 0
    let hotKey = QuickCaptureHotKey(route: .voice, allowsRegistration: true, validation: {
        QuickCaptureHotKey.validationFailure(for: $0, systemHotKeys: enabledEntries, mainMenu: nil)
    }) { _, _ in
        registrations += 1
        return .success { releases += 1 }
    }
    hotKey.register(nextSource)
    enabledEntries = [symbolic(true)]
    hotKey.register(nextSource)
    expect(!hotKey.isRegistered && hotKey.failure == .invalid(.systemCollision) && registrations == 1 && releases == 1,
           "4: refreshing an unchanged shortcut rechecks system conflicts and releases the old registration")
    let suite = "VoiceAdjudication-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.voiceCaptureShortcut = nextSource
    expect(AppSettings(defaults: defaults).voiceCaptureShortcut == nextSource,
           "4: existing custom Control-Option-Space bindings are never silently replaced")
    if let actual = QuickCaptureHotKey.systemHotKeys() {
        let oldConflict = QuickCaptureHotKey.validationFailure(for: nextSource, systemHotKeys: actual, mainMenu: nil)
        let newConflict = QuickCaptureHotKey.validationFailure(for: .defaultVoice, systemHotKeys: actual, mainMenu: nil)
        print("Read-only CopySymbolicHotKeys: \(actual.count) entries; old default conflict: \(String(describing: oldConflict)); proposed default conflict: \(String(describing: newConflict))")
        expect(newConflict == nil, "4: the safer default is verified against this Mac's enabled symbolic hotkeys (read only)")
    } else {
        expect(false, "4: CopySymbolicHotKeys must be readable for default verification")
    }
    check(failures.isEmpty, "Voice adjudication regressions: \(failures.joined(separator: "; "))")
}
