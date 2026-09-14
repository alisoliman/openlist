import SwiftData
import SwiftUI

struct TaskActivitySection: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let taskID: UUID
    var createdAt: Date?
    var completedAt: Date?
    @State private var isExpanded = false
    @State private var limit = 50

    var body: some View {
        DisclosureGroup("Activity", isExpanded: $isExpanded) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if let createdAt {
                        Text("Created \(Store.absoluteDateText(createdAt, includesTime: true))")
                    }
                    if let completedAt {
                        Text("Completed \(Store.absoluteDateText(completedAt, includesTime: true))")
                    }
                }
                .font(Theme.Font.metadata)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 8)
                TaskActivityPage(taskID: taskID, limit: limit, excluded: Array(env.store.uncommittedActivityIDs)) { limit += 50 }
                    .padding(.top, 8)
            }
        }
        .font(Theme.Font.body)
        .accessibilityIdentifier("task-activity")
        .help("Newest first. Clear History in Updates also clears task activity.")
        .transaction {
            if !Theme.Motion.allowsAnimation(reduceMotion: reduceMotion, eventType: NSApp.currentEvent?.type) {
                $0.disablesAnimations = true
            }
        }
    }
}

private struct TaskActivityPage: View {
    let limit: Int
    let loadOlder: () -> Void
    @Query private var events: [ActivityEvent]

    init(taskID: UUID, limit: Int, excluded: [UUID], loadOlder: @escaping () -> Void) {
        self.limit = limit
        self.loadOlder = loadOlder
        // Exclude before applying the limit so failed attempts cannot consume
        // a page or hide the Load older activity control.
        var descriptor = FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.blockID == taskID && !excluded.contains($0.id) },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.id)])
        descriptor.fetchLimit = limit + 1
        _events = Query(descriptor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if events.isEmpty {
                Text("No recorded activity for this task.")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(events.prefix(limit)) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: event.kind.symbol)
                            .foregroundStyle(event.kind.accent.color)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(event.kind.verb) “\(event.title)”").font(.callout.weight(.medium))
                            Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                                .font(Theme.Font.metadata).foregroundStyle(Theme.secondaryText)
                            if !event.recordedDetail.isEmpty { Text(event.recordedDetail).font(.callout) }
                            if !event.listTitle.isEmpty {
                                Text("\(event.listIcon) \(event.listTitle)")
                                    .font(Theme.Font.metadata).foregroundStyle(Theme.tertiaryText)
                            }
                        }
                        .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
                if events.count > limit {
                    Button("Load older activity", action: loadOlder)
                        .accessibilityIdentifier("task-activity-load-older")
                }
            }
            Text("Older events may have fewer details.")
                .font(Theme.Font.metadata).foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
