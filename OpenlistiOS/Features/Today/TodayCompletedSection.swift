import SwiftUI

struct TodayCompletedSection: View {
    let rows: [BlockRow]
    let additional: [ActivityCompletion]
    let day: Date
    let isToday: Bool
    let subtitle: (Block, Set<UUID>) -> String?
    @State private var isExpanded = false
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let visibleIDs = Set(rows.lazy.map(\.id))
        let items = rows.map(Item.task) + additional.map(Item.savedCompletion)
        OLFold(isToday ? "completed today" : "completed", count: items.count, identifier: "today.done", isExpanded: $isExpanded) {
            OLCardRows(items, depth: \.depth, shadow: .softCard) { item, separator in
                switch item {
                case let .task(row):
                    PhoneTaskRow(task: row.block, context: .today, depth: row.depth,
                                 subtitle: subtitle(row.block, visibleIDs), separator: separator, agendaDay: day)
                case let .savedCompletion(completion):
                    TodaySavedCompletionRow(completion: completion, separator: separator)
                }
            }
            OLLinkRow("View Activity", topSpacing: 8) { env.navigator.open(.activity) }
                .accessibilityIdentifier("today.activity")
        }
    }

    private enum Item: Identifiable {
        case task(BlockRow)
        case savedCompletion(ActivityCompletion)

        enum ID: Hashable {
            case task(UUID)
            case savedCompletion(UUID)
        }

        var id: ID {
            switch self {
            case let .task(row): .task(row.id)
            case let .savedCompletion(completion): .savedCompletion(completion.id)
            }
        }

        var depth: Int {
            switch self {
            case let .task(row): row.depth
            case .savedCompletion: 0
            }
        }
    }
}
