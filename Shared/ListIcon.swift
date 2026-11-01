//
//  ListIcon.swift
//  Shared between the app and the widget extension.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A list's icon: an emoji, or the name of an SF Symbol from synced or older
/// data, which the app and the widgets draw as the symbol, never as its name.
nonisolated enum ListIcon {
    /// The emoji Icon & Colour offers on the Mac and the iPhone; any other
    /// can be typed or pasted in.
    static let suggestions = [
        "📋", "✅", "🌱", "🏡", "💼", "📚", "🗻", "✈️", "🛒", "🎯",
        "💡", "🎨", "🎵", "🍳", "🏋️", "💰", "🐾", "🎁", "🧹", "📝",
        "🔧", "🌍", "☕️", "🌙", "🔥", "⭐️", "🧠", "🎬", "🚲", "🧺",
    ]

    /// Whether a list icon names an SF Symbol rather than being an emoji.
    static func isSymbolName(_ icon: String) -> Bool {
        icon.allSatisfy { $0.isASCII } && (icon.contains(".") || icon.count > 2)
            && symbolExists(icon)
    }

    /// The first emoji in what was typed, pasted or picked from the system's
    /// emoji into Icon & Colour's field, or nil when it holds none: letters,
    /// digits and symbols with no emoji form are no icon.
    static func emoji(in text: String) -> String? {
        text.first(where: isEmoji).map(String.init)
    }

    /// Drawn as an emoji: one that is by default, or a sequence that asks to
    /// be, such as ✈️, 1️⃣ or a flag, unless it asks for its text form.
    private static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first?.properties, first.isEmoji, !scalars.contains("\u{FE0E}") else { return false }
        return first.isEmojiPresentation || scalars.count > 1
    }

    private static func symbolExists(_ name: String) -> Bool {
        #if os(macOS)
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        #else
        UIImage(systemName: name) != nil
        #endif
    }
}
