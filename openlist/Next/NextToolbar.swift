//
//  NextToolbar.swift
//  openlist
//

import SwiftUI

/// The 52pt bar over the main pane: back, crumb, undo, Actions and New task,
/// with the work notch hanging from its top edge.
struct NextToolbar: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let crumb: String

    private var workbench: Workbench { env.workbench }

    var body: some View {
        let working = workbench.workTask != nil
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

            Text(crumb)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NX.ink(0.4))
                .lineLimit(1)
                .padding(.leading, 4)

            Spacer(minLength: 8)

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
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background {
            Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())
        }
        .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }
        .overlay(alignment: .top) {
            if working { NXWorkNotch().transition(.move(edge: .top)) }
        }
        .animation(style.ease(420), value: working)
        .animation(.easeOut(duration: 0.2), value: workbench.undoLabel)
        .zIndex(40)
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

/// The white tab that drops from the toolbar while you work.
struct NXWorkNotch: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style

    var body: some View {
        let workbench = env.workbench
        if let task = workbench.workTask {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let paused = workbench.isWorkPaused
                let elapsed = workbench.workElapsed(at: context.date)
                let estimate = Double(max(5, task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes
                                                                                  : env.workbench.defaultEstimate)) * 60
                let over = elapsed > estimate
                HStack(spacing: 10) {
                    NXBreathingDot(color: paused ? NX.amber : style.accent, active: !paused)
                    Text(task.displayTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(NX.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(NXFormat.mmss(elapsed))
                        .font(NX.mono(12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(over ? NX.amberText : style.accent)
                        .fixedSize()
                    Text("of \(Int(estimate / 60)) min")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NX.ink(0.4))
                        .fixedSize()
                    if let nudge = env.calendar.overrunNudge, nudge.taskID == task.id {
                        extensionChip(nudge)
                    }
                    HStack(spacing: 1) {
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
                .padding(.leading, 14)
                .padding(.trailing, 5)
                .frame(height: 38)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: true, vertical: false)
                .background(NX.card)
                .overlay(alignment: .bottom) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(NX.ink(0.06))
                            Capsule().fill(over ? NX.amber : style.accent)
                                .frame(width: geo.size.width * min(1, elapsed / estimate))
                                .animation(.linear(duration: 0.9), value: elapsed)
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
    }

    @ViewBuilder
    private func extensionChip(_ nudge: CalendarOverrunNudge) -> some View {
        let minutes = max(1, Int(nudge.proposedEnd.timeIntervalSince(nudge.estimatedEnd) / 60))
        let conflict = nudge.needsConfirmation && nudge.movedTaskCount > 0
        Button { env.calendar.acceptMoreTime() } label: {
            Text(conflict ? "+\(minutes)m · moves \(nudge.movedTaskCount)" : "+\(minutes)m")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(conflict ? NX.redText : NX.amberText)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(conflict ? NX.red.opacity(0.12) : NX.amber.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .help("Give this task more time")
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
