struct CapturePress {
    enum Action { case typed, voice }

    private(set) var isPressed = false
    private var held = false

    mutating func begin() {
        guard !isPressed else { return }
        isPressed = true
        held = false
    }

    mutating func recognizeHold() -> Action? {
        guard isPressed, !held else { return nil }
        held = true
        return .voice
    }

    /// A lift inside types, unless the press was a hold. `heldLongEnough`,
    /// a finger kept in place past the hold's time by the touches' own
    /// clock, is a hold whose recognizer the lift beat: a busy main thread
    /// handles a waiting lift before a hold's due timer.
    mutating func end(inside: Bool, heldLongEnough: Bool = false) -> Action? {
        defer { isPressed = false }
        guard isPressed, inside, !held else { return nil }
        return heldLongEnough ? .voice : .typed
    }

    mutating func cancel() { isPressed = false }
}
