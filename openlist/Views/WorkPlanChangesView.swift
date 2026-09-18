import SwiftUI

struct WorkPlanChangesView: View {
    let changes: [WorkPlanChange]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(changes) { change in
                VStack(alignment: .leading, spacing: 3) {
                    Text(change.title).font(.callout.weight(.medium))
                    Text("\(change.previousStart.formatted(date: .abbreviated, time: .shortened)) → \(change.proposedStart?.formatted(date: .abbreviated, time: .shortened) ?? "No available slot")")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }.accessibilityElement(children: .combine)
            }
        }
    }
}
