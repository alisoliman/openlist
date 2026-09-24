//
//  NextRow.swift
//  openlist
//

import SwiftData
import SwiftUI

/// How a screen wants its rows drawn.
struct NXRowOptions {
    /// Show the list chip, except for tasks in `listID`.
    var showList = true
    var listID: UUID?
    var notes = false
    /// Tasks screen: text-only chips, the open icon hidden until focus.
    var quiet = false
    /// The clock the due and done-ago chips read. Screens on a timeline pass its
    /// date so rows refresh with it; nil reads the time when the row draws.
    var now: Date?
}

/// A task row: rail, checkbox, text with strike, chips, selection mark and open icon.
struct NextTaskRow: View {
    @Environment(AppEnvironment.self) private var env
    let task: Block
    var options = NXRowOptions()

    var body: some View {
        let closing = env.workbench.closing[task.id]
        NXTaskRowChrome(task: task, options: options) {
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
                        // The design's 1.4 line box, its leading split above and below.
                        .padding(.vertical, max(0, 12 * 1.4 - NXStrikeText.glyphLineHeight(12)) / 2)
                }
            }
        }
    }
}

/// Everything around a task row's title: the dwell rail, checkbox, chips,
/// selection mark and open icon, and the focus, selection, fresh and closing
/// states. Screens give it `NXStrikeText`; the list document its live text.
struct NXTaskRowChrome<Title: View, Buttons: View>: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let task: Block
    var options = NXRowOptions()
    var indent: CGFloat = 0
    /// Chips before the row's own, like the document's subtask progress.
    var leadingChips: [NXChipModel] = []
    /// Being written in the list document: the design's editing fill in
    /// place of the focused card.
    var editing = false
    /// The rowIn a fresh row plays, in milliseconds. `nil` plays none, for
    /// the list document, whose lines play their own whatever their kind.
    var entrance: Double? = 320
    /// The whole row drags. The list document's text keeps its own drag.
    var draggable = true
    /// The pointer tints the row, as the screens' grouped rows do. The list
    /// document's lines have no hover of their own.
    var hoverFill = true
    /// The open icon comes to full strength under the pointer, as the list
    /// document's does.
    var opensOnHover = false
    /// A click on the row around its title. `nil` is the workbench's click.
    var onClick: (() -> Void)?
    @ViewBuilder var title: () -> Title
    /// Buttons before the open icon, like the document's note button.
    @ViewBuilder var buttons: () -> Buttons
    @State private var hovering = false
    @State private var openHovering = false
    /// Set once a freshly captured row has played its rowIn entrance.
    @State private var entered = false

    private var workbench: Workbench { env.workbench }

    var body: some View {
        // A row's own update can come after its task is deleted, as a new
        // line's Escape takes it away, and before its list has dropped it.
        if task.modelContext != nil, !task.isDeleted { row }
    }

    @ViewBuilder private var row: some View {
        let id = task.id
        let closing = workbench.closing[id]
        let flying = workbench.flying.contains(id)
        let focused = workbench.focusID == id || env.navigator.openTaskID == id
        let selected = workbench.selection.contains(id)
        let fresh = workbench.fresh.contains(id)
        let entering = fresh && !entered && entrance != nil
        let restored = workbench.restored.contains(id)
        let freshChip = workbench.freshChip.contains(id)

        HStack(alignment: .top, spacing: 0) {
            if indent > 0 {
                Color.clear.frame(width: indent, height: 1)
            }
            NXCheckbox(filled: task.isCompleted || closing != nil,
                       closing: closing, priority: task.priority, title: task.displayTitle,
                       ringing: workbench.pulseTaskID == id && closing != nil) {
                // A line being written is left first, as a click on the box leaves it in the design.
                NXDocumentEditing.end()
                workbench.toggle(id)
            }
            .frame(width: 26, alignment: .leading)
            // Centres the 16pt circle on the title's 20pt first line, as the design's 2px does.
            .padding(.top, 2)

            title()
                // The title takes what the chips leave and wraps into it.
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            // Chips claim their natural width first and wrap onto trailing lines
            // when the row is too narrow, so none is ever hidden. They wrap early
            // only to keep a title that doesn't fit beside them its first 96pt,
            // where the design would squeeze it to nothing.
            NXChipFlow(spacing: 6, titleRoom: min(96, NXStrikeText.lineWidth(task.displayTitle))) {
                ForEach(leadingChips + NXRowChips.chips(for: task, options: options, library: library, workbench: workbench)) { chip in
                    // A change pops every chip; a new row pops all but its list and star.
                    NXChip(chip: chip, fresh: freshChip || fresh && chip.popsWithRow, quiet: options.quiet)
                }
                if selected { NXSelectionMark() }
                buttons()
                Button {
                    // The inspector takes the keys, not the line being written.
                    NXDocumentEditing.end()
                    workbench.inspect(task.id)
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 12.5, weight: .medium))
                }
                .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), radius: 6,
                                                padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3),
                                                foreground: NX.ink(0.45), hoverForeground: NX.ink))
                .onHover { openHovering = $0 }
                // Only the fade is animated, so the icon never trails a reflow.
                .animation(.easeOut(duration: 0.14)) {
                    $0.opacity(focused || opensOnHover && openHovering ? 1 : options.quiet ? 0 : 0.22)
                }
                .help("Open details (↩)")
                .accessibilityLabel("Open details")
            }
            .padding(.top, 1)
            .padding(.leading, 2)
            .layoutPriority(1)
        }
        .padding(.vertical, style.rowVerticalPadding)
        .padding(.horizontal, 10)
        .background(alignment: .leading) {
            if closing != nil { NXDrainRail(duration: style.dwell) }
        }
        .background {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            let card = focused && !editing
            let fill = editing ? NX.ink(0.035) : background(focused: focused, selected: selected, fresh: fresh, restored: restored)
            let ring = card ? style.accent.opacity(0.25) : selected && !editing ? style.accent.opacity(0.19) : Color.clear
            // As the design: the fill eases over 700ms, the focus shadow and ring
            // over 180ms. Each animation covers only its colour or opacity, so a
            // row that resizes in the same update never drags its background.
            ZStack {
                NXRowShadow()
                    .animation(.easeOut(duration: 0.18)) { $0.opacity(card ? 1 : 0) }
                shape.animation(.easeOut(duration: editing ? 0.18 : 0.7)) { $0.foregroundStyle(fill) }
                shape.strokeBorder(lineWidth: 1)
                    .animation(.easeOut(duration: 0.18)) { $0.foregroundStyle(ring) }
            }
        }
        .contentShape(Rectangle())
        // rowIn: a freshly captured row slides down into place.
        .opacity(entering ? 0 : 1)
        .offset(y: entering ? -8 : 0)
        .scaleEffect(entering ? 0.99 : 1)
        .onAppear { if fresh { enter() } }
        .onChange(of: fresh) { _, isFresh in if isFresh, !entered { enter() } }
        .opacity(flying ? 0 : closing != nil ? 0.62 : 1)
        .offset(x: flying ? -56 : 0)
        .scaleEffect(flying ? 0.97 : 1)
        .animation(style.standard(280), value: flying)
        .animation(style.ease(280), value: closing)
        .zIndex(editing ? 4 : focused ? 3 : 0)
        .onHover { hovering = $0 }
        .onTapGesture {
            if let onClick { onClick() } else { workbench.click(id, command: NXModifiers.command, shift: NXModifiers.shift) }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { workbench.inspect(id) })
        .contextMenu { NXTaskMenu(ids: workbench.selection.contains(id) ? Array(workbench.selection) : [id]) }
        .modifier(NXRowDrag(id: id, isEnabled: draggable))
        .id(id)
    }

    private func enter() {
        guard let entrance else { entered = true; return }
        withAnimation(style.ease(entrance)) { entered = true }
    }

    private func background(focused: Bool, selected: Bool, fresh: Bool, restored: Bool) -> Color {
        if focused { return NX.card }
        if selected { return style.accent.opacity(0.08) }
        if fresh { return style.accent.opacity(0.11) }
        if restored { return style.accent.opacity(0.07) }
        return hovering && hoverFill ? NX.ink(0.03) : .clear
    }
}

extension NXTaskRowChrome where Buttons == EmptyView {
    init(task: Block, options: NXRowOptions = NXRowOptions(), @ViewBuilder title: @escaping () -> Title) {
        self.init(task: task, options: options, title: title) { EmptyView() }
    }
}

/// Drags a whole row to a list in the sidebar, or to a line of the list
/// document, in this library's own payload: never text a line could take in.
private struct NXRowDrag: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    let id: UUID
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.onDrag { NXBlockDrag.provider(for: [id], session: env.navigator.blockDragSessionID) }
        } else {
            content
        }
    }
}

/// The rows a drag carries, readable only by this app.
enum NXBlockDrag {
    static func provider(for ids: [UUID], session: UUID) -> NSItemProvider {
        let payload = DragPayload.encodeBlocks(ids, session: session)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: DragPayload.blockTypeIdentifier, visibility: .ownProcess) { load in
            load(Data(payload.utf8), nil)
            return nil
        }
        return provider
    }
}

/// A focused row's drop shadow on a layer of its own, cut away inside the
/// row, so it fades at the design's box-shadow pace however far the fill
/// has eased in underneath.
private struct NXRowShadow: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(NX.card)
            .shadow(color: NX.shadowWarm.opacity(0.09), radius: 8, y: 4)
            .clipShape(Outside(), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)
    }

    /// Everywhere the shadow reaches except the row itself.
    private nonisolated struct Outside: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path(rect.insetBy(dx: -24, dy: -24))
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 9, height: 9), style: .continuous)
            return path
        }
    }
}

/// The accent check a selected row shows, with the design's chipIn entrance.
struct NXSelectionMark: View {
    @Environment(\.nextStyle) private var style
    @State private var shown = false

    var body: some View {
        // With Reduce Motion it only fades, as the chips do.
        let risen = shown || !style.slides
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(style.accent)
            .frame(width: 16, height: 16)
            .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white))
            .scaleEffect(risen ? 1 : 0.85)
            .offset(y: risen ? 0 : 3)
            .opacity(shown ? 1 : 0)
            .onAppear {
                // Plays on insertion whether or not the selection change was
                // animated, at the design's 180ms whatever the Motion setting.
                withAnimation(NX.cssEase(180)) { shown = true }
            }
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
        // The design's 1.45 line height: the extra leading goes between lines
        // and, halved, above the first and below the last, as CSS places it.
        let glyphLine = Self.glyphLineHeight(size)
        let leading = max(0, size * 1.45 - glyphLine)
        Text(text)
            .font(.system(size: size))
            .lineSpacing(leading)
            .foregroundStyle(dimmed ? NX.ink(0.42) : NX.ink)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    // The strike's top edge sits at 52% of the first line's glyph box.
                    Capsule()
                        .fill(closing ? style.accent : NX.ink(0.36))
                        .frame(width: struck ? geo.size.width + 2 : 0, height: 1.5)
                        .offset(y: min(geo.size.height, glyphLine) * 0.52)
                        .animation(.timingCurve(0.3, 0.8, 0.2, 1, duration: style.ms(340) / 1000), value: struck)
                }
                .allowsHitTesting(false)
            }
            .padding(.vertical, leading / 2)
    }

    /// The height SwiftUI gives one line of the system font at `size`.
    static func glyphLineHeight(_ size: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size)
        return font.ascender - font.descender + font.leading
    }

    /// The width `text` needs to sit on one line at `size`.
    static func lineWidth(_ text: String, size: CGFloat = 13.8) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size)]).width)
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
                // The design's tick: a 140ms fade and a 200ms spring, at
                // those speeds whatever the Motion setting.
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.6, weight: .heavy))
                    .foregroundStyle(.white)
                    .animation(NX.cssEase(140)) { $0.opacity(filled ? 1 : 0) }
                    .animation(style.bounce(200)) { $0.scaleEffect(filled ? 1 : 0.3) }
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
            .opacity(grown ? 0 : 0.6)
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

/// The row's chip column, laid out like the design's `flex-wrap: wrap;
/// justify-content: flex-end`: one line at natural width while it fits, then
/// further lines, each aligned to the trailing edge. Items keep their order.
struct NXChipFlow: Layout {
    var spacing: CGFloat = 6
    /// Room the chips leave beside them by wrapping sooner, so a narrow row's
    /// title stays readable. Given up only when one chip needs it.
    var titleRoom: CGFloat = 0

    private struct Line {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(subviews, width: proposal.width.map { $0 - titleRoom } ?? .infinity)
        guard !lines.isEmpty else { return .zero }
        return CGSize(width: lines.map(\.width).max() ?? 0,
                      height: lines.map(\.height).reduce(0, +) + spacing * CGFloat(lines.count - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        // Wrapping at the widest line reproduces the lines sizeThatFits chose.
        for line in lines(subviews, width: bounds.width) {
            var x = bounds.maxX - line.width
            for (index, size) in line.items {
                // Centred on the line, as the design's align-items: center.
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    private func lines(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            // Half a point of slack so rounding never wraps a line that fits.
            if !line.items.isEmpty, line.width + spacing + size.width > width + 0.5 {
                lines.append(line)
                line = Line()
            }
            line.width += (line.items.isEmpty ? 0 : spacing) + size.width
            line.height = max(line.height, size.height)
            line.items.append((index, size))
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }
}

enum NXRowChips {
    @MainActor
    static func chips(for task: Block, options: NXRowOptions, library: NextLibrary, workbench: Workbench) -> [NXChipModel] {
        var chips: [NXChipModel] = []
        let done = task.isCompleted
        let now = options.now ?? .now
        if options.showList, task.listID != options.listID, let list = library.list(task.listID) {
            chips.append(NXChipModel(id: "list", label: list.displayTitle, glyph: list, popsWithRow: false))
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
            // Neutral all day, as the design's: only an earlier day reads as late.
            chips.append(NXChipModel(id: "time", label: NXFormat.clock(due), icon: "bell.fill", fill: true))
        }
        if !done, workbench.isPlanned(task) {
            let minutes = task.schedulingEstimateMinutes
            chips.append(NXChipModel(id: "planned", label: minutes > 0 ? "\(minutes)m" : "Planned",
                                     icon: "calendar.badge.clock", tone: .accent))
        }
        if let due = task.dueDate, !done {
            // By day, as the design: earlier days are overdue, a time today never is.
            let offset = NXFormat.dayOffset(due, now: now)
            chips.append(NXChipModel(id: "due", label: NXFormat.dueLabel(due, now: now),
                                     icon: offset < 0 ? "exclamationmark.circle.fill" : "calendar",
                                     tone: offset < 0 ? .over : offset == 0 ? .accent : .neutral, fill: offset < 0))
        }
        if task.isStarred {
            chips.append(NXChipModel(id: "star", label: "", icon: "star.fill", tone: .amber, fill: true, popsWithRow: false))
        }
        if done, let at = task.completedAt {
            chips.append(NXChipModel(id: "done", label: NXFormat.relative(at, now: now)))
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
    /// Whether the group starts open, until the user folds it this session.
    var defaultOpen = true
    /// A Completed group, on Today, a list or a label. These fold as one, as
    /// the design's completedOpen, so the last fold shows on every screen.
    var completed = false
    /// The list a Completed group sits under, whose own new choice there
    /// shows over the last fold.
    var listID: UUID?
    var emptyText = ""
    var actionLabel: String?
    var action: (() -> Void)?
}

extension NXGroup {
    /// Whether the group shows its rows. A Completed group follows the fold
    /// they share (`NXCompletedFold`); another's own fold flips its default,
    /// which is the same wherever it shows.
    @MainActor
    func isOpen(in workbench: Workbench) -> Bool {
        guard collapsible else { return true }
        if completed {
            return NXCompletedFold.isOpen(workbench.completedFold, default: defaultOpen, list: listID)
        }
        return defaultOpen != workbench.collapsedGroups.contains(id)
    }

    @MainActor
    func toggle(in workbench: Workbench) {
        guard collapsible else { return }
        if completed {
            workbench.completedFold = NXCompletedFold(open: !isOpen(in: workbench))
        } else if workbench.collapsedGroups.contains(id) {
            workbench.collapsedGroups.remove(id)
        } else {
            workbench.collapsedGroups.insert(id)
        }
    }
}

struct NXGroupView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let group: NXGroup
    var options = NXRowOptions()

    var body: some View {
        let open = group.isOpen(in: env.workbench)
        VStack(alignment: .leading, spacing: 0) {
            if group.showHead { head(open: open) }
            if open {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(group.rows, id: \.id) { task in
                        // A fresh row plays its own rowIn, so an animated insertion doesn't slide it twice.
                        let slides = !env.workbench.fresh.contains(task.id)
                        NextTaskRow(task: task, options: options)
                            .transition(.asymmetric(
                                insertion: slides ? .offset(y: -8).combined(with: .scale(scale: 0.99)).combined(with: .opacity) : .identity,
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

    private func head(open: Bool) -> some View {
        HStack(spacing: 7) {
            // VoiceOver reads the title and count as one, a button that folds the group.
            HStack(spacing: 7) {
                Group {
                    if let glyph = group.glyph {
                        NXListGlyph(list: glyph, size: 13)
                    } else if let icon = group.icon {
                        Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(group.color)
                    }
                }
                .accessibilityHidden(true)
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
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
            .modifier(NXFoldAccessibility(isEnabled: group.collapsible, open: open, toggle: toggle))
            Spacer(minLength: 8)
            if let label = group.actionLabel, let action = group.action {
                Button(label, action: action)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(NXHoverButtonStyle(hover: style.accent.opacity(0.16), rest: style.accent.opacity(0.08), radius: 6,
                                                    padding: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8),
                                                    foreground: style.accent))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }

    private func toggle() {
        // The design's chevron turns in 180ms whatever the Motion setting.
        withAnimation(NX.cssEase(180)) { group.toggle(in: env.workbench) }
    }
}

/// A collapsible group head's role for VoiceOver: a button that says
/// whether the group is open.
private struct NXFoldAccessibility: ViewModifier {
    let isEnabled: Bool
    let open: Bool
    let toggle: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .accessibilityValue(open ? "Expanded" : "Collapsed")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { toggle() }
        } else {
            content
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
        .onTapGesture(perform: open)
        .pointerStyle(.horizontalText)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }

    private func open() { env.workbench.openCapture(listID: listID, forToday: forToday) }
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
        Button("Due Tomorrow", systemImage: "sun.horizon") { workbench.schedule(ids, offset: 1) }
        Button("Plan for Today", systemImage: "calendar.badge.clock") { workbench.plan(ids) }
        Button("Find a Slot", systemImage: "sparkles") { ids.forEach(workbench.fit) }
        // Star toggles, so it reads every target as Task ▸ does: all starred unstars them.
        let unstars = !tasks.isEmpty && tasks.allSatisfy(\.isStarred)
        Button(unstars ? "Unstar" : "Star", systemImage: unstars ? "star.slash" : "star") { workbench.star(ids) }
        // The palette's subdirectory_arrow_right.
        Menu("Move to", systemImage: "arrow.turn.down.right") {
            ForEach(library.lists, id: \.id) { list in
                NXListMenuButton(list: list) { workbench.move(ids, to: list.id) }
            }
        }
        Divider()
        if ids.count == 1 {
            Button("Open Details", systemImage: "sidebar.right") { workbench.inspect(ids[0]) }
            Button("Start Working", systemImage: "play") { workbench.startWork(ids[0]) }
            CopyItemLinkButton(target: .task(ids[0]), iconed: true)
            Button("Copy Text", systemImage: "doc.on.clipboard") { workbench.copyText(ids[0]) }
            Button("Copy Content and Subtasks", systemImage: "list.bullet.clipboard") { workbench.copyContent(ids[0]) }
            Divider()
            Button("Duplicate", systemImage: "plus.square.on.square") { workbench.duplicate(ids[0]) }
            Button("Use as Template…", systemImage: "doc.on.doc") {
                env.templateCopyRequest = TemplateCopyRequest(source: .task(ids[0]), undoManager: nil)
            }
        }
        Divider()
        Button("Move to Trash", systemImage: "trash", role: .destructive) { workbench.trash(ids) }
    }
}
