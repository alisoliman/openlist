//
//  OLCards.swift
//  OpenlistiOS
//

import SwiftUI

// MARK: - C25 List cards

/// A list on Lists (`.lcard`): its tint band with the glyph, then its name
/// in two lines at most and "7 open".
struct OLListCard: View {
    let title: String
    let icon: String
    var accent: ListAccent = .graphite
    /// "7 open"; nil draws nothing.
    var detail: String?
    var isInbox = false
    let action: () -> Void

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
                .background(isInbox ? OL.Tint.blue.color : OL.tint(for: accent).color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(OLFont.rowTitleStrong)
                        .foregroundStyle(OL.ink)
                        .lineLimit(2)
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
        .accessibilityLabel([title, detail].compactMap(\.self).joined(separator: ", "))
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

/// Two columns of list cards 14 pt apart (`.lgrid`), more on wider screens.
struct OLListGrid<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14, alignment: .top)], spacing: 14) {
            content
        }
    }
}

// MARK: - C26 List page header

/// The top of a list's page: its tint in a band from the screen's top edge
/// to 38 pt under the top bar, and its glyph on a 60 pt tile overlapping the
/// band's edge by 30. The page's top bar goes inside (`topBar`).
struct OLListHeaderBand<TopBar: View>: View {
    let icon: String
    var accent: ListAccent = .graphite
    var isInbox = false
    @ViewBuilder var topBar: TopBar

    init(icon: String, accent: ListAccent = .graphite, isInbox: Bool = false, @ViewBuilder topBar: () -> TopBar) {
        self.icon = icon
        self.accent = accent
        self.isInbox = isInbox
        self.topBar = topBar()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topBar
            OLTile(icon: icon, accent: accent.color, size: 60, raised: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            // Far above the top, so the band also fills the status bar and a pull down.
            (isInbox ? OL.Tint.blue.color : OL.tint(for: accent).color)
                .frame(height: 44 + 38 + 800)
                .offset(y: -800)
                .padding(.horizontal, -OLMetrics.gutter)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - C27 Now card

/// Today's Now card: "Now · 10:00", the task, "50 min left", and a play
/// button. The whole card opens Working.
struct OLNowCard: View {
    enum State: Equatable {
        /// Planned for now and not started: play.
        case planned
        /// Recording: the button pauses.
        case working
        /// Paused: "Paused" in the Today colour, the button resumes.
        case paused
    }

    let eyebrow: String
    let title: String
    let detail: String
    var state: State = .planned
    let open: () -> Void
    let play: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(state == .paused ? "Paused" : eyebrow)
                        .font(OLFont.meta.weight(.semibold))
                        .foregroundStyle(state == .paused ? OL.todayText : OL.accentText)
                    Text(title)
                        .font(OLFont.rowTitleStrong)
                        .foregroundStyle(OL.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .font(OLFont.meta)
                        .foregroundStyle(OL.muted)
                        .contentTransition(.numericText(countsDown: true))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(OLRowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens Working")
            OLIconButton(state == .working ? "pause.fill" : "play.fill",
                         label: state == .working ? "Pause" : state == .paused ? "Resume" : "Start working",
                         kind: .accent, iconSize: 16, action: play)
        }
        .padding(.vertical, 14)
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .olCard()
    }
}

// MARK: - C28 Empty state

/// A screen with nothing to show (`Today is clear`): a 56 pt disc with the
/// screen's glyph, a serif title, a line of text and an action.
struct OLEmptyState: View {
    let symbol: String
    var tint: Color = OL.today
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background { Circle().fill(OL.surface).olShadow(.card) }
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
}
