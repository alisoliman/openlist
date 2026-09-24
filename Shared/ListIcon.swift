//
//  ListIcon.swift
//  Shared between the app and the widget extension.
//

import AppKit

/// A list's icon: an emoji, or the name of an SF Symbol from synced or older
/// data, which the app and the widgets draw as the symbol, never as its name.
nonisolated enum ListIcon {
    /// Whether a list icon names an SF Symbol rather than being an emoji.
    static func isSymbolName(_ icon: String) -> Bool {
        icon.allSatisfy { $0.isASCII } && (icon.contains(".") || icon.count > 2)
            && NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil
    }
}
