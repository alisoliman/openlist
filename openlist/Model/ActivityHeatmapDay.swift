import Foundation

nonisolated struct ActivityHeatmapDay: Identifiable, Equatable, Sendable {
    var id: Date
    var completions: [ActivityCompletion]
    var unclassifiedCount: Int

    var count: Int { completions.count }

    var countDescription: String {
        count == 0 ? "No count available" : "\(count) recorded completion\(count == 1 ? "" : "s")"
    }

    var accessibilityDescription: String {
        "\(id.formatted(date: .complete, time: .omitted)). \(countDescription). History may be incomplete."
            + (unclassifiedCount > 0 ? " \(unclassifiedCount) completion entries have missing or conflicting counting details." : "")
    }
}
