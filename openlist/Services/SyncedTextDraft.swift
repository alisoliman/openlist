import Foundation

struct SyncedTextDraft {
    var value = ""
    private(set) var original = ""

    mutating func reset(to value: String) {
        self.value = value
        original = value
    }

    mutating func receive(_ value: String) {
        guard self.value == original else { return }
        reset(to: value)
    }

    func editedValue(normalize: (String) -> String) -> String? {
        let normalized = normalize(value)
        return normalized == normalize(original) ? nil : normalized
    }
}
