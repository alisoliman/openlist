import SwiftUI

struct ActivityHeatmapLegend: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text("Recorded completions").font(.callout)
                legend
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Recorded completions").font(.callout)
                legend
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(0..<5) { level in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(level == 0 ? Theme.chipFill : Theme.accent.opacity([0, 0.15, 0.3, 0.55, 0.8][level]))
                        .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.separator) }
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    Text(["– unavailable", "1", "2–3", "4–6", "7+"][level]).font(.callout)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: dash, count unavailable; 1; 2 to 3; 4 to 6; 7 or more recorded completions")
    }
}
