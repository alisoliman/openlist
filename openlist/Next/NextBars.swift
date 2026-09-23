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
        .background(NX.inverse, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: Color(hex: 0x17161A).opacity(0.36), radius: 20, y: 16)
        .environment(\.colorScheme, .dark)
    }

    private func bar(_ fit: Fit) -> some View {
        let workbench = env.workbench
        let ids = workbench.targetIDs
        return HStack(spacing: 2) {
            Text("\(workbench.selection.count)")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 22, minHeight: 22)
                .padding(.horizontal, workbench.selection.count > 9 ? 6 : 0)
                .background(style.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(.trailing, fit == .icons ? 4 : 0)
                .accessibilityLabel("\(workbench.selection.count) selected")
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
            barButton("Tomorrow", icon: "sunset", key: "M", tint: Color(hex: 0xC9AEFF), fit: fit) { workbench.schedule(ids, offset: 1) }
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

/// The Store's completion Undo for tasks completed outside Next's rows: the
/// menu bar, calendar, notifications and MCP. Completions made here already
/// report in the tray, so their Store action stays quiet.
struct NXOutsideCompletionFeedback: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style

    var body: some View {
        let workbench = env.workbench
        if workbench.tray == nil, workbench.selection.isEmpty, let action = env.store.completionUndo, !isReported(action) {
            CalendarCompletionFeedback()
        }
    }

    /// Whether the change log already holds this completion or reopen of the
    /// same tasks. Next writes a completion once its dwell ends, so the Store's
    /// action arrives up to the dwell (plus the row stagger) after its entry.
    private func isReported(_ action: CompletionUndoAction) -> Bool {
        guard let change = env.store.completionUndoChanges[action.id] else { return false }
        let roots = Set([change.rootTaskID] + change.additionalRootTaskIDs)
        let window = style.dwell + 5 + Double(roots.count) * style.ms(75) / 1000
        let since = action.createdAt.addingTimeInterval(-window)
        // Newest first, so only the recent entries are read.
        return env.workbench.log.lazy.prefix { $0.at >= since }.contains { entry in
            guard let id = entry.taskID, roots.contains(id) else { return false }
            return action.isReopening ? entry.icon == "arrow.uturn.backward" : entry.tone == .green
        }
    }
}

/// The short-lived confirmation with Undo and an optional destination link.
struct NXTray: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let message: TrayMessage
    @State private var drained = false

    var body: some View {
        let workbench = env.workbench
        let tint = Self.tint(message.tone)
        HStack(spacing: 10) {
            Image(systemName: message.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            NXWidthCap(460) {
                Text(message.text)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
            }
            if let destination = message.destination, destination.route != env.navigator.route {
                Button(destination.label) {
                    workbench.go(destination.route)
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
        .frame(minHeight: 40)
        .background(NX.inverse)
        .overlay(alignment: .bottomLeading) {
            GeometryReader { geo in
                Rectangle().fill(tint)
                    .frame(width: geo.size.width, height: 2)
                    .scaleEffect(x: drained ? 0 : 1, y: 1, anchor: .leading)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .shadow(color: Color(hex: 0x17161A).opacity(0.34), radius: 17, y: 14)
        .environment(\.colorScheme, .dark)
        .onAppear { drain() }
        .onChange(of: message.id) { _, _ in drain() }
    }

    private func drain() {
        drained = false
        withAnimation(.linear(duration: style.dwell)) { drained = true }
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
        ZStack {
            if !workbench.selection.isEmpty && !env.navigator.isCommandPaletteOpen {
                NXSelectionBar().transition(Self.barTransition)
            } else if let tray = workbench.tray, workbench.selection.isEmpty {
                NXTray(message: tray).id(tray.id).transition(Self.barTransition)
            }
        }
        .animation(style.ease(220), value: workbench.selection.isEmpty)
        .animation(style.ease(200), value: workbench.tray?.id)
        .padding(.bottom, 26)
    }

    static let barTransition = AnyTransition.asymmetric(
        insertion: .offset(y: 10).combined(with: .scale(scale: 0.97)).combined(with: .opacity),
        removal: .opacity)
}
