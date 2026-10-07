//
//  NextInspectorDetails.swift
//  openlist
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A lower section's heading that opens and closes it, like Activity's.
struct NXInspectorFold: View {
    @Environment(\.nextStyle) private var style
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button { withAnimation(style.ease(220)) { isExpanded.toggle() } } label: {
            HStack(spacing: 6) {
                NXCapsTitle(text: title)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(NX.ink(0.36))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

/// A quiet action row, like the design's "Add subtask": tertiary text, ink on hover.
struct NXInspectorQuietAction: View {
    let icon: String
    let title: String
    /// Takes the row's width, as Add subtask does under the subtasks.
    var fills = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 15, height: 15)
                    .accessibilityHidden(true)
                // 500 12.5/1.
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .padding(.vertical, (12.5 - NX.lineHeight(12.5)) / 2)
                if fills { Spacer(minLength: 0) }
            }
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.04), radius: 8,
                                        padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8),
                                        foreground: NX.textTertiary, hoverForeground: NX.ink))
    }
}

// MARK: - Planning

/// Plan the day, under its heading rather than in a card: the switch that
/// puts the task on today's plan, how long it takes on a slider, and where
/// the calendar has it, or Find a slot; the rest under More options.
struct NXInspectorPlan: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let task: Block
    /// On the page, where the row is wider than a slider reads well: the
    /// slider keeps a panel's length and its value sits right beside it.
    var isPage = false
    /// Where the slider is being dragged to, shown as it moves and set as
    /// the drag ends, so a drag is one change.
    @State private var dragged: Int?
    @State private var dragging = false

    /// The slider's stops: five minutes at a time to an hour, fifteen to
    /// three hours, then thirty to eight. A longer duration is typed.
    static let stops = Array(stride(from: 5, through: 60, by: 5)) + Array(stride(from: 75, through: 180, by: 15))
        + Array(stride(from: 210, through: 480, by: 30))

    private var workbench: Workbench { env.workbench }

    var body: some View {
        let estimate = task.schedulingEstimateMinutes > 0 ? task.schedulingEstimateMinutes : workbench.defaultEstimate
        let shown = dragged ?? estimate
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                NXCapsTitle(text: "Plan for today")
                Spacer(minLength: 6)
                // Planning skips completed tasks, so the switch fades.
                NXToggle(isOn: workbench.isPlanned(task), label: "Plan for today") { workbench.plan([task.id]) }
                    .disabled(task.isCompleted)
                    .opacity(task.isCompleted ? 0.45 : 1)
            }
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NX.textTertiary)
                    .accessibilityHidden(true)
                Slider(value: position(estimate: estimate), in: 0...Double(Self.stops.count - 1)) {
                    Text("Duration")
                } onEditingChanged: { editing in
                    dragging = editing
                    if !editing { commit(estimate: estimate) }
                }
                .labelsHidden()
                .controlSize(.small)
                .tint(style.accent)
                .frame(maxWidth: 340)
                .accessibilityValue(DurationText.text(for: shown))
                NXDurationField(minutes: shown, alignment: isPage ? .leading : .trailing) {
                    workbench.setEstimate(task.id, minutes: $0)
                }
                if isPage { Spacer(minLength: 0) }
            }
            slotRow
            NXInspectorPlanOptions(task: task)
        }
    }

    /// The slider's place, the stop nearest the duration; a move sets the
    /// stop it lands on, at once from the keys, at the end of a drag.
    private func position(estimate: Int) -> Binding<Double> {
        Binding(get: { Double(Self.stop(nearest: dragged ?? estimate)) },
                set: { value in
                    dragged = Self.stops[min(max(Int(value.rounded()), 0), Self.stops.count - 1)]
                    if !dragging { commit(estimate: estimate) }
                })
    }

    private func commit(estimate: Int) {
        guard let minutes = dragged else { return }
        dragged = nil
        if minutes != estimate { workbench.setEstimate(task.id, minutes: minutes) }
    }

    static func stop(nearest minutes: Int) -> Int {
        stops.indices.min { abs(stops[$0] - minutes) < abs(stops[$1] - minutes) } ?? 0
    }

    /// The slot the calendar grid draws for the task, as the design reads its
    /// placement, past or done ones too (see `CalendarWeek.shownSlot`), which
    /// shows it there; without one, Find a slot plans it.
    @ViewBuilder private var slotRow: some View {
        if let placement = CalendarWeek.shownSlot(of: task.id, occurrenceID: task.occurrenceID, in: env.calendar.visibleBlocks,
                                                  now: .now, calendar: env.settings.calendar) {
            let offset = NXFormat.dayOffset(placement.start)
            let day = offset == 0 ? "Today" : placement.start.formatted(.dateTime.weekday(.abbreviated).day())
            Button { workbench.showOnCalendar(slotOf: task.id, occurrenceID: task.occurrenceID) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 11, weight: .medium))
                    Text("\(day) \(NXFormat.clock(placement.start))–\(NXFormat.clock(placement.end))").monospacedDigit()
                }
            }
            .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .small))
            .padding(.leading, -5)
            .help("Show in the calendar")
            .accessibilityLabel("In the calendar \(day), \(NXFormat.clock(placement.start)) to \(NXFormat.clock(placement.end))")
        } else if !task.isCompleted {
            Button { workbench.fit(task.id) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 11, weight: .medium))
                    Text("Find a slot")
                }
            }
            .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .small))
            .padding(.leading, -5)
            .help("Find a free slot in the calendar")
        }
    }
}

/// A task's duration, typed as it's said: "45", "1h30", "1.5 hours". At rest
/// it's the duration's text, beside the slider; a click opens it for typing,
/// all of it selected. Return or leaving the field sets it, and Esc, or text
/// that isn't a duration, puts back what it was. The field is there only
/// while typed in, so focus never wanders into it.
struct NXDurationField: View {
    @Environment(\.nextStyle) private var style
    let minutes: Int
    /// Beside the slider, its text starts there; at the row's end, it ends there.
    var alignment: HorizontalAlignment = .trailing
    let onCommit: (Int) -> Void
    /// What's being typed; nil shows the duration.
    @State private var draft: String?
    @State private var hovering = false
    @FocusState private var focused: Bool

    private var shown: String { DurationText.text(for: minutes) }

    var body: some View {
        Group {
            if draft != nil {
                TextField("Duration", text: Binding(get: { draft ?? "" }, set: { draft = $0 }))
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit {
                        if !commit() { NSSound.beep() }
                    }
                    .onExitCommand { draft = nil }
                    .onChange(of: focused) { _, now in
                        if !now, !commit() { draft = nil }
                    }
                    // Once it's on screen, or the focus can miss it.
                    .onAppear { DispatchQueue.main.async { focused = true } }
            } else {
                Button { draft = shown } label: {
                    Text(shown).frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Type a duration")
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .monospacedDigit()
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        .foregroundStyle(NX.ink)
        .frame(width: 70)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(NX.ink(draft != nil ? 0.06 : hovering ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(draft != nil ? style.accent.opacity(0.6) : .clear, lineWidth: 1))
        .onHover { hovering = $0 }
        // The text, not its hover fill, lines up with what's beside it.
        .padding(alignment == .leading ? .leading : .trailing, -6)
        .accessibilityLabel("Duration")
        .accessibilityValue(shown)
    }

    /// Sets what's typed, when it's a duration, and shows it.
    private func commit() -> Bool {
        guard let draft else { return true }
        guard let typed = DurationText.minutes(from: draft) else { return false }
        if typed != minutes { onCommit(typed) }
        self.draft = nil
        return true
    }
}

/// Calendar planning beyond the day toggle and estimate: deferral, how
/// sessions run and what has been recorded.
struct NXInspectorPlanOptions: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    let task: Block
    @State private var expanded = false
    @State private var deferring = false
    @State private var showsHistory = false

    var body: some View {
        // As the design's card, it says nothing of the planner's own sessions,
        // which the calendar never draws; the slot line says where the task is.
        VStack(alignment: .leading, spacing: 8) {
            if let deferred = task.deferredUntil {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.forward").font(.system(size: 10.5, weight: .semibold))
                    Text("Deferred until \(NXFormat.dueLabel(deferred))")
                    Spacer(minLength: 6)
                    Button("Clear") { env.workbench.clearDeferral(task.id) }
                        .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .small))
                        .padding(.trailing, -5)
                        .accessibilityLabel("Clear task deferral")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NX.textTertiary)
            }
            NXDisclosureButton("More options", isExpanded: $expanded)
            if expanded {
                options.transition(.opacity)
            }
        }
        .popover(isPresented: $deferring, arrowEdge: .bottom) { TaskDeferralPicker(block: task).environment(env) }
        .sheet(isPresented: $showsHistory) { CalendarHistoryView(taskID: task.id).environment(env) }
    }

    /// Built only when expanded: the suggestion and recorded time read history.
    private var options: some View {
        let calendar = env.calendar
        let estimate = Int(calendar.estimatedMinutes(for: task))
        let personal = library.list(task.listID)?.availabilityCategoryRaw == "personal"
        let suggestion = env.store.suggestedDuration(for: task).flatMap { $0.minutes != estimate ? $0 : nil }
        let ownEstimate = task.schedulingEstimateMinutes != 0
        return VStack(alignment: .leading, spacing: 9) {
            if suggestion != nil || ownEstimate {
                HStack(spacing: 6) {
                    if let suggestion {
                        Button("Use \(DurationText.text(for: suggestion.minutes))") { env.store.setTaskEstimate(suggestion.minutes, for: task) }
                            .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .small))
                            .accessibilityHint(suggestion.description)
                    }
                    if ownEstimate {
                        Button("Reset to \(DurationText.text(for: Int(calendar.preferences.defaultEstimateMinutes)))") {
                            env.store.setTaskEstimate(0, for: task)
                        }
                        .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .small))
                    }
                }
                .padding(.leading, -5)
            }
            toggle("Keep together", isOn: task.keepsSessionsTogether) {
                env.store.setKeepTogether(!task.keepsSessionsTogether, for: task)
            }
            toggle("Track away from this Mac", isOn: task.tracksAwayFromMac) {
                env.store.setTracksAway(!task.tracksAwayFromMac, for: task)
            }
            HStack(spacing: 6) {
                Image(systemName: personal ? "house" : "briefcase").font(.system(size: 10.5))
                Text(personal ? "Personal hours" : "Work hours")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NX.textTertiary)
            HStack(spacing: 6) {
                if !task.isCompleted {
                    Button("Defer…") { deferring = true }
                        .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .small))
                        .padding(.leading, -5)
                }
                Spacer(minLength: 6)
                Text("\(DurationText.text(for: Int(calendar.trackedMinutes(for: task).rounded()))) recorded")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(NX.textTertiary)
                Button("History") { showsHistory = true }
                    .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .small))
                    .padding(.trailing, -5)
            }
        }
        .padding(.top, 9)
        .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }
    }

    private func toggle(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(NX.textSecondary)
            Spacer(minLength: 6)
            NXToggle(isOn: isOn, label: title, action: action)
        }
    }
}

// MARK: - Subtasks

/// The task's subtasks as the design lists them: every task under it, in
/// document order and indented by depth, with their progress. Rows tick and
/// open from here; Add subtask writes the new line in the list's document.
struct NXInspectorSubtasks: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let task: Block
    /// Whether the section shows for a task with no subtasks yet.
    let showsEmpty: Bool
    @Query private var blocks: [Block]

    init(task: Block, showsEmpty: Bool = true) {
        self.task = task
        self.showsEmpty = showsEmpty
        _blocks = OutlineEditor.blocksQuery(for: DocumentContext(listID: task.listID ?? UUID()))
    }

    var body: some View {
        let workbench = env.workbench
        let rows = Self.subtasks(of: task.id, in: blocks)
        let done = rows.filter { $0.block.isCompleted || workbench.closing[$0.id] != nil }.count
        let fraction = rows.isEmpty ? 0 : CGFloat(done) / CGFloat(rows.count)
        if showsEmpty || !rows.isEmpty {
            section(rows: rows, done: done, fraction: fraction)
        }
    }

    private func section(rows: [BlockRow], done: Int, fraction: CGFloat) -> some View {
        let workbench = env.workbench
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                NXCapsTitle(text: "Subtasks")
                // Empty without subtasks, and still spaced, as the design's
                // count is; in the same 10.5/1 line box as the title.
                Text(rows.isEmpty ? "" : "\(done)/\(rows.count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(NX.textTertiary)
                    .monospacedDigit()
                    .padding(.vertical, (10.5 - NX.lineHeight(10.5)) / 2)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(NX.ink(0.07))
                        // As the design's, only the width eases; the fill
                        // turns green at once as the last one closes.
                        RoundedRectangle(cornerRadius: 2)
                            .animation(nil) { $0.foregroundStyle(!rows.isEmpty && done == rows.count ? NX.green : style.accent) }
                            .frame(width: proxy.size.width * fraction)
                    }
                    .animation(NX.cssEase(400), value: fraction)
                }
                .frame(height: 3)
            }
            .padding(.bottom, 6)
            ForEach(rows) { row in
                NXInspectorSubtaskRow(row: row)
            }
            NXInspectorQuietAction(icon: "plus", title: "Add subtask", fills: true) { workbench.addSubtask(to: task.id) }
        }
    }

    /// Every task under `id`, at any depth, in document order; each row's
    /// depth counts from the task's own children.
    static func subtasks(of id: UUID, in blocks: [Block]) -> [BlockRow] {
        let live = blocks.filter { $0.modelContext != nil && !$0.isDeleted }
        return BlockTree.flatten(live, root: id, respectCollapse: false).filter(\.block.isTask)
    }
}

/// One subtask: 15pt checkbox, 13pt title, struck once done, and a chevron.
/// A click inspects it. As the design, an untitled one shows blank.
private struct NXInspectorSubtaskRow: View {
    @Environment(AppEnvironment.self) private var env
    let row: BlockRow
    @State private var hovering = false

    var body: some View {
        let workbench = env.workbench
        let task = row.block
        let closing = workbench.closing[task.id]
        let filled = task.isCompleted || closing != nil
        HStack(spacing: 9) {
            // 18 a level; at the top it's still one of the row's gaps, as in the design.
            Color.clear.frame(width: CGFloat(row.depth) * 18, height: 1)
            NXCheckbox(filled: filled, closing: closing, priority: .none, title: task.displayTitle, size: 15, pops: false) {
                workbench.toggle(task.id)
            }
            // 400 13/1.3.
            Text(task.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 13))
                .foregroundStyle(filled ? NX.textTertiary : NX.ink)
                .strikethrough(filled, color: NX.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.vertical, (13 * 1.3 - NX.lineHeight(13)) / 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(NX.ink(0.3))
                .frame(width: 14, height: 14)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(hovering ? NX.ink(0.04) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        // The design's `opacity 300ms ease`, which eases nothing else.
        .animation(NX.cssEase(300)) { $0.opacity(closing != nil ? 0.6 : 1) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { workbench.inspect(task.id) }
        .contextMenu { NXTaskMenu(ids: [task.id]) }
        // One element: opening is its action, ticking a named one.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(task.displayTitle)
        .accessibilityValue(closing != nil ? "Completing" : filled ? "Completed" : "Open")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { workbench.inspect(task.id) }
        .accessibilityAction(named: filled ? "Reopen" : "Complete") { workbench.toggle(task.id) }
        .accessibilityAction(named: "Open Details") { workbench.inspect(task.id) }
    }
}

/// "Subtask of" the task above, over the inspector's title, with that
/// task's progress. A click inspects it.
struct NXInspectorParentCrumb: View {
    @Environment(AppEnvironment.self) private var env
    let parent: Block
    @Query private var blocks: [Block]
    @State private var hovering = false

    init(parent: Block) {
        self.parent = parent
        _blocks = OutlineEditor.blocksQuery(for: DocumentContext(listID: parent.listID ?? UUID()))
    }

    var body: some View {
        let workbench = env.workbench
        let subtasks = NXInspectorSubtasks.subtasks(of: parent.id, in: blocks)
        let done = subtasks.filter { $0.block.isCompleted || workbench.closing[$0.id] != nil }.count
        Button { workbench.inspect(parent.id) } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14, height: 14)
                Text("Subtask of")
                    .font(.system(size: 11.5, weight: .medium))
                    .fixedSize()
                // As the design, the parent's text as written, blank when it has none.
                Text(parent.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(NX.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(done)/\(subtasks.count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .opacity(0.8)
                    .fixedSize()
            }
            .foregroundStyle(hovering ? NX.ink : NX.textTertiary)
            .padding(.top, 5)
            .padding(.bottom, 5)
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .background(NX.ink(hovering ? 0.07 : 0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Its hover shows at once, as the design's style-hover.
        .onHover { hovering = $0 }
        .accessibilityLabel("Subtask of \(parent.displayTitle)")
        // The design's -4 above and -8 below, so it sits close over the title.
        .padding(.top, -4)
        .padding(.bottom, -8)
    }
}

// MARK: - Files

/// Files kept with the task. The design has none, so the section shows only
/// once there are some; the footer's paperclip attaches them, and files
/// dropped anywhere on the panel are attached too.
struct NXInspectorFiles: View {
    @Environment(AppEnvironment.self) private var env
    let task: Block

    var body: some View {
        let attachments = env.store.attachments(for: task.id)
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                NXCapsTitle(text: "Files")
                    .padding(.bottom, 4)
                ForEach(attachments) { attachment in
                    AttachmentRow(attachment: attachment) { env.workbench.removeAttachment(attachment) }
                }
            }
        }
    }
}

/// Keeps files with a task, chosen in the Open panel or dropped, as one
/// Workbench step (`Workbench.attachFiles`).
struct NXTaskFiles {
    let workbench: Workbench

    func choose(for block: Block) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        workbench.attachFiles(panel.urls, to: block.id)
    }

    func drop(_ providers: [NSItemProvider], on blockID: UUID) -> Bool {
        // The provider calls back off the main actor, so carry the id rather
        // than the model object itself.
        let dropped = DroppedFiles(workbench: workbench, blockID: blockID, count: providers.count)
        for (index, provider) in providers.enumerated() {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in dropped.receive(url, at: index) }
            }
        }
        return true
    }
}

/// A drop's files as their providers hand them over, attached together, in
/// the order dropped, once the last has arrived.
private final class DroppedFiles {
    let workbench: Workbench
    let blockID: UUID
    private var urls: [URL?]
    private var remaining: Int

    init(workbench: Workbench, blockID: UUID, count: Int) {
        self.workbench = workbench
        self.blockID = blockID
        urls = Array(repeating: nil, count: count)
        remaining = count
    }

    func receive(_ url: URL?, at index: Int) {
        urls[index] = url
        remaining -= 1
        guard remaining == 0 else { return }
        workbench.attachFiles(urls.compactMap(\.self), to: blockID)
    }
}

// MARK: - History

/// The task's saved activity. Unlike the session's change log it survives a
/// relaunch and includes changes made over MCP or on another Mac.
struct NXInspectorHistory: View {
    @Environment(AppEnvironment.self) private var env
    let task: Block
    @State private var expanded = false
    @State private var limit = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NXDisclosureButton("Full history", isExpanded: $expanded)
            // Queried only when open, so a closed disclosure fetches no history.
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Created \(NXFormat.moment(task.createdAt))")
                        if let completedAt = task.completedAt {
                            Text("Completed \(NXFormat.moment(completedAt))")
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NX.textTertiary)
                    NXInspectorHistoryPage(taskID: task.id, limit: limit,
                                           excluded: Array(env.store.uncommittedActivityIDs)) { limit += 50 }
                }
                .transition(.opacity)
            }
        }
    }
}

private struct NXInspectorHistoryPage: View {
    let limit: Int
    let loadOlder: () -> Void
    @Query private var events: [ActivityEvent]

    init(taskID: UUID, limit: Int, excluded: [UUID], loadOlder: @escaping () -> Void) {
        self.limit = limit
        self.loadOlder = loadOlder
        // One past the page, which shows Load older activity. The Store's
        // query excludes before the limit applies, so failed attempts can't
        // use up a page or hide it.
        _events = Query(Store.taskActivityDescriptor(for: taskID, excluding: excluded, limit: limit + 1))
    }

    /// Activity's 12/1.4, so the saved rows keep the rhythm of the ones above.
    private var leading: CGFloat { 12 * 1.4 - NX.lineHeight(12) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if events.isEmpty {
                Text("No recorded activity for this task.")
                    .font(.system(size: 12))
                    .lineSpacing(leading)
                    .foregroundStyle(NX.textTertiary)
                    .padding(.vertical, 5 + leading / 2)
            } else {
                ForEach(events.prefix(limit)) { event in
                    row(event)
                }
                if events.count > limit {
                    Button("Load older activity", action: loadOlder)
                        .buttonStyle(NXPanelButtonStyle(kind: .quiet, size: .small))
                        .padding(.leading, -5)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func row(_ event: ActivityEvent) -> some View {
        let when = NXFormat.moment(event.timestamp)
        let spoken = event.listTitle.isEmpty ? when : "\(when) · \(event.listTitle)"
        // Its due dates in the words of the time under them, as recordedDetail writes them.
        let detail = ActivityEvent.recordedDetail(event.kind, detail: event.detail, change: event.change)
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: event.kind.symbol).font(.system(size: 11.5, weight: .medium)).foregroundStyle(NX.ink(0.4)).frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(event.kind.verb) “\(event.title)”")
                    .font(.system(size: 12))
                    .lineSpacing(leading)
                    .foregroundStyle(NX.textSecondary)
                    .padding(.vertical, leading / 2)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(NX.textTertiary)
                }
                place(event, when: when)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NX.textQuaternary)
                    // The line without its list's glyph, which reads as a symbol's name.
                    .accessibilityLabel(spoken)
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    /// When it happened and in which list, its glyph drawn as the Activity
    /// day panel draws it: an SF Symbol from synced or older data as the
    /// symbol, never its name.
    private func place(_ event: ActivityEvent, when: String) -> Text {
        let title = event.listTitle
        guard !event.listIcon.isEmpty else { return Text(verbatim: title.isEmpty ? when : "\(when) · \(title)") }
        let glyph = NXListGlyph.text(event.listIcon, size: 10.5)
        return title.isEmpty ? Text("\(when) · \(glyph)") : Text("\(when) · \(glyph) \(title)")
    }
}
