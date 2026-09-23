//
//  NextRow.swift
//  openlist
//

import SwiftUI

/// How a screen wants its rows drawn.
struct NXRowOptions {
    /// Show the list chip, except for tasks in `listID`.
    var showList = true
    var listID: UUID?
    var notes = false
    /// Tasks screen: text-only chips, the open icon hidden until focus.
    var quiet = false
    /// Outline depth for subtasks on a list screen.
    var depths: [UUID: Int] = [:]
}

/// A task row: rail, checkbox, text with strike, chips, selection mark and open icon.
struct NextTaskRow: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let task: Block
    var options = NXRowOptions()
    @State private var hovering = false

    private var workbench: Workbench { env.workbench }

    var body: some View {
        let id = task.id
        let closing = workbench.closing[id]
        let flying = workbench.flying.contains(id)
        let focused = workbench.focusID == id || env.navigator.openTaskID == id
        let selected = workbench.selection.contains(id)
        let fresh = workbench.fresh.contains(id)
        let restored = workbench.restored.contains(id)
        let chipFresh = workbench.freshChip.contains(id) || fresh

        HStack(alignment: .top, spacing: 0) {
            if let depth = options.depths[id], depth > 0 {
                Color.clear.frame(width: CGFloat(depth) * 22, height: 1)
            }
            NXCheckbox(filled: task.isCompleted || closing != nil,
                       closing: closing, priority: task.priority, title: task.displayTitle,
                       ringing: workbench.pulseTaskID == id && closing != nil) {
                workbench.toggle(id)
            }
            .frame(width: 26, alignment: .leading)
            .padding(.top, 2.5)

            VStack(alignment: .leading, spacing: 2) {
                NXStrikeText(text: task.displayTitle,
                             struck: closing ?? task.isCompleted,
                             closing: closing != nil,
                             dimmed: task.isCompleted && closing == nil)
                if options.notes, !task.note.isEmpty {
                    Text(task.note.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 12))
                        .foregroundStyle(NX.ink(0.45))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Narrow rows shed chips from the front (context first, dates and state last)
            // so the title keeps its room.
            let chips = NXRowChips.chips(for: task, options: options, library: library, workbench: workbench)
            ViewThatFits(in: .horizontal) {
                ForEach(0...chips.count, id: \.self) { dropped in
                    accessories(Array(chips.dropFirst(dropped)), fresh: chipFresh, selected: selected, focused: focused)
                }
            }
            .padding(.top, 1)
            .padding(.leading, 8)
        }
        .padding(.vertical, style.rowVerticalPadding)
        .padding(.horizontal, 10)
        .background(alignment: .leading) {
            if closing != nil { NXDrainRail(duration: style.dwell) }
        }
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(background(focused: focused, selected: selected, fresh: fresh, restored: restored))
                .shadow(color: focused ? NX.shadowWarm.opacity(0.09) : .clear, radius: 8, y: 4)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(focused ? style.accent.opacity(0.25) : selected ? style.accent.opacity(0.19) : .clear, lineWidth: 1)
                }
                .animation(style.ease(fresh || restored ? 700 : 180), value: focused)
                .animation(.easeOut(duration: 0.7), value: fresh)
                .animation(.easeOut(duration: 0.7), value: restored)
        }
        .contentShape(Rectangle())
        .opacity(flying ? 0 : closing != nil ? 0.62 : 1)
        .offset(x: flying ? -56 : 0)
        .scaleEffect(flying ? 0.97 : 1)
        .animation(style.standard(280), value: flying)
        .animation(style.ease(280), value: closing)
        .zIndex(focused ? 3 : 0)
        .onHover { hovering = $0 }
        .onTapGesture { workbench.click(id, command: NXModifiers.command, shift: NXModifiers.shift) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { workbench.inspect(id) })
        .contextMenu { NXTaskMenu(ids: workbench.selection.contains(id) ? Array(workbench.selection) : [id]) }
        .draggable(DragPayload.block.encode(id))
        .id(id)
    }

    private func accessories(_ chips: [NXChipModel], fresh: Bool, selected: Bool, focused: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(chips) { chip in
                NXChip(chip: chip, fresh: fresh, quiet: options.quiet)
            }
            if selected {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(style.accent)
                    .frame(width: 16, height: 16)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            Button { workbench.inspect(task.id) } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), radius: 6,
                                            padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3),
                                            foreground: NX.ink(0.45), hoverForeground: NX.ink))
            .opacity(focused ? 1 : hovering ? 0.6 : options.quiet ? 0 : 0.22)
            .help("Open details (↩)")
            .accessibilityLabel("Open details")
        }
    }

    private func background(focused: Bool, selected: Bool, fresh: Bool, restored: Bool) -> Color {
        if focused { return NX.card }
        if selected { return style.accent.opacity(0.08) }
        if fresh { return style.accent.opacity(0.11) }
        if restored { return style.accent.opacity(0.07) }
        return hovering ? NX.ink(0.03) : .clear
    }
}

/// Task text with an animated strike-through line.
struct NXStrikeText: View {
    @Environment(\.nextStyle) private var style
    let text: String
    let struck: Bool
    let closing: Bool
    let dimmed: Bool
    var size: CGFloat = 13.8

    var body: some View {
        Text(text)
            .font(.system(size: size))
            .lineSpacing(size * 0.2)
            .foregroundStyle(dimmed ? NX.ink(0.42) : NX.ink)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    let lineHeight = min(geo.size.height, size * 1.45)
                    Capsule()
                        .fill(closing ? style.accent : NX.ink(0.36))
                        .frame(width: struck ? geo.size.width + 2 : 0, height: 1.5)
                        .offset(y: lineHeight * 0.52 - 0.75)
                        .animation(.timingCurve(0.3, 0.8, 0.2, 1, duration: style.ms(340) / 1000), value: struck)
                }
                .allowsHitTesting(false)
            }
    }
}

/// The round checkbox with its pop, tick and completion ring.
struct NXCheckbox: View {
    @Environment(\.nextStyle) private var style
    let filled: Bool
    let closing: Bool?
    let priority: TaskPriority
    /// Spoken with the action, e.g. "Complete Buy milk".
    var title = ""
    var ringing = false
    var size: CGFloat = 16
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(filled ? (closing != nil ? style.accent : NX.green) : .clear)
                Circle()
                    .strokeBorder(filled ? .clear : (NX.priorityStroke(priority) ?? NX.ink(0.3)), lineWidth: 1.5)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.6, weight: .heavy))
                    .foregroundStyle(.white)
                    .opacity(filled ? 1 : 0)
                    .scaleEffect(filled ? 1 : 0.3)
                    .animation(style.spring(200), value: filled)
                    .accessibilityHidden(true)
                if ringing { NXRing(color: style.accent, size: size) }
            }
            .frame(width: size, height: size)
            .scaleEffect(style.lively && closing == false ? 1.18 : 1)
            .animation(style.spring(240), value: closing)
            .animation(style.ease(200), value: filled)
            .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(.plain)
        // Filled covers the completion dwell too; clicking then cancels it, so it reads as Reopen.
        .accessibilityLabel("\(filled ? "Reopen" : "Complete") \(title.isEmpty ? "task" : title)")
        .accessibilityValue(closing != nil ? "Completing" : filled ? "Completed" : "Open")
        .accessibilityAddTraits(filled ? .isSelected : [])
    }
}

/// The expanding ring when a check lands.
struct NXRing: View {
    @Environment(\.nextStyle) private var style
    let color: Color
    var size: CGFloat = 16
    @State private var grown = false

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 2)
            .frame(width: size, height: size)
            .scaleEffect(grown ? 2.6 : 0.6)
            .opacity(grown ? 0 : 0.9)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: style.ms(640) / 1000)) { grown = true } }
    }
}

/// The accent rail that drains while a finished row waits to settle.
struct NXDrainRail: View {
    @Environment(\.nextStyle) private var style
    let duration: Double
    @State private var drained = false

    var body: some View {
        Capsule()
            .fill(style.accent)
            .frame(width: 2.5)
            .scaleEffect(x: 1, y: drained ? 0 : 1, anchor: .top)
            .padding(.vertical, 5)
            .onAppear { withAnimation(.linear(duration: duration)) { drained = true } }
    }
}

// MARK: - Chips

enum NXRowChips {
    @MainActor
    static func chips(for task: Block, options: NXRowOptions, library: NextLibrary, workbench: Workbench) -> [NXChipModel] {
        var chips: [NXChipModel] = []
        let done = task.isCompleted
        if options.showList, task.listID != options.listID, let list = library.list(task.listID) {
            chips.append(NXChipModel(id: "list", label: "\(list.glyph) \(list.displayTitle)"))
        }
        for id in task.labelIDs {
            if let label = library.label(id) {
                chips.append(NXChipModel(id: "label-\(id)", label: label.name, tone: .label(label.nxColor)))
            }
        }
        if let recurrence = task.recurrence {
            chips.append(NXChipModel(id: "repeat", label: recurrence.displayText, icon: "repeat"))
        }
        if task.includesTime, let due = task.dueDate, !done {
            chips.append(NXChipModel(id: "time", label: NXFormat.clock(due), icon: "bell.fill", fill: true))
        }
        if !done, workbench.isPlanned(task) {
            let minutes = task.schedulingEstimateMinutes
            chips.append(NXChipModel(id: "planned", label: minutes > 0 ? "\(minutes)m" : "Planned",
                                     icon: "calendar.badge.clock", tone: .accent))
        }
        if let due = task.dueDate, !done {
            let overdue = task.isOverdue
            chips.append(NXChipModel(id: "due", label: NXFormat.dueLabel(due),
                                     icon: overdue ? "exclamationmark.circle.fill" : "calendar",
                                     tone: overdue ? .over : NXFormat.dayOffset(due) == 0 ? .accent : .neutral, fill: overdue))
        }
        if task.isStarred {
            chips.append(NXChipModel(id: "star", label: "", icon: "star.fill", tone: .amber, fill: true))
        }
        if done, let at = task.completedAt {
            chips.append(NXChipModel(id: "done", label: NXFormat.relative(at)))
        }
        return chips
    }
}

// MARK: - Groups

/// A titled run of rows on Today, Tasks, a list or a label.
struct NXGroup: Identifiable {
    var id: String
    var title: String = ""
    var icon: String?
    var color: Color = NX.ink(0.45)
    var glyph: TaskList?
    var rows: [Block]
    var showHead = true
    var collapsible = false
    /// Whether the group starts open; collapsing flips it for the session.
    var defaultOpen = true
    var emptyText = ""
    var actionLabel: String?
    var action: (() -> Void)?
}

struct NXGroupView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let group: NXGroup
    var options = NXRowOptions()

    var body: some View {
        let open = isOpen
        VStack(alignment: .leading, spacing: 0) {
            if group.showHead { head(open: open) }
            if open {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(group.rows, id: \.id) { task in
                        NextTaskRow(task: task, options: options)
                            .transition(.asymmetric(
                                insertion: .offset(y: -8).combined(with: .scale(scale: 0.99)).combined(with: .opacity),
                                removal: .opacity))
                    }
                    if group.rows.isEmpty, !group.emptyText.isEmpty {
                        Text(group.emptyText)
                            .font(.system(size: 12.5))
                            .foregroundStyle(NX.ink(0.4))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
        .padding(.top, 16)
    }

    private var isOpen: Bool {
        !group.collapsible || group.defaultOpen != env.workbench.collapsedGroups.contains(group.id)
    }

    private func head(open: Bool) -> some View {
        HStack(spacing: 7) {
            if let glyph = group.glyph {
                NXListGlyph(list: glyph, size: 13)
            } else if let icon = group.icon {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(group.color)
            }
            Text(group.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(NX.ink)
                .lineLimit(1)
                .fixedSize()
            if !group.rows.isEmpty {
                Text("\(group.rows.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NX.ink(0.38))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            if group.collapsible {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NX.ink(0.36))
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            Spacer(minLength: 8)
            if let label = group.actionLabel, let action = group.action {
                Button(label, action: action)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(NXHoverButtonStyle(hover: style.accent.opacity(0.16), radius: 6,
                                                    padding: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8),
                                                    foreground: style.accent))
                    .background(style.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard group.collapsible else { return }
            withAnimation(style.ease(180)) {
                if env.workbench.collapsedGroups.contains(group.id) { env.workbench.collapsedGroups.remove(group.id) }
                else { env.workbench.collapsedGroups.insert(group.id) }
            }
        }
    }
}

/// "Add to …" row that opens capture.
struct NXAddRow: View {
    @Environment(AppEnvironment.self) private var env
    let text: String
    var listID: UUID?
    var forToday = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(NX.ink(0.24), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
                .frame(width: 15, height: 15)
            Text(text).font(.system(size: 13.5))
            Text("N")
                .font(NX.mono(10))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 4))
            Spacer()
        }
        .foregroundStyle(hovering ? NX.ink(0.55) : NX.ink(0.36))
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(hovering ? NX.ink(0.035) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { env.workbench.openCapture(listID: listID, forToday: forToday) }
        .pointerStyle(.horizontalText)
        .padding(.top, 8)
    }
}

/// Right-click actions for a row or the current selection.
struct NXTaskMenu: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    let ids: [UUID]

    var body: some View {
        let workbench = env.workbench
        let tasks = workbench.tasks(ids)
        // A task in the completion dwell isn't completed yet; Reopen cancels the pending completion.
        let pending = tasks.filter { workbench.closing[$0.id] != nil }.map(\.id)
        let completed = tasks.filter(\.isCompleted).map(\.id)
        if tasks.count > pending.count + completed.count {
            Button("Mark as Done", systemImage: "checkmark.circle") { workbench.complete(ids) }
        }
        if !pending.isEmpty || !completed.isEmpty {
            Button("Reopen", systemImage: "arrow.uturn.backward.circle") {
                if !pending.isEmpty { workbench.cancelClosing(pending) }
                // One Undo step for the whole selection.
                workbench.reopen(completed)
            }
        }
        Button("Due Today", systemImage: "calendar") { workbench.schedule(ids, offset: 0) }
        Button("Due Tomorrow", systemImage: "sunset") { workbench.schedule(ids, offset: 1) }
        Button("Plan for Today", systemImage: "calendar.badge.clock") { workbench.plan(ids) }
        Button("Find a Slot", systemImage: "sparkles") { ids.forEach(workbench.fit) }
        Button("Star", systemImage: "star") { workbench.star(ids) }
        Menu("Move to") {
            ForEach(library.lists, id: \.id) { list in
                Button("\(list.glyph) \(list.displayTitle)") { workbench.move(ids, to: list.id) }
            }
        }
        Divider()
        if ids.count == 1 {
            Button("Open Details", systemImage: "sidebar.right") { workbench.inspect(ids[0]) }
            Button("Start Working", systemImage: "play") { workbench.startWork(ids[0]) }
            CopyItemLinkButton(target: .task(ids[0]))
        }
        Divider()
        Button("Move to Trash", systemImage: "trash", role: .destructive) { workbench.trash(ids) }
    }
}
