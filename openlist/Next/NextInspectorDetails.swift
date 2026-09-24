//
//  NextInspectorDetails.swift
//  openlist
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A small caps heading for the inspector's lower sections, like Activity.
struct NXInspectorHeading<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.74)
                .textCase(.uppercase)
                .foregroundStyle(NX.ink(0.36))
            Spacer(minLength: 6)
            accessory()
        }
    }
}

/// A quiet text button for secondary inspector actions.
private struct NXInspectorLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 5,
                                            padding: EdgeInsets(top: 2, leading: 5, bottom: 2, trailing: 5),
                                            foreground: NX.ink(0.6), hoverForeground: NX.ink))
            .font(.system(size: 11, weight: .semibold))
    }
}

/// A quiet action row, like the design's "Add subtask": ink 0.42, ink on hover.
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
                    .padding(.vertical, (12.5 - NXStrikeText.glyphLineHeight(12.5)) / 2)
                if fills { Spacer(minLength: 0) }
            }
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.04), radius: 8,
                                        padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8),
                                        foreground: NX.ink(0.42), hoverForeground: NX.ink))
    }
}

/// A chevron toggle for a part of a section the inspector builds only when open.
private struct NXInspectorDisclosure: View {
    @Environment(\.nextStyle) private var style
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button { withAnimation(style.ease(220)) { isExpanded.toggle() } } label: {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 5,
                                        padding: EdgeInsets(top: 2, leading: 5, bottom: 2, trailing: 5),
                                        foreground: NX.ink(0.5), hoverForeground: NX.ink))
        .padding(.leading, -5)
    }
}

// MARK: - Planning

/// Calendar planning beyond the day toggle and estimate: why the plan falls
/// short, deferral, how sessions run and what has been recorded.
struct NXInspectorPlanOptions: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    let task: Block
    @State private var expanded = false
    @State private var deferring = false
    @State private var showsHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Only work you asked the calendar to hold can fall short; an
            // unplanned task just reads "Not in the calendar yet", as in the design.
            if env.workbench.isPlanned(task) || !env.store.placements(taskID: task.id).isEmpty,
               let assessment = env.calendar.plan.assessments.first(where: { $0.taskID == task.id }),
               assessment.status != .scheduled || !assessment.conflicts.isEmpty {
                shortfall(assessment)
            }
            if let deferred = task.deferredUntil {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.forward").font(.system(size: 10.5, weight: .semibold))
                    Text("Deferred until \(NXFormat.dueLabel(deferred))")
                    Spacer(minLength: 6)
                    NXInspectorLink(title: "Clear") { env.store.deselectForToday(task) }
                        .accessibilityLabel("Clear task deferral")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NX.ink(0.55))
            }
            NXInspectorDisclosure(title: "More options", isExpanded: $expanded)
            if expanded {
                options.transition(.opacity)
            }
        }
        .popover(isPresented: $deferring, arrowEdge: .bottom) { TaskDeferralPicker(block: task).environment(env) }
        .sheet(isPresented: $showsHistory) { CalendarHistoryView(taskID: task.id).environment(env) }
    }

    private func shortfall(_ assessment: TaskScheduleAssessment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(assessment.status.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(assessment.status == .cannotFitBeforeDeadline ? NX.amberText : NX.ink(0.66))
            Text("\(Int(assessment.beforeDeadlineMinutes.rounded())) of \(Int(assessment.requiredMinutes.rounded())) min covered · \(assessment.reason)")
                .font(.system(size: 11))
                .foregroundStyle(NX.ink(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Built only when expanded: the suggestion and recorded time read history.
    private var options: some View {
        let calendar = env.calendar
        let estimate = Int(calendar.estimatedMinutes(for: task))
        let personal = library.list(task.listID)?.availabilityCategoryRaw == "personal"
        return VStack(alignment: .leading, spacing: 9) {
            if let suggestion = env.store.suggestedDuration(for: task), suggestion.minutes != estimate {
                hint(suggestion.description, action: "Use \(suggestion.minutes) min") {
                    env.store.setTaskEstimate(suggestion.minutes, for: task)
                }
            }
            if task.schedulingEstimateMinutes != 0 {
                hint("This task has its own estimate.",
                     action: "Use default (\(Int(calendar.preferences.defaultEstimateMinutes)) min)") {
                    env.store.setTaskEstimate(0, for: task)
                }
            }
            toggle("Keep task together", isOn: task.keepsSessionsTogether) {
                env.store.setKeepTogether(!task.keepsSessionsTogether, for: task)
            }
            .help("Plan the remaining work as one block instead of splitting it")
            toggle("Track work away from this Mac", isOn: task.tracksAwayFromMac) {
                env.store.setTracksAway(!task.tracksAwayFromMac, for: task)
            }
            .help(task.tracksAwayFromMac ? "Tracking continues through lock or sleep."
                  : "Locking or sleeping pauses active work.")
            HStack(spacing: 6) {
                Image(systemName: personal ? "house" : "briefcase").font(.system(size: 10.5))
                Text("\(personal ? "Personal" : "Work") hours, from this task’s list")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NX.ink(0.45))
            HStack(spacing: 6) {
                if !task.isCompleted {
                    NXInspectorLink(title: "Defer…") { deferring = true }
                        .padding(.leading, -5)
                }
                Spacer(minLength: 6)
                Text("\(Int(calendar.trackedMinutes(for: task).rounded())) min recorded")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(NX.ink(0.45))
                NXInspectorLink(title: "History") { showsHistory = true }
                    .padding(.trailing, -5)
            }
        }
        .padding(.top, 9)
        .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.07)).frame(height: 0.5) }
    }

    private func hint(_ text: String, action title: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(NX.ink(0.5))
                .fixedSize(horizontal: false, vertical: true)
            NXInspectorLink(title: title, action: perform)
                .padding(.leading, -5)
        }
    }

    private func toggle(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(NX.ink(0.66))
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
                Text("Subtasks")
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(0.735)
                    .textCase(.uppercase)
                    .foregroundStyle(NX.ink(0.36))
                // Empty without subtasks, and still spaced, as the design's count is.
                Text(rows.isEmpty ? "" : "\(done)/\(rows.count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(NX.ink(0.45))
                    .monospacedDigit()
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(NX.ink(0.07))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(!rows.isEmpty && done == rows.count ? NX.green : style.accent)
                            .frame(width: proxy.size.width * fraction)
                    }
                    .animation(NX.cssEase(400), value: fraction)
                }
                .frame(height: 3)
            }
            // The design's line-height 1.
            .padding(.vertical, (10.5 - NXStrikeText.glyphLineHeight(10.5)) / 2)
            .padding(.bottom, 6)
            ForEach(rows) { row in
                NXInspectorSubtaskRow(row: row)
            }
            NXInspectorQuietAction(icon: "plus", title: "Add subtask", fills: true) { workbench.addSubtask(to: task.id) }
                .help("Add a subtask in the list")
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
            NXCheckbox(filled: filled, closing: closing, priority: .none, title: task.displayTitle, size: 15) {
                workbench.toggle(task.id)
            }
            // 400 13/1.3.
            Text(task.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 13))
                .foregroundStyle(filled ? NX.ink(0.42) : NX.ink)
                .strikethrough(filled, color: NX.ink(0.42))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.vertical, (13 * 1.3 - NXStrikeText.glyphLineHeight(13)) / 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(NX.ink(0.3))
                .frame(width: 14, height: 14)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(hovering ? NX.ink(0.04) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(closing != nil ? 0.6 : 1)
        .animation(.easeOut(duration: 0.3), value: closing != nil)
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
    @Environment(\.nextStyle) private var style
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
            .foregroundStyle(hovering ? style.accent : NX.ink(0.55))
            .padding(.top, 5)
            .padding(.bottom, 5)
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .background(hovering ? style.accent.opacity(0.1) : NX.ink(0.04),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .help("Show “\(parent.displayTitle)”")
        .accessibilityLabel("Subtask of \(parent.displayTitle)")
        // The design's -4 above and -8 below, so it sits close over the title.
        .padding(.top, -4)
        .padding(.bottom, -8)
    }
}

// MARK: - Files

/// Files kept with the task. The design has none, so the section shows only
/// once there are some; until then "Attach a file" sits by "Add a note",
/// while that stands in for the note. Files dropped anywhere on the panel
/// are attached too.
struct NXInspectorFiles: View {
    @Environment(AppEnvironment.self) private var env
    let task: Block
    /// Opens the note, while "Add a note" stands in for it.
    var addsNote: (() -> Void)?

    var body: some View {
        let attachments = env.store.attachments(for: task.id)
        let files = NXTaskFiles(store: env.store)
        if addsNote != nil || attachments.isEmpty {
            HStack(spacing: 2) {
                if let addsNote {
                    NXInspectorQuietAction(icon: "text.alignleft", title: "Add a note", action: addsNote)
                }
                if attachments.isEmpty {
                    NXInspectorQuietAction(icon: "paperclip", title: "Attach a file") { files.choose(for: task) }
                        .help("Attach files, or drop them on the panel")
                }
            }
            // The icons line up with the panel's edge.
            .padding(.leading, -8)
            .padding(.vertical, -6)
        }
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                NXInspectorHeading(title: "Files") {
                    Button { files.choose(for: task) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperclip").font(.system(size: 10.5, weight: .semibold))
                            Text("Attach")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 5,
                                                    padding: EdgeInsets(top: 2, leading: 5, bottom: 2, trailing: 5),
                                                    foreground: NX.ink(0.6), hoverForeground: NX.ink))
                    .padding(.trailing, -5)
                    .help("Attach files, or drop them on the panel")
                    .accessibilityLabel("Attach files to task")
                }
                ForEach(attachments) { attachment in
                    AttachmentRow(attachment: attachment) {
                        env.store.removeEditorMedia(filename: attachment.filename)
                        env.store.context.delete(attachment)
                        env.store.save()
                    }
                }
            }
        }
    }
}

/// Keeps files with a task, chosen in the Open panel or dropped.
struct NXTaskFiles {
    let store: Store

    func choose(for block: Block) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            attach(url: url, to: block)
        }
    }

    func drop(_ providers: [NSItemProvider], on blockID: UUID) -> Bool {
        // The provider calls back off the main actor, so carry the id rather
        // than the model object itself.
        let store = store
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    guard let target = store.block(id: blockID) else { return }
                    NXTaskFiles(store: store).attach(url: url, to: target)
                }
            }
        }
        return true
    }

    func attach(url: URL, to block: Block) {
        do {
            let media = try MediaStore.shared.importFile(at: url)
            let existing = store.attachments(for: block.id)
            let attachment = Attachment(
                blockID: block.id,
                filename: media.filename,
                displayName: media.displayName,
                contentType: media.contentType,
                byteCount: media.byteCount,
                sortIndex: (existing.last?.sortIndex ?? 0) + BlockTree.indexStep,
                contentData: media.data
            )
            store.context.insert(attachment)
            store.save()
        } catch {
            MarkdownExporter.presentError(error, operation: "Import attachment")
        }
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
            NXInspectorDisclosure(title: "Full history", isExpanded: $expanded)
                .help("Newest first. Clearing activity history in Settings › Data also clears this.")
            // Queried only when open, like the legacy Activity disclosure.
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Created \(Store.absoluteDateText(task.createdAt, includesTime: true))")
                        if let completedAt = task.completedAt {
                            Text("Completed \(Store.absoluteDateText(completedAt, includesTime: true))")
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NX.ink(0.45))
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
        // Exclude before applying the limit, so failed attempts can't use up
        // a page or hide Load older activity.
        var descriptor = FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.blockID == taskID && !excluded.contains($0.id) },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.id)])
        descriptor.fetchLimit = limit + 1
        _events = Query(descriptor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if events.isEmpty {
                Text("No recorded activity for this task.")
                    .font(.system(size: 12))
                    .foregroundStyle(NX.ink(0.45))
                    .padding(.vertical, 5)
            } else {
                ForEach(events.prefix(limit)) { event in
                    row(event)
                }
                if events.count > limit {
                    NXInspectorLink(title: "Load older activity", action: loadOlder)
                        .padding(.leading, -5)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func row(_ event: ActivityEvent) -> some View {
        let place = [event.listIcon, event.listTitle].filter { !$0.isEmpty }.joined(separator: " ")
        let when = event.timestamp.formatted(date: .abbreviated, time: .shortened)
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: event.kind.symbol).font(.system(size: 11.5, weight: .medium)).foregroundStyle(NX.ink(0.4)).frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(event.kind.verb) “\(event.title)”")
                    .font(.system(size: 12))
                    .foregroundStyle(NX.ink(0.66))
                if !event.recordedDetail.isEmpty {
                    Text(event.recordedDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(NX.ink(0.5))
                }
                Text(place.isEmpty ? when : "\(when) · \(place)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NX.ink(0.36))
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
