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

    mutating func end(inside: Bool) -> Action? {
        defer { isPressed = false }
        return isPressed && inside && !held ? .typed : nil
    }

    mutating func cancel() { isPressed = false }
}
