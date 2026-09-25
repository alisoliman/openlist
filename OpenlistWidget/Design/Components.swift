//
//  Components.swift
//  OpenlistWidget
//

import AppIntents
import AppKit
import SwiftUI
import WidgetKit

/// "+4 more", indented to line up with the row titles above it.
struct MoreLabel: View {
    let count: Int
    /// The checkbox (15) plus the row's gap (8).
    var indent: CGFloat = 23
    @Environment(\.widgetStyle) private var style

    var body: some View {
        Text("+\(count) more")
            .foregroundStyle(style.faint)
            .textStyle(10.5, .medium, lineHeight: 1)
            .padding(.leading, indent)
    }
}

/// The "+ New task" chip at the foot of Today and List. Opens Openlist.
struct ChipLink: View {
    let title: String
    var systemImage = "plus"
    let link: WidgetLink
    @Environment(\.widgetStyle) private var style

    init(_ title: String, systemImage: String = "plus", link: WidgetLink) {
        self.title = title
        self.systemImage = systemImage
        self.link = link
    }

    var body: some View {
        AppLink(link) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(style.acc)
                    .widgetAccentable()
                    .frame(width: 14, height: 14)
                Text(title)
                    .foregroundStyle(style.ink)
                    .lineLimit(1)
                    .textStyle(11, .semibold, lineHeight: 1)
            }
            .padding(.vertical, 5)
            .padding(.leading, 6)
            .padding(.trailing, 9)
            .background(style.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityLabel(title)
    }
}

/// Today's completion ring: green progress on a track, starting at twelve.
///
/// The design draws it as an r=10 circle in a 24-point box scaled to `size`,
/// so the stroke defaults to the matching share of the design's 3.2.
struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = 20
    var lineWidth: CGFloat?
    /// Defaults to `green`.
    var color: Color?
    @Environment(\.widgetStyle) private var style

    init(fraction: Double, size: CGFloat = 20, lineWidth: CGFloat? = nil, color: Color? = nil) {
        self.fraction = fraction
        self.size = size
        self.lineWidth = lineWidth
        self.color = color
    }

    var body: some View {
        let width = lineWidth ?? size * 3.2 / 24
        ZStack {
            Circle().stroke(style.track, lineWidth: width)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(color ?? style.green, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .frame(width: size * 20 / 24, height: size * 20 / 24)
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent")
    }
}

/// A 3-point progress bar: Up Next's block and the List header.
struct ProgressLine: View {
    let fraction: Double
    /// Defaults to `acc`.
    var color: Color?
    var height: CGFloat = 3
    @Environment(\.widgetStyle) private var style

    init(fraction: Double, color: Color? = nil, height: CGFloat = 3) {
        self.fraction = fraction
        self.color = color
        self.height = height
    }

    var body: some View {
        Capsule()
            .fill(style.track)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(color ?? style.acc)
                        .frame(width: proxy.size.width * min(1, max(0, fraction)))
                        .widgetAccentable()
                }
            }
            .accessibilityHidden(true)
    }
}

/// A list's emoji (or SF Symbol) on a soft tile of its colour.
struct ListGlyph: View {
    let icon: String
    let accentHex: UInt32
    var size: CGFloat = 28
    @Environment(\.widgetStyle) private var style

    init(icon: String, accentHex: UInt32, size: CGFloat = 28) {
        self.icon = icon
        self.accentHex = accentHex
        self.size = size
    }

    var body: some View {
        glyph
            .frame(width: size, height: size)
            .background(style.listTint(accentHex), in: RoundedRectangle(cornerRadius: size * 9 / 28, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        if Self.isSymbol(icon) {
            Image(systemName: icon)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(style.listColor(accentHex))
        } else {
            // Vibrant rendering keeps the emoji's shape but not its colours.
            // The design's 15 px on a 28-point tile, drawn as large as the
            // design draws it rather than at Core Text's larger size.
            Text(verbatim: icon)
                .font(.system(size: EmojiSize.points(forDesign: size * 15 / 28)))
                .grayscale(style.isVibrant ? 1 : 0)
                .brightness(style.isVibrant ? 0.3 : 0)
        }
    }

    /// Lists store an emoji, or an SF Symbol name, as the app's sidebar does.
    static func isSymbol(_ icon: String) -> Bool { ListIcon.isSymbolName(icon) }
}

/// The 32-point round buttons on Up Next: Start, Pause, Resume and Done.
struct RoundIconButton<Intent: AppIntent>: View {
    enum Role {
        /// Accent fill with a soft accent shadow: Start.
        case primary
        /// Quiet chip fill: Pause and Resume.
        case secondary
        /// Green fill: Done.
        case confirm
    }

    let label: String
    let systemImage: String
    var role = Role.primary
    let intent: Intent
    @Environment(\.widgetStyle) private var style

    init(_ label: String, systemImage: String, role: Role = .primary, intent: Intent) {
        self.label = label
        self.systemImage = systemImage
        self.role = role
        self.intent = intent
    }

    var body: some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: role == .confirm ? .bold : .regular))
                .foregroundStyle(role == .secondary ? style.ink : style.onAcc)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(fill)
                        .widgetAccentable(role != .secondary)
                        .shadow(color: role == .primary ? style.accShadow : .clear, radius: 6, y: 5)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var fill: Color {
        switch role {
        case .primary: style.acc
        case .secondary: style.chip
        case .confirm: style.green
        }
    }

    /// Matches the optical size of the design's Material icons.
    private var iconSize: CGFloat {
        switch role {
        case .primary: 13
        case .secondary: 11.5
        case .confirm: 12
        }
    }
}

/// A 0.5-point rule in `line`: the dividers between a widget's columns and
/// above its footer.
struct Hairline: View {
    var axis: Axis = .horizontal
    @Environment(\.widgetStyle) private var style

    init(_ axis: Axis = .horizontal) {
        self.axis = axis
    }

    var body: some View {
        Rectangle()
            .fill(style.line)
            .frame(width: axis == .vertical ? 0.5 : nil, height: axis == .horizontal ? 0.5 : nil)
    }
}

/// A centred message for a widget with nothing to list.
struct WidgetEmptyState: View {
    let systemImage: String
    let title: String
    var message: String?
    /// Defaults to `green`, for the "all done" states.
    var tint: Color?
    @Environment(\.widgetStyle) private var style

    init(systemImage: String, title: String, message: String? = nil, tint: Color? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.tint = tint
    }

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint ?? style.green)
                .widgetAccentable()
                .padding(.bottom, 2)
            Text(title)
                .foregroundStyle(style.ink)
                .textStyle(13, .semibold, lineHeight: 1.2)
            if let message {
                Text(message)
                    .foregroundStyle(style.sub)
                    .multilineTextAlignment(.center)
                    .textStyle(11, .medium, lineHeight: 1.3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Shown when the app has never published a snapshot, or the widget cannot
/// read it (`SnapshotEntry.isPlaceholder`). Tapping the widget opens the app,
/// which writes one.
struct OpenAppPrompt: View {
    /// A snapshot days old rather than none at all.
    var isOutdated = false
    @Environment(\.widgetStyle) private var style

    var body: some View {
        WidgetEmptyState(systemImage: isOutdated ? "arrow.clockwise" : "checklist", title: "Open Openlist",
                         message: isOutdated ? "To bring today up to date." : "Your tasks will show up here.", tint: style.acc)
    }
}

/// The recorded time, "00:04". While working it ticks by itself through the
/// system's live stopwatch text, so the widget needs no reload per second;
/// while paused it stands still. Both go through the same format, so pausing
/// never changes how the time is written.
struct WorkClock: View {
    let upNext: UpNext
    let now: Date

    var body: some View {
        if let origin = upNext.timerOrigin {
            #if WIDGET_RENDER
            // The harness has no live source; draw the entry's moment.
            Text(Self.format(from: origin).format(now))
            #else
            Text(.currentDate, format: Self.format(from: origin))
            #endif
        } else {
            Text(Self.format(from: now.addingTimeInterval(-upNext.elapsed)).format(now))
        }
    }

    /// "00:04" and "59:59", then "01:02:05" past the hour.
    private static func format(from origin: Date) -> SystemFormatStyle.Stopwatch {
        .stopwatch(startingAt: origin, showsHours: true, maxFieldCount: 3, maxPrecision: .seconds(1))
    }
}
