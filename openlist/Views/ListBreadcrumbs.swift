import SwiftData
import SwiftUI

struct ListBreadcrumbs: View {
    let list: TaskList
    @Environment(AppEnvironment.self) private var env
    @Query private var lists: [TaskList]

    var body: some View {
        let hierarchy = ListHierarchy(lists)
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    Button("Lists") { env.navigator.go(to: .lists) }
                    ForEach(hierarchy.ancestors(of: list.id)) { ancestor in
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                        Button(ancestor.displayTitle) { env.navigator.go(to: .list(ancestor.id)) }
                    }
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                    Text(list.displayTitle).foregroundStyle(Theme.secondaryText)
                }
                .font(.callout)
                .buttonStyle(.plain)
            }
            .scrollIndicators(.hidden)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("List location")
            if let context = hierarchy.recoveryContext(for: list.id) {
                Text(context).font(.callout).foregroundStyle(Theme.secondaryText)
            }
            if hierarchy.isArchived(list.id) {
                Label(list.isArchived ? "Archived list" : "Archived through its parent list", systemImage: "archivebox")
                    .font(.callout).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
