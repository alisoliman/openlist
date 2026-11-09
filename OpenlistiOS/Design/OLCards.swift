//
//  OLCards.swift
//  OpenlistiOS
//

import SwiftUI

// MARK: - C25 List cards

/// A list on Lists (`.lcard`): a grey band with its glyph, in the list's
/// colour when it's a symbol, then its name and "7 open". Names use two
/// lines normally and wrap at accessibility sizes.
struct OLListCard: View {
    let title: String
    let icon: String
    var accent: ListAccent = .graphite
    /// "7 open"; nil draws nothing.
    var detail: String?
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    OLListGlyph(icon: icon, accent: accent.color, size: 30)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
                .frame(height: 56, alignment: .bottom)
                .frame(maxWidth: .infinity)
                .background(OL.band)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(OLFont.rowTitleStrong)
                        .foregroundStyle(OL.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail)
                            .font(OLFont.meta)
                            .foregroundStyle(OL.muted)
                            .contentTransition(.numericText())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .olCard()
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(OLPressStyle(scale: 0.97))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(detail ?? "")
    }
}

/// The dashed "+ New list" card.
struct OLNewListCard: View {
    var title = "New list"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 20, weight: .regular))
                Text(title).font(OLFont.note.weight(.semibold))
            }
            .foregroundStyle(OL.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 110)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(OL.line, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(OLPressStyle(scale: 0.97))
    }
}

/// Cards 14 pt apart (`.lgrid`): adaptive columns normally, one at accessibility sizes.
struct OLListGrid<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        let column: GridItem.Size = dynamicTypeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 150)
        LazyVGrid(columns: [GridItem(column, spacing: 14, alignment: .top)], spacing: 14) {
            content
        }
    }
}

// MARK: - C26 List page header

/// The top of a list's page: a grey band from the screen's top edge to 38 pt
/// under the top bar, and its glyph on a 60 pt tile overlapping the band's
/// edge by 30. The list's colour is its glyph's, not the band's. The page's
/// top bar goes inside (`topBar`).
struct OLListHeaderBand<TopBar: View>: View {
    let icon: String
    var accent: ListAccent = .graphite
    /// Makes the tile a button, which opens the list's Icon & colour.
    var editAppearance: (() -> Void)?
    @ViewBuilder var topBar: TopBar

    init(icon: String, accent: ListAccent = .graphite, editAppearance: (() -> Void)? = nil,
         @ViewBuilder topBar: () -> TopBar) {
        self.icon = icon
        self.accent = accent
        self.editAppearance = editAppearance
        self.topBar = topBar()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topBar
            let tile = OLTile(icon: icon, accent: accent.color, size: 60, raised: true)
            if let editAppearance {
                Button(action: editAppearance) { tile }
                    .buttonStyle(OLPressStyle())
                    .accessibilityLabel("Icon & colour")
                    .accessibilityValue(ListIcon.isSymbolName(icon) ? "" : icon)
                    .accessibilityIdentifier("list.icon")
            } else {
                tile
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            // Far above the top, so the band also fills the status bar and a pull down.
            OL.band
                .frame(height: 44 + 38 + 800)
                .offset(y: -800)
                .padding(.horizontal, -OLMetrics.gutter)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - C27 Now card

/// Today's Now card (the Mac's schedule summary): what's on now and what
/// comes next, meetings and planned sessions alike, as `OLNowCardLine`s, then
/// quiet notes (`OLNowNote`) with a light way on. The lines say it; the
/// card adds no title of its own.
struct OLNowCard<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .olCard()
    }
}

/// Where a line of the Now card stands in the day.
enum OLNowRole: Equatable {
    case now
    /// Under way too, beside the first: no label of its own.
    case alsoNow
    case next

    var label: String {
        switch self {
        case .now: "Now"
        case .alsoNow: ""
        case .next: "Next"
        }
    }
}

/// One line of the Now card: "NOW" or "NEXT" in a small column, the title,
/// and under it the time and place, a session's list marked by its colour.
/// What's on now is a step heavier than what comes next. VoiceOver reads it
/// as one: "Now: Draft Q3 OKRs", then its detail.
struct OLNowCardLine: View {
    let role: OLNowRole
    let title: String
    let detail: String
    /// A session's list colour, a dot before its detail; nil for a meeting.
    var listColor: Color?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The label column, which titles line up after: 46 pt at the default
    /// size, growing with the caps' text so "NEXT" never breaks in two.
    @ScaledMetric(relativeTo: .caption2) private var labelWidth: CGFloat = 46

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    if !role.label.isEmpty { label }
                    text
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    label.fixedSize().frame(width: labelWidth, alignment: .leading)
                    text
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(role == .alsoNow ? "Also now: \(title)" : "\(role.label): \(title)")
        .accessibilityValue(detail)
    }

    private var label: some View {
        Text(role.label)
            .olCaps()
            .foregroundStyle(OL.muted)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(OLFont.rowTitle.weight(role == .next ? .medium : .semibold))
                .foregroundStyle(OL.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .multilineTextAlignment(.leading)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let listColor {
                    Circle().fill(listColor)
                        .frame(width: 7, height: 7)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3.5 }
                }
                Text(detail)
                    .font(OLFont.meta)
                    .monospacedDigit()
                    .foregroundStyle(OL.muted)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .contentTransition(.numericText(countsDown: true))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Now card folded to one line: what's on now, or what's next, and
/// when, "NOW  Design review  Until 11:30", or what the card says with
/// nothing on. The title gives way before the time does. At accessibility
/// sizes the label, title and time stack, as a line's do.
struct OLNowCardSummary: View {
    /// Nil for the card's empty text, which stands alone.
    var role: OLNowRole?
    let title: String
    var time: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// As `OLNowCardLine`'s, so the folded title starts where it did.
    @ScaledMetric(relativeTo: .caption2) private var labelWidth: CGFloat = 46

    var body: some View {
        Group {
            if let role {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        label(role)
                        titleText.lineLimit(2)
                        if let time { timeText(time) }
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        label(role).fixedSize().frame(width: labelWidth, alignment: .leading)
                        titleText.lineLimit(1)
                        if let time { timeText(time).fixedSize().padding(.leading, 8) }
                    }
                }
            } else {
                Text(title)
                    .font(OLFont.note)
                    .foregroundStyle(OL.muted)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func label(_ role: OLNowRole) -> some View {
        Text(role.label)
            .olCaps()
            .foregroundStyle(OL.muted)
    }

    private var titleText: some View {
        Text(title)
            .font(OLFont.rowTitle.weight(role == .next ? .medium : .semibold))
            .foregroundStyle(OL.ink)
    }

    private func timeText(_ time: String) -> some View {
        Text(time)
            .font(OLFont.meta)
            .monospacedDigit()
            .foregroundStyle(OL.muted)
            .contentTransition(.numericText(countsDown: true))
    }
}

/// The Now card's fold: a quiet chevron in its top line that points down
/// while the card is folded to one line and turns up once it's open.
/// VoiceOver reads it as the schedule, expanded or collapsed.
struct OLNowCardFold: View {
    let isFolded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(OLFont.meta.weight(.semibold))
                .foregroundStyle(OL.muted)
                .rotationEffect(.degrees(isFolded ? 0 : 180))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(OLPressStyle())
        .accessibilityLabel("Schedule")
        .accessibilityValue(isFolded ? "Collapsed" : "Expanded")
        .accessibilityHint(isFolded ? "Shows the whole schedule" : "Folds the schedule to one line")
    }
}

/// A quiet note under the Now card's lines, with one small button: "4 tasks
/// have no time yet · Fit", "No calendar connected · Connect".
struct OLNowNote: View {
    let text: String
    let actionTitle: String
    /// The button's identifier, for UI tests.
    var identifier: String?
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ text: String, actionTitle: String, identifier: String? = nil, action: @escaping () -> Void) {
        self.text = text
        self.actionTitle = actionTitle
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            Text(text)
                .font(OLFont.meta)
                .foregroundStyle(OL.muted)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(actionTitle, action: action)
                .buttonStyle(.ol(.neutral, size: .small))
                .accessibilityIdentifier(identifier ?? "")
        }
        .frame(minHeight: 44)
    }
}

// MARK: - C28 Empty state

/// What a screen shows while its content is still on its way: a native
/// spinner and a line of text, where its empty state would be.
struct OLLoadingState: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title)
                .font(OLFont.note)
                .foregroundStyle(OL.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
        .accessibilityElement(children: .combine)
    }
}

/// A screen with nothing to show (`Today is clear`): a 56 pt disc with the
/// screen's glyph, grey unless it means something (a list's colour, a done
/// tick's green), a serif title, a line of text and an action. A
/// `checkmark` is the design's own tick, 24 pt at a 2.4 stroke.
struct OLEmptyState: View {
    let symbol: String
    var tint: Color = OL.muted
    /// A flat disc in this colour, as Triage's finished tick, instead of the
    /// raised surface one.
    var fill: Color?
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            glyph
                .frame(width: 56, height: 56)
                .background {
                    if let fill { Circle().fill(fill) } else { Circle().fill(OL.surface).olShadow(.card).olDarkRing(Circle()) }
                }
                .accessibilityHidden(true)
            OLTitle(title, size: 28, lineHeight: 32, style: .title)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            if let message {
                Text(message)
                    .font(OLFont.note)
                    .foregroundStyle(OL.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.olLink())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var glyph: some View {
        if symbol == "checkmark" {
            OLTick()
                .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tint)
        }
    }
}

/// What couldn't be read, in the place of what a screen would show: why, in
/// a line, and Try Again. Never an empty state, which would say there's
/// nothing there.
struct OLLoadFailure: View {
    let message: String
    let retry: () -> Void

    init(_ message: String, retry: @escaping () -> Void) {
        self.message = message
        self.retry = retry
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(message)
                .font(OLFont.note)
                .foregroundStyle(OL.muted)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retry).buttonStyle(.olLink())
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
