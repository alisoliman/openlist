//
//  WidgetCanvas.swift
//  OpenlistWidget
//

import SwiftUI
import WidgetKit

/// Sizes and margins, as the design draws them.
nonisolated enum WidgetMetrics {
    static let cornerRadius: CGFloat = 22

    /// Every kind draws its own margins (configurations use
    /// `.contentMarginsDisabled()`), so layouts match the design to the point
    /// instead of depending on the system's defaults.
    static func insets(for family: WidgetFamily) -> EdgeInsets {
        family == .systemSmall
            ? EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
            : EdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16)
    }

    /// The design's widget sizes, used by the render harness.
    static func size(for family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemMedium: CGSize(width: 358, height: 170)
        case .systemLarge: CGSize(width: 358, height: 358)
        case .systemExtraLarge: CGSize(width: 734, height: 358)
        default: CGSize(width: 170, height: 170)
        }
    }

    /// The sizes macOS 27's widget host (chronod) logs on a current Mac:
    /// small 164, medium 344 × 164 and large 344 × 344. Extra large is two
    /// mediums and the gap between them, 704 × 344. Up to 30 points smaller
    /// than the design's, and every column a view fixes leaves that much less
    /// to the rest, so the render harness draws both.
    static func measuredSize(for family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: CGSize(width: 164, height: 164)
        case .systemMedium: CGSize(width: 344, height: 164)
        case .systemLarge: CGSize(width: 344, height: 344)
        case .systemExtraLarge: CGSize(width: 704, height: 344)
        default: CGSize(width: 164, height: 164)
        }
    }
}

/// Applies a widget's margins and hands its style to the shared components.
/// Used by `WidgetEntryView` and by the render harness, so both lay out the
/// same way.
struct WidgetCanvas<Content: View>: View {
    let family: WidgetFamily
    let style: WidgetStyle
    private let content: Content

    init(family: WidgetFamily, style: WidgetStyle, @ViewBuilder content: () -> Content) {
        self.family = family
        self.style = style
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(WidgetMetrics.insets(for: family))
            .foregroundStyle(style.ink)
            .environment(\.widgetStyle, style)
    }
}

/// The entry view every widget kind uses.
///
/// WidgetKit's family, rendering mode and background visibility only exist in
/// its environment, and are read-only there. Reading them once here and
/// passing `family` and `style` on explicitly lets the render harness draw
/// every family and mode by calling the same widget views directly.
struct WidgetEntryView<Content: View>: View {
    let entry: SnapshotEntry
    private let content: (WidgetFamily, WidgetStyle) -> Content
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    init(entry: SnapshotEntry, @ViewBuilder content: @escaping (WidgetFamily, WidgetStyle) -> Content) {
        self.entry = entry
        self.content = content
    }

    var body: some View {
        let style = WidgetStyle(colorScheme: colorScheme, renderingMode: renderingMode, showsBackground: showsBackground, snapshot: entry.snapshot)
        WidgetCanvas(family: family, style: style) {
            content(family, style)
        }
        .containerBackground(style.bg, for: .widget)
    }
}
