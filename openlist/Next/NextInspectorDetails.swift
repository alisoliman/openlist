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
            if let assessment = env.calendar.plan.assessments.first(where: { $0.taskID == task.id }),
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

/// The task's own outline, drawn by the same editor a list uses.
struct NXInspectorSubtasks: View {
    @Environment(AppEnvironment.self) private var env
    let task: Block

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NXInspectorHeading(title: "Subtasks") {
                if let progress = env.store.subtaskProgress(for: task) {
                    SubtaskProgressChip(done: progress.done, total: progress.total)
                }
            }
            DocumentView(
                document: DocumentContext(listID: task.listID ?? UUID(), rootBlockID: task.id),
                emptyPlaceholder: "Add a subtask…",
                showsCompleted: true,
                seedsEmptyBlock: false,
                appendButtonTitle: "Add subtask"
            )
            .id(task.id)
        }
    }
}

// MARK: - Files

/// Files kept with the task. Attach with the button or drop them on the section.
struct NXInspectorFiles: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let task: Block
    @State private var dropTargeted = false

    var body: some View {
        let attachments = env.store.attachments(for: task.id)
        VStack(alignment: .leading, spacing: 4) {
            NXInspectorHeading(title: "Files") {
                Button { presentFilePicker() } label: {
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
                .help("Attach files")
                .accessibilityLabel("Attach files to task")
            }
            if attachments.isEmpty {
                Text("Drop files here to keep them with the task")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NX.ink(0.36))
                    .padding(.vertical, 4)
            } else {
                ForEach(attachments) { attachment in
                    AttachmentRow(attachment: attachment) {
                        env.store.removeEditorMedia(filename: attachment.filename)
                        env.store.context.delete(attachment)
                        env.store.save()
                    }
                }
            }
        }
        .padding(6)
        .background(dropTargeted ? style.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(style.accent.opacity(0.5), lineWidth: 1)
            }
        }
        .padding(-6)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            // The provider calls back off the main actor, so carry the id
            // rather than the model object itself.
            let blockID = task.id
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        guard let target = env.store.block(id: blockID) else { return }
                        attach(url: url, to: target)
                    }
                }
            }
            return true
        }
    }

    private func presentFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            attach(url: url, to: task)
        }
    }

    private func attach(url: URL, to block: Block) {
        do {
            let media = try MediaStore.shared.importFile(at: url)
            let existing = env.store.attachments(for: block.id)
            let attachment = Attachment(
                blockID: block.id,
                filename: media.filename,
                displayName: media.displayName,
                contentType: media.contentType,
                byteCount: media.byteCount,
                sortIndex: (existing.last?.sortIndex ?? 0) + BlockTree.indexStep,
                contentData: media.data
            )
            env.store.context.insert(attachment)
            env.store.save()
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
                .help("Newest first. Clear History in Updates also clears task activity.")
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
