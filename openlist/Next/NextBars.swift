//
//  NextBars.swift
//  openlist
//

import SwiftUI

/// The dark floating bar that acts on a multi-selection.
struct NXSelectionBar: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style

    /// How much of each button fits, e.g. beside the inspector in a narrow window.
    private enum Fit { case full, titles, icons }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(.full)
            bar(.titles)
            bar(.icons)
        }
        .foregroundStyle(.white)
        .padding(6)
        .environment(\.colorScheme, .dark)
        // Outside the dark scheme, so the surface follows the window's appearance.
        .background(NX.inverse, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: Color(hex: 0x17161A).opacity(0.36), radius: 20, y: 16)
    }

    /// The selected rows the current screen shows, in screen order: what the
    /// bar counts and acts on, and whether it shows at all.
    static func selected(_ workbench: Workbench) -> [UUID] {
        workbench.visibleIDs.filter(workbench.selection.contains)
    }

    private func bar(_ fit: Fit) -> some View {
        let workbench = env.workbench
        // The buttons act on the rows the count was taken from, so the two
        // agree even if rows leave the screen before the bar is drawn again.
        let ids = Self.selected(workbench)
        let count = ids.count
        return HStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 22, minHeight: 22)
                .padding(.horizontal, count > 9 ? 6 : 0)
                .background(style.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(.trailing, fit == .icons ? 4 : 0)
                .accessibilityLabel("\(count) selected")
            if fit != .icons {
                Text("selected")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.leading, 6)
                    .padding(.trailing, 10)
                    .accessibilityHidden(true)
            }
            divider
            barButton("Done", icon: "checkmark.circle", key: "E", tint: Color(hex: 0x6FD3A4), fit: fit) { workbench.complete(ids) }
            barButton("Today", icon: "calendar", key: "T", tint: Color(hex: 0xC9AEFF), fit: fit) { workbench.schedule(ids, offset: 0) }
            barButton("Tomorrow", icon: "sun.horizon", key: "M", tint: Color(hex: 0xC9AEFF), fit: fit) { workbench.schedule(ids, offset: 1) }
            barButton("Plan", icon: "calendar.badge.clock", key: "P", tint: Color(hex: 0xC9AEFF), fit: fit) { workbench.plan(ids) }
            barButton("Star", icon: "star", key: "F", tint: Color(hex: 0xF2C14E), fit: fit) { workbench.star(ids) }
            barButton("Trash", icon: "trash", key: "D", tint: Color(hex: 0xFF8A8A), hover: Color(red: 1, green: 0.47, blue: 0.47).opacity(0.14),
                      fit: fit) {
                workbench.trash(ids)
            }
            divider
            Button { workbench.selection = [] } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(NXHoverButtonStyle(hover: .white.opacity(0.1), radius: 8,
                                            padding: EdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7),
                                            foreground: .white.opacity(0.7), hoverForeground: .white))
            .help("Clear selection (Esc)")
            .accessibilityLabel("Clear selection")
        }
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 18).padding(.horizontal, 4)
    }

    private func barButton(_ title: String, icon: String, key: String, tint: Color, hover: Color = .white.opacity(0.1),
                           fit: Fit, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                if fit != .icons { Text(title).font(.system(size: 12, weight: .medium)) }
                if fit == .full { NXKey(key, opacity: 0.5, size: 9.5) }
            }
        }
        .buttonStyle(NXHoverButtonStyle(hover: hover, radius: 8,
                                        padding: EdgeInsets(top: 7, leading: fit == .icons ? 7 : 9,
                                                            bottom: 7, trailing: fit == .icons ? 7 : 9),
                                        foreground: .white))
        .help("\(title) (\(key))")
        .accessibilityLabel(title)
    }
}

/// The short-lived confirmation with Undo and an optional destination link.
/// It stays up as one message follows another: the text changes in place and
/// only the drain starts over.
struct NXTray: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let message: TrayMessage

    var body: some View {
        let workbench = env.workbench
        let tint = Self.tint(message.tone)
        HStack(spacing: 10) {
            // The design's 15pt icon line sets a plain message's height; only
            // Undo or a destination's pill makes the tray taller.
            Image(systemName: message.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(height: 15)
            NXWidthCap(460) {
                Text(message.text)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
            }
            if let destination = message.destination, workbench.offers(destination) {
                Button(destination.label) {
                    workbench.follow(destination)
                    workbench.dismissTray()
                }
                .font(.system(size: 11.5, weight: .semibold))
                .buttonStyle(NXHoverButtonStyle(hover: .white.opacity(0.18), rest: .white.opacity(0.1), radius: 7,
                                                padding: EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9),
                                                foreground: .white))
            }
            if message.undoable, workbench.canUndo {
                Button("Undo ⌘Z") { workbench.undoLast() }
                    .font(.system(size: 11.5, weight: .semibold))
                    .buttonStyle(NXHoverButtonStyle(hover: Color(hex: 0xC9AEFF, opacity: 0.24), rest: Color(hex: 0xC9AEFF, opacity: 0.14), radius: 7,
                                                    padding: EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9),
                                                    foreground: Color(hex: 0xC9AEFF)))
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .overlay(alignment: .bottomLeading) {
            NXTrayDrain(color: Self.drain(message.tone, accent: style.accent), dwell: style.dwell)
                .id(message.id)
        }
        .environment(\.colorScheme, .dark)
        // Outside the dark scheme, so the surface follows the window's appearance.
        .background(NX.inverse)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .shadow(color: Color(hex: 0x17161A).opacity(0.34), radius: 17, y: 14)
        // A new message swaps in without animating the tray's size.
        .animation(nil, value: message.id)
    }

    /// The drain takes the saturated tone, not the icon's pastel; the
    /// neutral one is the design's dark ink, barely there on the tray.
    static func drain(_ tone: TrayTone, accent: Color) -> Color {
        switch tone {
        case .green: Color(hex: 0x2F9E6E)
        case .red: Color(hex: 0xC03A42)
        case .amber: Color(hex: 0xA87A06)
        case .accent: accent
        case .neutral: Color(hex: 0x17161A, opacity: 0.6)
        }
    }

    static func tint(_ tone: TrayTone) -> Color {
        switch tone {
        case .green: Color(hex: 0x6FD3A4)
        case .red: Color(hex: 0xFF8A8A)
        case .amber: Color(hex: 0xF2C14E)
        case .accent, .neutral: Color(hex: 0xC9AEFF)
        }
    }
}

/// The 2pt bar that empties over the dwell. The tray gives each message a new
/// one, so the drain starts over while the tray stays put.
private struct NXTrayDrain: View {
    let color: Color
    let dwell: Double
    @State private var drained = false

    var body: some View {
        GeometryReader { geo in
            Rectangle().fill(color)
                .frame(width: geo.size.width, height: 2)
                .scaleEffect(x: drained ? 0 : 1, y: 1, anchor: .leading)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear { withAnimation(.linear(duration: dwell)) { drained = true } }
    }
}

/// Hugs its content like `fixedSize`, but wraps it past `cap` instead of growing.
struct NXWidthCap: Layout {
    let cap: CGFloat
    init(_ cap: CGFloat) { self.cap = cap }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: min(proposal.width ?? cap, cap), height: nil)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// Where the bottom bars rise from.
struct NXBottomBars: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style

    var body: some View {
        let workbench = env.workbench
        // Like its count, the bar goes by the selected rows on screen.
        let hasSelection = !NXSelectionBar.selected(workbench).isEmpty
        ZStack {
            if hasSelection && !env.navigator.isCommandPaletteOpen {
                NXSelectionBar().transition(style.slide(Self.barTransition))
            } else if let tray = workbench.tray, !hasSelection {
                NXTray(message: tray).transition(style.slide(Self.barTransition))
            }
        }
        // The design's barIn, at its own speed whatever the Motion setting.
        .animation(NX.ease(220), value: hasSelection)
        .animation(NX.ease(200), value: workbench.tray == nil)
        .padding(.bottom, 26)
        // The tray rises and drains away without a sound, so VoiceOver hears
        // each message, even one a selection bar keeps off screen.
        .onChange(of: workbench.tray?.id) {
            guard let tray = workbench.tray, NSApp.isActive else { return }
            let undo = tray.undoable && workbench.canUndo ? ". Undo with Command-Z" : ""
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: tray.text + undo, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    static let barTransition = AnyTransition.asymmetric(
        insertion: .offset(y: 10).combined(with: .scale(scale: 0.97)).combined(with: .opacity),
        removal: .opacity)
}
