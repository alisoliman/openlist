//
//  QuickCaptureHotKey.swift
//  openlist
//

import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

/// Registers ⇧⌥Space as a system-wide hot key for quick capture.
///
/// Carbon's `RegisterEventHotKey` is used rather than an `NSEvent` global
/// monitor because it works inside the App Sandbox without the accessibility
/// permission a monitor would demand.
@Observable @MainActor
final class QuickCaptureHotKey {
    static let shared = QuickCaptureHotKey()

    /// Why ⇧⌥Space couldn't be registered, the last time it was tried.
    enum Failure: Equatable {
        /// Another app already owns it.
        case taken
        case failed
    }

    /// Invoked on the main actor when the hot key fires.
    @ObservationIgnored var onTrigger: (() -> Void)?

    /// Whether ⇧⌥Space opens capture from any app now, which the menu bar's
    /// key cap shows.
    private(set) var isRegistered = false
    /// Why the last registration failed, until the next one or `unregister`;
    /// Settings says so under its switch rather than promise the key.
    private(set) var failure: Failure?

    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var eventHandler: EventHandlerRef?
    private let signature = OSType(0x4F4C_5354) // 'OLST'
    private let identifier: UInt32 = 1

    private init() {}

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
        // A non-zero status usually means another app already owns the combo.
        // Launch goes on; Settings says why the key does nothing.
        guard status == noErr else {
            failure = status == OSStatus(eventHotKeyExistsErr) ? .taken : .failed
            return
        }
        hotKeyRef = reference
        isRegistered = true
        failure = nil
        _ = hotKeyID
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        isRegistered = false
        failure = nil
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
