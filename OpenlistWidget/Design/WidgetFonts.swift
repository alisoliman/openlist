//
//  WidgetFonts.swift
//  OpenlistWidget
//

import AppKit
import CoreText

/// Instrument Serif, bundled from `Shared/Fonts` into both the app and the
/// extension.
///
/// The widget Info.plist also declares the font through
/// `ATSApplicationFontsPath`; registering it here as well covers processes
/// that load the extension's code without reading that key, such as previews
/// and the render harness.
nonisolated enum WidgetFonts {
    static let serifName = "InstrumentSerif-Regular"

    /// Registers the serif for this process. Safe to call more than once.
    static func register(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: serifName, withExtension: "ttf") else { return }
        register(url: url)
    }

    static func register(url: URL) {
        // Fails harmlessly with "already registered" on a second call.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// Resolved once, after registration: the answer cannot change later in
    /// the process, and asking AppKit on every render would be wasted work.
    static let hasSerif = NSFont(name: serifName, size: 12) != nil

    /// The height SwiftUI gives one line of system text at `size`, which is
    /// what the design's CSS line heights are measured against. SF's own
    /// line-height tables decide it, not a formula over its metrics; TextKit's
    /// line-fragment measurement reads the same tables and agrees with
    /// SwiftUI at every size and weight.
    static func naturalLineHeight(_ size: CGFloat, weight: NSFont.Weight = .regular, monospaced: Bool = false) -> CGFloat {
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        let line = NSAttributedString(string: "Hg", attributes: [.font: font])
        return line.boundingRect(with: CGSize(width: 1000, height: 1000), options: .usesLineFragmentOrigin).height
    }

    /// The height SwiftUI gives one line of `WidgetStyle.display(size)`,
    /// measured the same way.
    static func naturalDisplayLineHeight(_ size: CGFloat, serifTitles: Bool) -> CGFloat {
        guard serifTitles else { return naturalLineHeight(size * 0.8, weight: .bold) }
        let serif = hasSerif ? NSFont(name: serifName, size: size) : nil
        let font = serif
            ?? NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) }
            ?? NSFont.systemFont(ofSize: size)
        let line = NSAttributedString(string: "Hg", attributes: [.font: font])
        return line.boundingRect(with: CGSize(width: 1000, height: 1000), options: .usesLineFragmentOrigin).height
    }
}
