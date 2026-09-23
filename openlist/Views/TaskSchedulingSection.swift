import SwiftData
import SwiftUI

/// Scheduling intent stays separate from a task's due date and existing starred state.
struct TaskSchedulingSection: View {
    let block: Block
    @Environment(AppEnvironment.self) private var env
    @State private var showsDeferral = false
    @State private var showsHistory = false
    private var selectedToday: Bool { block.selectedForDay.map { Calendar.current.startOfDay(for: $0) <= Calendar.current.startOfDay(for: .now) } ?? false }
    private var isActive: Bool { env.calendar.activeSession?.taskID == block.id }
    private var assessment: TaskScheduleAssessment? { env.calendar.plan.assessments.first { $0.taskID == block.id } }

    var body: some View {
        // SwiftUI may update this child after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { liveContent }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Plan for today", isOn: Binding(get: { selectedToday }, set: { value in
                    if value { env.store.selectForToday(block) } else { env.store.deselectForToday(block) }
                    env.calendar.storeDidChange()
                }))
                .disabled(block.isCompleted)
                Button { env.navigator.go(to: .calendar) } label: { Image(systemName: "arrow.up.right") }
                    .buttonStyle(.plain).help("Open calendar").accessibilityLabel("Open calendar")
            }
            HStack {
                Text("Estimate")
                Spacer()
                TextField("Minutes", value: Binding(get: { Int(env.calendar.estimatedMinutes(for: block)) }, set: { value in
                    env.store.setTaskEstimate(max(1, min(100_800, value)), for: block)
                    env.calendar.storeDidChange()
                }), format: .number)
                .labelsHidden()
                .textFieldStyle(.roundedBorder).frame(width: 60).multilineTextAlignment(.trailing)
                .accessibilityLabel("Task estimate in minutes")
                Text("min").foregroundStyle(Theme.secondaryText)
            }
            if block.schedulingEstimateMinutes != 0 {
                Button("Use default (\(Int(env.calendar.preferences.defaultEstimateMinutes)) min)") {
                    env.store.setTaskEstimate(0, for: block); env.calendar.storeDidChange()
                }.buttonStyle(.link).font(.caption)
            }
            if let suggestion = env.store.suggestedDuration(for: block), suggestion.minutes != Int(env.calendar.estimatedMinutes(for: block)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(suggestion.description).font(.caption).foregroundStyle(Theme.secondaryText)
                    Button("Apply suggested \(suggestion.minutes) minutes") {
                        env.store.setTaskEstimate(suggestion.minutes, for: block); env.calendar.storeDidChange()
                    }.font(.caption)
                }
                .padding(8).background(Theme.rowSelected, in: RoundedRectangle(cornerRadius: 7))
            }
            Toggle("Keep task together", isOn: Binding(get: { block.keepsSessionsTogether }, set: {
                env.store.setKeepTogether($0, for: block); env.calendar.storeDidChange()
            }))
            Toggle("Track work away from this Mac", isOn: Binding(get: { block.tracksAwayFromMac }, set: {
                env.store.setTracksAway($0, for: block)
            }))
            .help(block.tracksAwayFromMac ? "Tracking continues through lock or sleep." : "Locking or sleeping pauses active work.")
            HStack {
                let category = env.store.list(id: block.listID)?.availabilityCategoryRaw == "personal" ? "Personal" : "Work"
                Label("\(category) hours", systemImage: category == "Personal" ? "house" : "briefcase")
                Spacer()
                Image(systemName: "square.stack").help("Inherited from this task's list")
            }.font(.caption).foregroundStyle(Theme.secondaryText)
            if let assessment {
                VStack(alignment: .leading, spacing: 3) {
                    Text(assessment.status.title).font(.caption.weight(.semibold))
                        .foregroundStyle(assessment.status == .cannotFitBeforeDeadline ? ListAccent.orange.color : Theme.accent)
                    Text("\(Int(assessment.beforeDeadlineMinutes.rounded())) of \(Int(assessment.requiredMinutes.rounded())) min covered")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                    if assessment.status != .scheduled || !assessment.conflicts.isEmpty { Text(assessment.reason).font(.caption).foregroundStyle(Theme.secondaryText) }
                }
            }
            if let deferred = block.deferredUntil {
                HStack {
                    Text("Deferred until \(deferred.formatted(date: .abbreviated, time: .omitted))")
                    Spacer(minLength: 0)
                    Button("Clear") { env.store.deselectForToday(block) }
                        .buttonStyle(.link).accessibilityLabel("Clear task deferral")
                }.font(.caption).foregroundStyle(Theme.secondaryText)
            }
            if !block.isCompleted {
                HStack(spacing: 8) {
                    Button {
                        if isActive { env.calendar.stopWorking() } else { env.calendar.requestWork(WorkTaskReference(block)) }
                    } label: { Label(isActive ? "Stop working" : "Start working", systemImage: isActive ? "pause.fill" : "play.fill") }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    Button("Defer…") { showsDeferral = true }
                    Spacer(minLength: 0)
                }
            }
            HStack {
                Text("\(env.calendar.trackedMinutes(for: block).formatted(.number.precision(.fractionLength(0)))) min recorded")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                Spacer()
                Button("History") { showsHistory = true }.buttonStyle(.link).font(.caption)
            }
        }
        .font(Theme.Font.body)
        .padding(12).background(Theme.canvas.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
        .popover(isPresented: $showsDeferral) { TaskDeferralPicker(block: block) }
        .sheet(isPresented: $showsHistory) { CalendarHistoryView(taskID: block.id) }
    }
}

struct TaskDeferralPicker: View {
    let block: Block
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    var body: some View {
        // SwiftUI may update this child after a saved deletion, before its
        // parent removes it. Never read persisted fields on that old model.
        if block.modelContext != nil, !block.isDeleted { liveContent }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Defer work").font(.headline)
            Text(block.displayTitle).lineLimit(2)
            DatePicker("Resume planning on", selection: $date, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
            Text("Remaining work will use the next available time on or after this day. The due date stays the same.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Defer") { env.calendar.deferTask(task: block, to: date); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(16).frame(width: 320)
    }
}
