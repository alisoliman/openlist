import AppKit
import SwiftUI

struct NXVoiceShortcutSetting: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isRecording = false
    @State private var recordingError: String?

    var body: some View {
        @Bindable var settings = env.settings
        NXSettingToggle(label: "Say tasks from anywhere", hint: shortcutHint,
                        isError: registrationFailure != nil, isOn: $settings.voiceCaptureHotKeyEnabled)
            .accessibilityIdentifier("settings.voiceShortcutEnabled")
            .onChange(of: settings.voiceCaptureHotKeyEnabled) { finishRecording() }
        NXSettingValue(label: "Voice shortcut", hint: "Off by default · initially ⌃⇧⌥Space. Click to record a different combination.",
                       value: isRecording ? "Press shortcut…" : settings.voiceCaptureShortcut.display, action: beginRecording)
            .accessibilityIdentifier("settings.voiceShortcut")
            .background {
                NXShortcutRecorder(isRecording: isRecording, received: receive, cancelled: finishRecording)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .onChange(of: settings.voiceCaptureShortcut) {
                if !isRecording { QuickCaptureHotKey.refresh(settings: settings) }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                if isRecording { finishRecording() }
            }
            .onDisappear { if isRecording { finishRecording() } }
        if isRecording {
            HStack(spacing: 12) {
                Text(recordingError ?? "Hold at least two modifiers and press a key. Escape cancels.")
                    .foregroundStyle(recordingError == nil ? NX.ink(0.55) : NX.redText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Cancel recording", action: finishRecording)
                    .buttonStyle(.plain)
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .accessibilityIdentifier("settings.voiceShortcutRecording")
        }
    }

    private var registrationFailure: QuickCaptureHotKey.Failure? {
        env.settings.voiceCaptureHotKeyEnabled ? QuickCaptureHotKey.voice.failure : nil
    }

    private var shortcutHint: String {
        if !QuickCaptureHotKey.voice.allowsRegistration { return "Global shortcuts are disabled in review sessions." }
        let key = env.settings.voiceCaptureShortcut.display
        switch registrationFailure {
        case .taken: return "\(key) is in use by another app. Change it, or free it there and turn this off and on."
        case .failed: return "\(key) could not be registered. Turn this off and on to retry."
        case let .invalid(reason): return reason.message
        case nil: return "\(key) opens floating Quick Add already listening. No Accessibility permission needed."
        }
    }

    private func beginRecording() {
        guard !isRecording else { return }
        recordingError = nil
        QuickCaptureHotKey.voice.unregister()
        QuickCaptureHotKey.shared.unregister()
        isRecording = true
        AccessibilityNotification.Announcement("Press a shortcut with at least two modifiers. Escape cancels.").post()
    }

    private func receive(_ event: NSEvent) {
        guard isRecording, !event.isARepeat else { return }
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        if event.keyCode == 53, flags.isEmpty { finishRecording(); return }
        var modifiers: CaptureShortcut.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        let shortcut = CaptureShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers,
                                       keyLabel: event.charactersIgnoringModifiers ?? "")
        if let failure = QuickCaptureHotKey.validationFailure(for: shortcut) {
            recordingError = failure.message
            AccessibilityNotification.Announcement(failure.message).post()
            return
        }
        env.settings.voiceCaptureShortcut = shortcut
        finishRecording()
    }

    private func finishRecording() {
        isRecording = false
        recordingError = nil
        QuickCaptureHotKey.refresh(settings: env.settings)
    }
}

struct NXShortcutRecorder: NSViewRepresentable {
    let isRecording: Bool
    let received: (NSEvent) -> Void
    let cancelled: () -> Void

    func makeNSView(context: Context) -> RecorderView { RecorderView() }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.received = received
        view.cancelled = cancelled
        if isRecording { view.begin() } else { view.end() }
    }

    static func dismantleNSView(_ view: RecorderView, coordinator: ()) { view.cancelRecording() }

    final class RecorderView: NSView {
        var received: (NSEvent) -> Void = { _ in }
        var cancelled: () -> Void = {}
        private var isRecording = false
        private weak var previousResponder: NSResponder?
        private var keyObserver: NSObjectProtocol?

        override var acceptsFirstResponder: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func begin() {
            guard !isRecording else { return }
            isRecording = true
            focus()
        }

        func end() {
            isRecording = false
            let previous = previousResponder
            previousResponder = nil
            if window?.firstResponder === self { window?.makeFirstResponder(previous) }
        }

        func cancelRecording() {
            guard isRecording else { return }
            end()
            cancelled()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
            keyObserver = nil
            guard let window else { cancelRecording(); return }
            keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                  object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelRecording() }
            }
            if isRecording { focus() }
        }

        isolated deinit {
            if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        }

        private func focus() {
            guard let window, window.isKeyWindow, window.firstResponder !== self else { return }
            previousResponder = window.firstResponder
            window.makeFirstResponder(self)
        }

        override func resignFirstResponder() -> Bool {
            if isRecording {
                isRecording = false
                previousResponder = nil
                cancelled()
            }
            return super.resignFirstResponder()
        }

        override func keyDown(with event: NSEvent) {
            if isRecording, let window, window.isKeyWindow, event.window === window {
                received(event)
            } else {
                super.keyDown(with: event)
            }
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording, let window, window.isKeyWindow, event.window === window else { return false }
            received(event)
            return true
        }
    }
}
