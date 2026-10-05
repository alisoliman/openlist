//
//  OLDock.swift
//  OpenlistiOS
//

import SwiftUI

// MARK: - C20 Dock

/// The floating dock: Today, Inbox, Lists and Work in a 64 pt capsule, and the
/// accent + beside it (`.dock`, `.tabbar`, `.fab`), in Liquid Glass. Icons
/// only; VoiceOver reads each as a tab ("Inbox, 6 to triage") and the + as
/// "New task", or "New task in Weekend in Kyoto" on that list's page.
struct OLDock: View {
    @Binding var tab: PhoneTab
    var inboxCount: Int
    var captureLabel = "New task"
    /// Tapping the tab on show: back to its root.
    var reselect: (PhoneTab) -> Void = { _ in }
    var captureByVoice: (() -> Void)?
    let capture: () -> Void
    @Namespace private var namespace
    @Environment(\.olStyle) private var style
    @State private var capturePressed = false

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                tabBar
                captureButton
            }
        }
        .padding(.horizontal, OLMetrics.gutter)
        .olFeedback(.selection, trigger: tab)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PhoneTab.allCases) { item in
                tabButton(item)
            }
        }
        .padding(6)
        .frame(height: OLMetrics.dockHeight)
        .glassEffect(.regular.tint(OL.surface.opacity(0.55)), in: .capsule)
        .olGlassShadow(.float, in: Capsule(), fill: OL.surface)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        .accessibilityLabel("Tabs")
    }

    private func tabButton(_ item: PhoneTab) -> some View {
        let isOn = tab == item
        let showsBadge = item == .inbox && inboxCount > 0
        return Button {
            if isOn { reselect(item) } else {
                withAnimation(style.animation(.snappy(duration: 0.28))) { tab = item }
            }
        } label: {
            // 19 pt draws the symbols at about the design's 24 pt icon box
            // (a 20 pt sun, an 18 pt grid, 1.8 pt strokes).
            Image(systemName: item.symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(isOn ? OL.accentText : OL.muted)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background {
                    if isOn {
                        Capsule(style: .continuous)
                            .fill(OL.accentSoft)
                            .matchedGeometryEffect(id: "tab", in: namespace)
                    }
                }
                .overlay(alignment: .top) {
                    if showsBadge { badge }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(OLPressStyle(scale: 0.96))
        .accessibilityElement(children: .ignore)
        // The design's labels: the count on the other tabs' dock, where the
        // Inbox's own screen doesn't say it.
        .accessibilityLabel(showsBadge && !isOn ? "Inbox, \(inboxCount) to triage" : item.title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("dock.\(item.rawValue)")
        // The dock keeps its size at every text size; a long press shows the
        // tab large, as the system tab bar does.
        .accessibilityShowsLargeContentViewer {
            Label(showsBadge ? "Inbox, \(inboxCount)" : item.title, systemImage: item.symbol)
        }
    }

    /// `.badge`: 7 pt from the tab's top, its left edge 5 pt right of centre.
    /// The halves split the tab, so the badge grows rightward from there.
    private var badge: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(height: 0)
            Text(inboxCount > 99 ? "99+" : "\(inboxCount)")
                .font(OLFont.badge)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .foregroundStyle(OL.onInfo)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(OL.info, in: .capsule)
                .fixedSize()
                .contentTransition(.numericText())
                .padding(.leading, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 7)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var captureButton: some View {
        ZStack {
            // The design's 26 pt plus at a 2.2 stroke draws 16 pt across.
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(OL.onAccent)
                .frame(width: OLMetrics.dockHeight, height: OLMetrics.dockHeight)
                .contentShape(.circle)
                .accessibilityHidden(true)
            OLCaptureButton(label: captureLabel, isPressed: $capturePressed, sayTasks: captureByVoice, typeTask: capture)
        }
        .frame(width: OLMetrics.dockHeight, height: OLMetrics.dockHeight)
        .glassEffect(.regular.tint(OL.accent).interactive(), in: .circle)
        .olGlassShadow(.fab, in: Circle(), fill: OL.accent)
        .scaleEffect(capturePressed && !style.reduceMotion ? 0.96 : 1)
        .opacity(capturePressed ? 0.9 : 1)
        .animation(style.animation(.easeOut(duration: 0.12)), value: capturePressed)
    }
}

// MARK: - C21 Bottom action docks

/// A screen's own row of actions where the dock would be: Task detail's
/// Trash and Start working, Triage's buttons, Working's controls. 20 pt
/// gutters, just above the home indicator.
struct OLActionDock<Content: View>: View {
    /// In the dock's place, 28 pt above the screen's edge (Task detail's);
    /// otherwise just above the home indicator (Triage's, Working's).
    var dropsLikeTheDock = false
    @ViewBuilder var content: Content
    @Environment(\.olDockDrop) private var dockDrop

    init(dropsLikeTheDock: Bool = false, @ViewBuilder content: () -> Content) {
        self.dropsLikeTheDock = dropsLikeTheDock
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.horizontal, OLMetrics.gutter)
            .padding(.bottom, dropsLikeTheDock ? 0 : 8)
            .offset(y: dropsLikeTheDock ? dockDrop : 0)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - C22 Bulk bar

/// Select's actions in the dock's place: a 64 pt `ink` capsule with five
/// 22 pt icons, light in dark mode as the design's ink surfaces are.
struct OLBulkBar: View {
    struct Action: Identifiable {
        let symbol: String
        let label: String
        var isEnabled = true
        let perform: () -> Void
        var id: String { label }
    }

    let actions: [Action]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                Button(action: action.perform) {
                    Image(systemName: action.symbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(OL.canvas)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(.rect)
                }
                .buttonStyle(OLPressStyle())
                .disabled(!action.isEnabled)
                .opacity(action.isEnabled ? 1 : 0.4)
                .accessibilityLabel(action.label)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: OLMetrics.dockHeight)
        .background { Capsule(style: .continuous).fill(OL.ink).olShadow(.float) }
        .padding(.horizontal, OLMetrics.gutter)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions for selected tasks")
    }
}

// MARK: - C23 Sheet chrome

/// The capture sheet's top: Cancel and a primary button under the grabber
/// the system draws. Present with `.olSheet()`.
struct OLSheetHeader: View {
    var cancelTitle = "Cancel"
    let confirmTitle: String
    var canConfirm = true
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        HStack {
            Button(cancelTitle, action: cancel).buttonStyle(.olLink())
            Spacer()
            Button(confirmTitle, action: confirm)
                .buttonStyle(.ol(.primary, size: .small))
                .disabled(!canConfirm)
                // Back in to the gutter the Cancel link reaches out of.
                .padding(.trailing, 10)
        }
        .padding(.horizontal, -10)
        .padding(.top, 6)
    }
}

extension View {
    /// The design's sheet: `surface`, 28 pt corners, the grabber.
    func olSheet() -> some View {
        presentationBackground(OL.surface)
            .presentationCornerRadius(28)
            .presentationDragIndicator(.visible)
    }
}

// MARK: - C24 Tray

/// The tray (`.tray`): an `ink` card, 18 pt corners, a message, its Undo, and
/// a 2 pt bar draining over the message's time, coloured by what happened.
struct OLTrayView: View {
    let message: TrayMessage
    let action: () -> Void
    var dismiss: () -> Void = {}
    /// Whether VoiceOver hears it: only the tray in front of everything speaks.
    var announces = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.olStyle) private var style
    @State private var drained = false

    var body: some View {
        // The message and its button, as the design's tray: no glyph; the
        // drain's colour says what kind of thing happened.
        HStack(spacing: 12) {
            Text(message.text)
                .font(OLFont.note)
                .foregroundStyle(OL.canvas)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let title = message.actionTitle {
                Button(action: action) {
                    Text(title)
                        .font(OLFont.buttonSmall)
                        .foregroundStyle(OL.canvas)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(scheme == .dark ? Color.black.opacity(0.08) : Color.white.opacity(0.14), in: .capsule)
                        // A 44 pt target around the 36 pt capsule.
                        .padding(.vertical, 4)
                        .contentShape(.rect)
                }
                .buttonStyle(OLPressStyle())
                .padding(.vertical, -4)
                .accessibilityIdentifier("tray.action")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(OL.ink)
        .overlay(alignment: .bottomLeading) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(drainColor)
                    .frame(width: proxy.size.width * remaining, height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(OL.ink).olShadow(.float) }
        .gesture(DragGesture(minimumDistance: 12).onEnded { value in
            if value.translation.height > 20 { dismiss() }
        })
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("tray")
        .onAppear {
            if announces { AccessibilityNotification.Announcement(message.text).post() }
            let left = max(0, message.seconds - Date.now.timeIntervalSince(message.shownAt))
            withAnimation(.linear(duration: left)) { drained = true }
        }
    }

    private var remaining: CGFloat {
        guard !drained else { return 0 }
        let elapsed = Date.now.timeIntervalSince(message.shownAt)
        return CGFloat(max(0, 1 - elapsed / max(0.1, message.seconds)))
    }

    private var drainColor: Color {
        switch message.tone {
        case .success: OL.success
        case .danger: OL.danger
        case .warning: OL.today
        case .accent: OL.accent
        case .neutral: OL.muted
        }
    }
}
