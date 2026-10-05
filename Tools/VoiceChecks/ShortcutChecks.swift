import Foundation

@MainActor
func runVoiceShortcutChecks() {
    let suite = "VoiceShortcutChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    check(!settings.voiceCaptureHotKeyEnabled, "The global voice shortcut is opt-in on every device and build")
    check(settings.voiceCaptureShortcut == .defaultVoice, "Control-Shift-Option-Space is the initial voice combination")
    settings.voiceCaptureHotKeyEnabled = true
    settings.voiceCaptureShortcut = CaptureShortcut(keyCode: 40, modifiers: [.control, .command], keyLabel: "K")
    let restored = AppSettings(defaults: defaults)
    check(restored.voiceCaptureHotKeyEnabled && restored.voiceCaptureShortcut == settings.voiceCaptureShortcut,
          "The enabled state and user-recorded key combination persist")
    settings.voiceCaptureHotKeyEnabled = false
    check(!AppSettings(defaults: defaults).voiceCaptureHotKeyEnabled, "Disabling global voice persists")
    defaults.set(Data("invalid".utf8), forKey: "settings.voiceCaptureShortcut")
    check(AppSettings(defaults: defaults).voiceCaptureShortcut == .defaultVoice, "Corrupt shortcut data has a safe initial combination")

    check(CaptureShortcut.defaultVoice.display == "⌃⇧⌥Space" && CaptureShortcut.defaultVoice.validationFailure == nil,
          "The initial combination is valid and explicitly labelled")
    let modifierSets: [CaptureShortcut.Modifiers] = [[], [.shift], [.option], [.command], [.control]]
    for modifiers in modifierSets {
        check(CaptureShortcut(keyCode: 0, modifiers: modifiers).validationFailure == .needsModifiers,
              "Bare typing keys and single-modifier editing keys cannot become global voice shortcuts")
    }
    check(CaptureShortcut(keyCode: 56, modifiers: [.control, .option]).validationFailure == .unsupportedKey,
          "A modifier by itself cannot be recorded as a key")
    check(CaptureShortcut(keyCode: 49, modifiers: .init(rawValue: 255)).validationFailure == .needsModifiers,
          "Unknown modifier bits are rejected")
    check(CaptureShortcut.typedQuickAdd.validationFailure == .quickAddCollision, "The typed Quick Add combination stays reserved")
    check(CaptureShortcut(keyCode: 9, modifiers: [.option, .command]).validationFailure == .inAppVoiceCollision,
          "The existing in-app voice shortcut stays reserved")
    check(CaptureShortcut(keyCode: 47, modifiers: [.option, .command], keyLabel: "v").validationFailure == .inAppVoiceCollision,
          "The in-app voice shortcut also stays reserved on a different keyboard layout")
    check(CaptureShortcut(keyCode: 40, modifiers: [.control, .command]).validationFailure == nil,
          "A user can choose another modified typing key")

    var registered: [CaptureShortcut] = []
    var released = 0
    var failure: QuickCaptureHotKey.Failure?
    var triggers = 0
    let hotKey = QuickCaptureHotKey(route: .voice, allowsRegistration: true) { shortcut, identifier in
        check(identifier == 2, "Voice registrations use a distinct Carbon hotkey ID")
        registered.append(shortcut)
        if let failure { return .failure(failure) }
        return .success { released += 1 }
    }
    hotKey.onTrigger = { triggers += 1 }
    hotKey.trigger()
    check(triggers == 0, "A disabled hotkey cannot dispatch a queued event")
    hotKey.register(.defaultVoice)
    check(hotKey.isRegistered && hotKey.failure == nil && registered == [.defaultVoice], "An enabled valid combination registers once")
    hotKey.register(.defaultVoice)
    check(registered.count == 1 && released == 0, "Repeated registration refreshes do not re-register unchanged keys")
    hotKey.trigger()
    check(triggers == 1, "An active voice hotkey dispatches its own action")
    let changed = CaptureShortcut(keyCode: 40, modifiers: [.control, .command])
    hotKey.register(changed)
    check(registered == [.defaultVoice, changed] && released == 1, "Editing unregisters the old key before registering the new one")
    hotKey.register(.typedQuickAdd)
    check(!hotKey.isRegistered && hotKey.failure == .invalid(.quickAddCollision) && registered.count == 2 && released == 2,
          "A local collision gives feedback and leaves no stale key active")
    failure = .taken
    hotKey.register(.defaultVoice)
    check(!hotKey.isRegistered && hotKey.failure == .taken, "Another app owning the combination produces collision feedback")
    failure = nil
    hotKey.register(.defaultVoice)
    check(hotKey.isRegistered && hotKey.failure == nil, "Registration can recover after the other app frees the key")
    hotKey.unregister()
    hotKey.trigger()
    check(!hotKey.isRegistered && hotKey.failure == nil && triggers == 1, "Disabling unregisters and suppresses late triggers")

    let fixture = QuickCaptureHotKey(route: .voice, allowsRegistration: false) { _, _ in
        preconditionFailure("A review fixture must never call the real hotkey registration backend")
    }
    fixture.register(.defaultVoice)
    check(!fixture.isRegistered && fixture.failure == nil, "Fixture registration is suppressed even when stored settings enable it")
    let typedFixture = QuickCaptureHotKey(route: .typed, allowsRegistration: false) { _, _ in
        preconditionFailure("Typed fixture shortcuts must also stay local")
    }
    typedFixture.register()
    check(!typedFixture.isRegistered, "Review fixtures cannot grab the existing typed shortcut either")

    let signature = QuickCaptureHotKey.signature
    check(QuickCaptureHotKey.route(signature: signature, identifier: 1) == .typed, "Typed Carbon events route only to typed Quick Add")
    check(QuickCaptureHotKey.route(signature: signature, identifier: 2) == .voice, "Voice Carbon events have their own route")
    check(QuickCaptureHotKey.route(signature: signature, identifier: 3) == nil
          && QuickCaptureHotKey.route(signature: 0, identifier: 1) == nil, "Unrelated hotkey events are never consumed")
    check(QuickCaptureHotKey.Route.typed.request == nil, "Typed hotkeys keep the existing plain Quick Add request")
    check(QuickCaptureHotKey.Route.voice.request == QuickCaptureRequest(listens: true), "Voice hotkeys request listening in the floating panel")

    let voice = QuickCaptureRequest(listens: true)
    check(voice.shouldStartListening(hasDraft: false, isActive: false), "A new floating voice capture starts listening")
    check(!voice.shouldStartListening(hasDraft: true, isActive: false), "Retriggering resumes a typed or spoken draft instead of overwriting it")
    check(!voice.shouldStartListening(hasDraft: false, isActive: true), "Retriggering cannot stop or restart an active recording")
    check(!QuickCaptureRequest().shouldStartListening(hasDraft: false, isActive: false), "Typed Quick Add never starts listening")
    let now = Date.now
    check(voice.keepsDraft(hasDraft: true, keptUntil: now.addingTimeInterval(-1), now: now),
          "A voice retrigger never discards a draft just because its usual retention timer expired")
    check(!QuickCaptureRequest().keepsDraft(hasDraft: true, keptUntil: now.addingTimeInterval(-1), now: now),
          "The typed Quick Add retention policy stays unchanged")
}
