//
//  NextToolbar.swift
//  openlist
//

import SwiftUI

/// The 52pt bar over the main pane: back, crumb, undo, Actions and New task,
/// with the work notch hanging from its top edge. It also presents the Work
/// panel, whatever opens it: the notch, the Work menu or a notification.
struct NextToolbar: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let crumb: String
    /// Widths of the back-and-crumb and button groups, which the notch keeps clear of.
    @State private var leadingWidth: CGFloat = 0
    @State private var trailingWidth: CGFloat = 0

    private var workbench: Workbench { env.workbench }

    var body: some View {
        @Bindable var calendar = env.calendar
        let working = workbench.workTask != nil
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Button { env.navigator.goBack(); workbench.focusID = nil; workbench.selection = [] } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        .frame(width: 17, height: 17)
                }
                .buttonStyle(NXHoverButtonStyle(hover: env.navigator.canGoBack ? NX.ink(0.06) : .clear, radius: 6,
                                                padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3),
                                                foreground: env.navigator.canGoBack ? NX.ink(0.6) : NX.ink(0.2)))
                .disabled(!env.navigator.canGoBack)
                .help("Back (⌘[)")

                // While you work the crumb gives the notch its room past 200 pt.
                NXWidthCap(working ? 200 : .infinity) {
                    Text(crumb)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NX.ink(0.4))
                        .lineLimit(1)
                }
                .padding(.leading, 4)
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { leadingWidth = $0 }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if let undo = workbench.undoLabel {
                    toolButton(icon: "arrow.uturn.backward", help: "Undo \(undo) (⌘Z)") {
                        if !working {
                            // Hug the label; truncate only past 180 pt.
                            Text(undo).font(.system(size: 11.5, weight: .medium)).lineLimit(1).frame(maxWidth: 180).fixedSize()
                        }
                    } action: { workbench.undoLast() }
                    .transition(.opacity)
                }
                toolButton(icon: "bolt", help: "Actions (⌘K)") {
                    if !working {
                        Text("Actions").font(.system(size: 11.5, weight: .medium))
                        NXKey("⌘K", opacity: 0.6)
                    }
                } action: { env.navigator.isCommandPaletteOpen.toggle() }

                Button { workbench.openCapture() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        if !working {
                            Text("New task").font(.system(size: 11.5, weight: .semibold))
                            NXKey("N", opacity: 0.65)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(style.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: style.accent.opacity(0.4), radius: 1, y: 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New task (N)")
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { trailingWidth = $0 }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background {
            Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())
        }
        .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }
        .overlay(alignment: .top) {
            // Centred, but never over the crumb or the buttons.
            NXNotchPlacement(leading: 18 + leadingWidth + 8, trailing: 18 + trailingWidth + 8) {
                if working { NXWorkNotch().transition(.move(edge: .top)) }
            }
        }
        .popover(isPresented: $calendar.isWorkPanelPresented, attachmentAnchor: .point(.bottom), arrowEdge: .bottom) {
            WorkPopover().environment(env).environment(\.nextStyle, style)
        }
        .onChange(of: recordingAnnouncement) { _, announcement in
            guard let announcement else { return }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        .animation(style.ease(420), value: working)
        .animation(.easeOut(duration: 0.2), value: workbench.undoLabel)
        .zIndex(40)
    }

    /// Only meaningful transitions announce; timer ticks and suggestions do not.
    private var recordingAnnouncement: String? {
        let calendar = env.calendar
        if let notice = calendar.notice { return notice }
        if let conflict = calendar.workConflict, let session = calendar.activeSession, session.occurrenceID == conflict.occurrenceID {
            return "Still recording. \(session.title) is running into \(workbench.conflictLabel(conflict, inSentence: true))."
        }
        if let session = calendar.activeSession { return "Recording work on \(session.title)." }
        if let summary = calendar.workCompletion { return "Completed \(summary.title). Recording stopped." }
        if let task = calendar.resumableTask { return "Recording stopped for \(task.displayTitle). The task is still open." }
        return nil
    }

    private func toolButton<Label: View>(icon: String, help: String, @ViewBuilder label: () -> Label,
                                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12.5, weight: .medium))
                label()
            }
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 8,
                                        padding: EdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9)))
        .help(help)
    }
}

/// The white tab that drops from the toolbar while you work. Its title opens
/// the Work panel.
struct NXWorkNotch: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @FocusState private var triggerFocused: Bool
    /// Whether the open Work panel came from this notch rather than a menu.
    @State private var openedHere = false

    var body: some View {
        let workbench = env.workbench
        if let task = workbench.workTask {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let paused = workbench.isWorkPaused
                let elapsed = workbench.workElapsed(at: context.date)
                let estimate = Double(max(5, task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes
                                                                                  : env.workbench.defaultEstimate)) * 60
                let over = elapsed > estimate
                // The whole notch while the bar has room for it and a few words
                // of the title; then just the timer and Stop; then nothing,
                // rather than covering the crumb or the buttons.
                ViewThatFits(in: .horizontal) {
                    NXNotchIdeal(titleRoom: 60) {
                        // Hugs its content up to 440 pt, and narrows (the title truncating) when the bar has less room.
                        NXWidthCap(440) {
                            HStack(spacing: 10) {
                                panelButton(task, paused: paused, elapsed: elapsed, estimate: estimate, over: over, compact: false)
                                // What the work ran into, in red, takes the place of the time it was given, in amber.
                                if let conflict = env.calendar.workConflict, conflict.occurrenceID == task.occurrenceID {
                                    let sentence = workbench.conflictLabel(conflict, inSentence: true)
                                    extensionChip(workbench.conflictLabel(conflict), color: NX.redText, fill: NX.red.opacity(0.12))
                                        .help("Still recording. Running into \(sentence)")
                                        .accessibilityLabel("Running into \(sentence)")
                                } else if let extended = env.calendar.workExtension, extended.occurrenceID == task.occurrenceID {
                                    extensionChip("+\(extended.minutes)m", color: NX.amberText, fill: NX.amber.opacity(0.16))
                                        .help("Extended by \(extended.minutes) min")
                                        .accessibilityLabel("Extended by \(extended.minutes) minutes")
                                }
                                controls {
                                    notchButton(paused ? "play.fill" : "pause.fill", help: paused ? "Resume" : "Pause",
                                                color: NX.ink(0.6), hover: NX.ink(0.06)) { workbench.toggleWorkPause() }
                                    notchButton("checkmark", help: "Done", color: NX.green, hover: NX.green.opacity(0.12), weight: .bold) {
                                        workbench.finishWork()
                                    }
                                    notchButton("xmark", help: "Stop", color: NX.ink(0.42), hover: NX.ink(0.06)) { workbench.stopWork() }
                                }
                            }
                            .padding(.leading, 14)
                            .padding(.trailing, 5)
                            .frame(height: 38)
                        }
                        .modifier(NXNotchChrome(progress: elapsed / estimate, over: over))
                    }
                    // The Work panel it opens has pause, Done and the plan.
                    HStack(spacing: 10) {
                        panelButton(task, paused: paused, elapsed: elapsed, estimate: estimate, over: over, compact: true)
                        controls {
                            notchButton("xmark", help: "Stop", color: NX.ink(0.42), hover: NX.ink(0.06)) { workbench.stopWork() }
                        }
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 5)
                    .frame(height: 38)
                    .modifier(NXNotchChrome(progress: elapsed / estimate, over: over))
                    Color.clear.frame(width: 0, height: 0)
                }
            }
            // A panel opened here hands focus back to the notch.
            .onChange(of: env.calendar.isWorkPanelPresented) { wasOpen, isOpen in
                guard wasOpen && !isOpen else { return }
                if openedHere { triggerFocused = true }
                openedHere = false
            }
        }
    }

    /// The dot, title and timer, which open the Work panel. Compact, it keeps
    /// only the dot and the timer.
    private func panelButton(_ task: Block, paused: Bool, elapsed: Double, estimate: Double, over: Bool,
                             compact: Bool) -> some View {
        Button(action: toggleWorkPanel) {
            HStack(spacing: 10) {
                NXBreathingDot(color: paused ? NX.amber : style.accent, active: !paused)
                if !compact {
                    Text(task.displayTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(NX.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(NXFormat.mmss(elapsed))
                    .font(NX.mono(12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(over ? NX.amberText : style.accent)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($triggerFocused)
        .help("Show work — pause, review or change the plan")
        .accessibilityLabel("\(paused ? "Paused" : "Working") on \(task.displayTitle). Show work details.")
        .accessibilityValue("\(NXFormat.mmss(elapsed)) of \(Int(estimate / 60)) minutes")
    }

    /// The icon buttons after a hairline.
    private func controls<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 1) { content() }
            .padding(.leading, 5)
            .overlay(alignment: .leading) { Rectangle().fill(NX.ink(0.1)).frame(width: 0.5, height: 22) }
    }

    private func toggleWorkPanel() {
        if env.calendar.isWorkPanelPresented {
            env.calendar.isWorkPanelPresented = false
        } else {
            openedHere = true
            env.calendar.showWork()
        }
    }

    /// The chip after the timer: the minutes the work was given, or what it ran into.
    private func extensionChip(_ label: String, color: Color, fill: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize()
            .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private func notchButton(_ icon: String, help: String, color: Color, hover: Color, weight: Font.Weight = .semibold,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12.5, weight: weight)).frame(width: 28, height: 28)
        }
        .buttonStyle(NXHoverButtonStyle(hover: hover, radius: 8, padding: EdgeInsets(), foreground: color,
                                        hoverForeground: color == NX.green ? NX.green : NX.ink))
        .help(help)
    }
}

/// Centres the notch on the bar, but slides it clear of `leading` and
/// `trailing` and narrows it to the room between them.
private struct NXNotchPlacement: Layout {
    let leading: CGFloat
    let trailing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let room = max(0, bounds.width - leading - trailing)
        for notch in subviews {
            let size = notch.sizeThatFits(ProposedViewSize(width: room, height: nil))
            let width = min(size.width, room)
            let x = min(max(bounds.midX - width / 2, bounds.minX + leading), bounds.maxX - trailing - width)
            notch.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: size.height))
        }
    }
}

/// The notch's card, progress line, rounded bottom and shadow.
private struct NXNotchChrome: ViewModifier {
    @Environment(\.nextStyle) private var style
    let progress: Double
    let over: Bool

    func body(content: Content) -> some View {
        content
            .background(NX.card)
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NX.ink(0.06))
                        Capsule().fill(over ? NX.amber : style.accent)
                            .frame(width: geo.size.width * min(1, progress))
                            .animation(.linear(duration: 0.9), value: progress)
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 14)
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15, style: .continuous))
            .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15, style: .continuous)
                .strokeBorder(NX.ink(0.12), lineWidth: 0.5))
            .shadow(color: NX.shadowWarm.opacity(0.12), radius: 13, y: 10)
    }
}

/// Reports an ideal width of at most `titleRoom` past the content's narrowest,
/// so `ViewThatFits` keeps the full notch while its title can show a few
/// words, not only while the whole title fits. Proposed a width, it passes
/// it on unchanged.
private struct NXNotchIdeal: Layout {
    let titleRoom: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(proposal)
        guard proposal.width == nil else { return size }
        let least = content.sizeThatFits(ProposedViewSize(width: 0, height: proposal.height))
        return CGSize(width: min(size.width, least.width + titleRoom), height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
