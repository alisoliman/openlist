import SwiftUI

/// Page identity reads vertically, while actions keep their own space above
/// the heading so long titles use the full content width.
struct ScreenHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    var isEmoji: Bool = false
    var accent: ListAccent?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Group {
                    if isEmoji {
                        Text(icon)
                            .font(.system(size: 24))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(accent?.color ?? Theme.accent)
                    }
                }
                .accessibilityHidden(true)

                Spacer(minLength: 12)
                trailing()
            }
            .frame(minHeight: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Font.documentTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil, isEmoji: Bool = false, accent: ListAccent? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle, isEmoji: isEmoji, accent: accent) { EmptyView() }
    }
}
