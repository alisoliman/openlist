//
//  QuickCaptureHotKey.swift
//  openlist
//

import AppKit
import Carbon.HIToolbox
import Foundation

/// Registers ⇧⌥Space as a system-wide hot key for quick capture.
///
/// Carbon's `RegisterEventHotKey` is used rather than an `NSEvent` global
/// monitor because it works inside the App Sandbox without the accessibility
/// permission a monitor would demand.
@MainActor
final class QuickCaptureHotKey {
    static let shared = QuickCaptureHotKey()

    /// Invoked on the main actor when the hot key fires.
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature = OSType(0x4F4C_5354) // 'OLST'
    private let identifier: UInt32 = 1

    private init() {}

    var isRegistered: Bool { hotKeyRef != nil }

    func register() {
        guard hotKeyRef == nil else { return }

        installHandlerIfNeeded()

        var hotKeyID = EventHotKeyID(signature: signature, id: identifier)
        let modifiers = UInt32(shiftKey | optionKey)
        let keyCode = UInt32(kVK_Space)

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        // A non-zero status usually means another app already owns the combo;
        // failing quietly is better than blocking launch.
        guard status == noErr else { return }
        hotKeyRef = reference
        _ = hotKeyID
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, _ in
            var firedID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &firedID
            )
            guard status == noErr else { return status }

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    QuickCaptureHotKey.shared.onTrigger?()
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }
}
