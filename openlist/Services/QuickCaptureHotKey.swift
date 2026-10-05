import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

@Observable @MainActor
final class QuickCaptureHotKey {
    nonisolated enum Route: UInt32 {
        case typed = 1, voice = 2

        @MainActor var request: QuickCaptureRequest? {
            switch self {
            case .typed: nil
            case .voice: QuickCaptureRequest(listens: true)
            }
        }
    }

    enum Failure: Error, Equatable {
        case taken, failed
        case invalid(CaptureShortcut.ValidationFailure)
    }

    typealias Registration = (CaptureShortcut, UInt32) -> Result<() -> Void, Failure>
    typealias Validation = (CaptureShortcut) -> CaptureShortcut.ValidationFailure?

    static let shared = QuickCaptureHotKey(route: .typed)
    static let voice = QuickCaptureHotKey(route: .voice)
    nonisolated static let signature: UInt32 = 0x4F4C_5354
    private static var eventHandler: EventHandlerRef?

    @ObservationIgnored var onTrigger: (() -> Void)?
    private(set) var isRegistered = false
    private(set) var failure: Failure?
    let allowsRegistration: Bool
    private let routeKind: Route
    @ObservationIgnored private let registration: Registration
    @ObservationIgnored private let validation: Validation
    @ObservationIgnored private var releaseRegistration: (() -> Void)?
    @ObservationIgnored private var registeredShortcut: CaptureShortcut?

    private convenience init(route: Route) {
        self.init(route: route, allowsRegistration: ReviewSession.identifier == nil,
                  validation: Self.validationFailure(for:), registration: Self.registerCarbon)
    }

    init(route: Route, allowsRegistration: Bool, validation: @escaping Validation = { $0.validationFailure },
         registration: @escaping Registration) {
        self.routeKind = route
        self.allowsRegistration = allowsRegistration
        self.registration = registration
        self.validation = validation
    }

    func register(_ shortcut: CaptureShortcut? = nil) {
        guard allowsRegistration else { unregister(); return }
        let chosen = routeKind == .typed ? .typedQuickAdd : shortcut ?? .defaultVoice
        if routeKind == .voice, let invalid = validation(chosen) {
            unregister()
            failure = .invalid(invalid)
            return
        }
        guard chosen != registeredShortcut else { return }
        unregister()
        switch registration(chosen, routeKind.rawValue) {
        case let .success(release):
            releaseRegistration = release
            registeredShortcut = chosen
            isRegistered = true
        case let .failure(failure):
            self.failure = failure
        }
    }

    func unregister() {
        releaseRegistration?()
        releaseRegistration = nil
        registeredShortcut = nil
        isRegistered = false
        failure = nil
    }

    static func validationFailure(for shortcut: CaptureShortcut, systemHotKeys: [[String: Any]],
                                  mainMenu: NSMenu?) -> CaptureShortcut.ValidationFailure? {
        if let invalid = shortcut.validationFailure { return invalid }
        let mask = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        if systemHotKeys.contains(where: { entry in
            (entry[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true
                && (entry[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == shortcut.keyCode
                && (entry[kHISymbolicHotKeyModifiers as String] as? NSNumber).map { $0.uint32Value & mask } == shortcut.carbonModifiers
        }) { return .systemCollision }
        if let mainMenu, menu(mainMenu, uses: shortcut.menuKeyEquivalent, modifiers: shortcut.modifiers) { return .menuCollision }
        return nil
    }

    static func validationFailure(for shortcut: CaptureShortcut) -> CaptureShortcut.ValidationFailure? {
        if let invalid = shortcut.validationFailure { return invalid }
        guard let hotKeys = systemHotKeys() else { return .systemUnavailable }
        return validationFailure(for: shortcut, systemHotKeys: hotKeys, mainMenu: NSApp?.mainMenu)
    }

    static func systemHotKeys() -> [[String: Any]]? {
        var entries: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&entries) == noErr, let entries else { return nil }
        return entries.takeRetainedValue() as? [[String: Any]]
    }

    private static func menu(_ menu: NSMenu, uses key: String, modifiers: CaptureShortcut.Modifiers) -> Bool {
        guard !key.isEmpty else { return false }
        for item in menu.items {
            var itemModifiers: CaptureShortcut.Modifiers = []
            let flags = item.keyEquivalentModifierMask
            if flags.contains(.control) { itemModifiers.insert(.control) }
            if flags.contains(.option) { itemModifiers.insert(.option) }
            if flags.contains(.shift) { itemModifiers.insert(.shift) }
            if flags.contains(.command) { itemModifiers.insert(.command) }
            if item.keyEquivalent != item.keyEquivalent.lowercased() { itemModifiers.insert(.shift) }
            if item.keyEquivalent.lowercased() == key.lowercased(), itemModifiers == modifiers { return true }
            if let submenu = item.submenu, self.menu(submenu, uses: key, modifiers: modifiers) { return true }
        }
        return false
    }

    func trigger() {
        guard isRegistered else { return }
        onTrigger?()
    }

    static func refresh(settings: AppSettings) {
        if settings.quickCaptureHotKeyEnabled { shared.register() } else { shared.unregister() }
        if settings.voiceCaptureHotKeyEnabled { voice.register(settings.voiceCaptureShortcut) } else { voice.unregister() }
    }

    nonisolated static func route(signature: UInt32, identifier: UInt32) -> Route? {
        signature == Self.signature ? Route(rawValue: identifier) : nil
    }

    private static func registerCarbon(_ shortcut: CaptureShortcut, identifier: UInt32) -> Result<() -> Void, Failure> {
        guard installHandlerIfNeeded() else { return .failure(.failed) }
        let hotKeyID = EventHotKeyID(signature: signature, id: identifier)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else {
            return .failure(status == OSStatus(eventHotKeyExistsErr) ? .taken : .failed)
        }
        return .success { UnregisterEventHotKey(reference) }
    }

    private static func installHandlerIfNeeded() -> Bool {
        guard eventHandler == nil else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ in
            var firedID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &firedID)
            guard status == noErr else { return status }
            guard let route = QuickCaptureHotKey.route(signature: firedID.signature, identifier: firedID.id) else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch route {
                    case .typed: QuickCaptureHotKey.shared.trigger()
                    case .voice: QuickCaptureHotKey.voice.trigger()
                    }
                }
            }
            return noErr
        }
        return InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &eventHandler) == noErr
    }
}

private extension CaptureShortcut {
    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }

    var menuKeyEquivalent: String {
        if !keyLabel.isEmpty { return keyLabel }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "" }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return "" }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        guard UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                             OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters) == noErr else { return "" }
        return String(utf16CodeUnits: characters, count: length)
    }
}
