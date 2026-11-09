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

/// Today's Now card: "Now · 10:00", the task, "50 min left", and a play
/// button. The whole card opens Working; the button starts the work, resumes
/// it, or goes back to it while it runs.
struct OLNowCard: View {
    enum State: Equatable {
        /// Planned for now and not started: play.
        case planned
        /// Recording: the button opens Working.
        case working
        /// Paused: "Paused" in grey, the button resumes.
        case paused
    }

    let eyebrow: String
    let title: String
    let detail: String
    var state: State = .planned
    let open: () -> Void
    let play: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // The tile and the card's padding are the open target's too; the
        // play button keeps its own.
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: state == .paused ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OL.ink)
                        .frame(width: 42, height: 48)
                        .background(OL.sunken, in: .rect(cornerRadius: 12))
                        .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(state == .paused ? "Paused" : eyebrow)
                            .font(OLFont.meta.weight(.semibold))
                            .foregroundStyle(state == .paused ? OL.muted : OL.accentText)
                        Text(title)
                            .font(OLFont.rowTitleStrong)
                            .foregroundStyle(OL.ink)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .multilineTextAlignment(.leading)
                        Text(detail)
                            .font(OLFont.meta)
                            .foregroundStyle(OL.muted)
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 14)
                .padding(.leading, 16)
                .contentShape(.rect)
            }
            .buttonStyle(OLRowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens Working")
            OLIconButton("play.fill",
                         label: state == .working ? "Open Working" : state == .paused ? "Resume" : "Start working",
                         kind: .accent, iconSize: 16, action: play)
        }
        .padding(.trailing, 14)
        .olCard()
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
