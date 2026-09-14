import SwiftUI

struct ActivityHeatmapCell: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let day: ActivityHeatmapDay
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Text(day.count == 0 ? "–" : day.count.formatted())
                .font(.caption).monospacedDigit()
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.chip)
                        .fill(day.count == 0 ? Theme.chipFill : Theme.accent.opacity([0, 0.15, 0.3, 0.55, 0.8][day.intensity]))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.chip)
                        .strokeBorder(isSelected ? Color.primary : Theme.separator, lineWidth: isSelected || contrast == .increased ? 2 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.accessibilityDescription)
        .accessibilityHint("Show the recorded completions for this day")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(day.accessibilityDescription)
        .accessibilityIdentifier("activity-day-\(day.id.timeIntervalSince1970)")
    }
}
