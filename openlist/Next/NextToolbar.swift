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
    @Environment(\.nxTrafficLightsInset) private var trafficLightsInset
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
                // No hover fill, as the design's: only its colour says whether it can go back.
                .buttonStyle(NXHoverButtonStyle(hover: .clear, radius: 6,
                                                padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3),
                                                foreground: env.navigator.canGoBack ? NX.ink(0.6) : NX.ink(0.2)))
                .disabled(!env.navigator.canGoBack)
                .help("Back (⌘[)")
                .accessibilityLabel("Back")

                // While you work the crumb gives the notch its room past 200 pt.
                // Its first 80 pt outlast the Undo label.
                NXWidthFloor(80) {
                    NXWidthCap(working ? 200 : .infinity) {
                        Text(crumb)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NX.ink(0.4))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 4)
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { leadingWidth = $0 }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if let undo = workbench.undoLabel {
                    // A narrow bar truncates the label, then drops it, before
                    // Actions and New task give up anything.
                    ViewThatFits(in: .horizontal) {
                        NXNotchIdeal(titleRoom: 60) { undoButton(undo, labelled: !working) }
                        undoButton(undo, labelled: false)
                    }
                    .transition(.opacity)
                }
                toolButton(icon: "bolt", help: "Actions (⌘K)") {
                    if !working {
                        Text("Actions").font(.system(size: 11.5, weight: .medium))
                        NXKey("⌘K", opacity: 0.6)
                    }
                } action: { env.navigator.isCommandPaletteOpen.toggle() }
                .fixedSize()
                .accessibilityLabel("Actions")

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
                .fixedSize()
                .help("New task (N)")
                .accessibilityLabel("New task")
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { trailingWidth = $0 }
            // The buttons keep their room; the crumb truncates first, down to its floor.
            .layoutPriority(1)
        }
        .padding(.leading, 18 + trafficLightsInset)
        .padding(.trailing, 18)
        .frame(height: 52)
        .background {
            Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())
        }
        .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }
        .overlay(alignment: .top) {
            // Centred, but never over the crumb or the buttons.
            NXNotchPlacement(leading: 18 + trafficLightsInset + leadingWidth + 8, trailing: 18 + trailingWidth + 8) {
                if working { NXWorkNotch().transition(style.slide(.move(edge: .top))) }
            }
        }
        .popover(isPresented: $calendar.isWorkPanelPresented, attachmentAnchor: .point(.bottom), arrowEdge: .bottom) {
            WorkPopover().environment(env).environment(\.nextStyle, style)
        }
        // Asked for as the window opened, as Work ▸ Show Work does with it
        // closed, the panel shows once the bar it hangs from is up. Any other
        // ask with no window to show it in, as a notification's Start makes,
        // has lapsed: the window doesn't open onto it hours later.
        .onAppear {
            let asked = env.showsWorkPanelOnOpen
            env.showsWorkPanelOnOpen = false
            guard calendar.isWorkPanelPresented else { return }
            calendar.isWorkPanelPresented = false
            if asked { DispatchQueue.main.async { calendar.isWorkPanelPresented = true } }
        }
        .onChange(of: recordingAnnouncement) { _, announcement in
            guard let announcement else { return }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        // The design's notchDrop plays at its own speed whatever the Motion setting.
        .animation(NX.ease(420), value: working)
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
        if let task = calendar.resumableTask { return "Paused \(task.displayTitle). No time is being recorded." }
        return nil
    }

    /// Undo, named after the latest change when `labelled`: the name hugs its
    /// text up to 180 pt and truncates past that, or where the bar is short.
    private func undoButton(_ undo: String, labelled: Bool) -> some View {
        toolButton(icon: "arrow.uturn.backward", help: "Undo \(undo) (⌘Z)") {
            if labelled {
                NXWidthCap(180) { Text(undo).font(.system(size: 11.5, weight: .medium)).lineLimit(1) }
            }
        } action: { workbench.undoLast() }
        .accessibilityLabel("Undo \(undo)")
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
                // of the title; then, as the design's title shrinks to nothing,
                // the notch without it, then without its chip too; then
                // nothing, rather than covering the crumb or the buttons.
                // Pause or Resume, Done and Stop stay while it shows.
                ViewThatFits(in: .horizontal) {
                    NXNotchIdeal(titleRoom: 60) {
                        // Hugs its content up to 440 pt, and narrows (the title truncating) when the bar has less room.
                        NXWidthCap(440) {
                            HStack(spacing: 10) {
                                panelButton(task, paused: paused, elapsed: elapsed, estimate: estimate, over: over, compact: false)
                                chip(task, paused: paused)
                                controls(paused: paused)
                            }
                            .padding(.leading, 14)
                            .padding(.trailing, 5)
                            .frame(height: 38)
                        }
                        .modifier(NXNotchChrome(progress: elapsed / estimate, over: over))
                    }
                    compactNotch(task, paused: paused, elapsed: elapsed, estimate: estimate, over: over, chipped: true)
                    compactNotch(task, paused: paused, elapsed: elapsed, estimate: estimate, over: over, chipped: false)
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

    /// The notch without its title, and without its chip unless `chipped`.
    private func compactNotch(_ task: Block, paused: Bool, elapsed: Double, estimate: Double, over: Bool,
                              chipped: Bool) -> some View {
        HStack(spacing: 10) {
            panelButton(task, paused: paused, elapsed: elapsed, estimate: estimate, over: over, compact: true)
            if chipped { chip(task, paused: paused) }
            controls(paused: paused)
        }
        .padding(.leading, 14)
        .padding(.trailing, 5)
        .frame(height: 38)
        .modifier(NXNotchChrome(progress: elapsed / estimate, over: over))
    }

    /// What the work ran into, in red, in place of the time it was given, in
    /// amber. Paused, the notch reads as the work did when it paused, as its block does.
    @ViewBuilder
    private func chip(_ task: Block, paused: Bool) -> some View {
        let workbench = env.workbench
        if let conflict = env.calendar.displayedWorkConflict, conflict.occurrenceID == task.occurrenceID {
            let sentence = workbench.conflictLabel(conflict, inSentence: true)
            extensionChip(workbench.conflictLabel(conflict), color: NX.redText, fill: NX.red.opacity(0.12))
                .help(paused ? "Ran into \(sentence)" : "Still recording. Running into \(sentence)")
                .accessibilityLabel((paused ? "Ran into " : "Running into ") + sentence)
        } else if let extended = env.calendar.displayedWorkExtension, extended.occurrenceID == task.occurrenceID {
            extensionChip("+\(extended.minutes)m", color: NX.amberText, fill: NX.amber.opacity(0.16))
                .help("Extended by \(extended.minutes) min")
                .accessibilityLabel("Extended by \(extended.minutes) minutes")
        }
    }

    /// Pause or Resume, Done and Stop, after a hairline.
    private func controls(paused: Bool) -> some View {
        let workbench = env.workbench
        return HStack(spacing: 1) {
            notchButton(paused ? "play.fill" : "pause.fill", help: paused ? "Resume" : "Pause",
                        color: NX.ink(0.6), hover: NX.ink(0.06)) { workbench.toggleWorkPause() }
            notchButton("checkmark", help: "Done", color: NX.green, hover: NX.green.opacity(0.12), weight: .bold) {
                workbench.finishWork()
            }
            notchButton("xmark", help: "Stop", color: NX.ink(0.42), hover: NX.ink(0.06)) { workbench.stopWork() }
        }
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
        // Named as the design's titles name them, not by the symbol.
        .accessibilityLabel(help)
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

/// Keeps at least `floor` of the content's width, or all of it when narrower,
/// however little the bar offers, so the crumb shows a word or two before the
/// Undo label, which outranks it, keeps its room.
private struct NXWidthFloor: Layout {
    let floor: CGFloat
    init(_ floor: CGFloat) { self.floor = floor }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let ideal = content.sizeThatFits(.unspecified).width
        let width = max(proposal.width ?? ideal, min(ideal, floor))
        return content.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// Reports an ideal width of at most `titleRoom` past the content's narrowest,
/// so `ViewThatFits` keeps the full notch, or the named Undo, while its title
/// can show a few words, not only while the whole title fits. Proposed a
/// width, it passes it on unchanged.
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
