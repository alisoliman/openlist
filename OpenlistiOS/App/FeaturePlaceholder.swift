//
//  FeaturePlaceholder.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI

/// What a feature's screen shows until the feature is built: the shell's
/// chrome is real, and the card lists the screens this one leads to, so the
/// navigation can be walked end to end. Each feature replaces its screen's
/// body with the real thing and drops this.
struct FeaturePlaceholder: View {
    struct Link: Identifiable {
        let title: String
        let symbol: String
        let action: () -> Void
        var id: String { title }
    }

    let summary: String
    var links: [Link] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(summary)
                .font(OLFont.note)
                .foregroundStyle(OL.muted)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                Button(action: link.action) {
                    OLSettingsRow(link.title, tile: .accent(link.symbol), separator: index == 0 ? .inset(16) : .settings) {
                        OLRowValue(nil)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(OLRowPressStyle())
            }
        }
        .olCard()
        .padding(.top, OLMetrics.headerGap)
    }
}

extension FeaturePlaceholder.Link {
    init(_ title: String, symbol: String, route: PhoneRoute, navigator: PhoneNavigator) {
        self.init(title: title, symbol: symbol) { navigator.open(route) }
    }
}

extension FeaturePlaceholder {
    /// A link to a task, for walking to Task detail: the one planned for
    /// today first, in `listID` when given.
    static func firstTask(in env: PhoneEnvironment, listID: UUID? = nil) -> [Link] {
        let kind = BlockKind.task.rawValue
        let open = (try? env.store.context.fetch(FetchDescriptor<Block>(
            predicate: #Predicate { $0.kindRaw == kind && !$0.isCompleted && $0.trashID == nil },
            sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let candidates = open.filter { task in
            env.store.block(id: task.id) != nil && (listID.map { task.listID == $0 } ?? true)
        }
        guard let task = candidates.first(where: { $0.selectedForDay != nil }) ?? candidates.first else { return [] }
        let navigator = env.navigator
        return [Link(title: task.displayTitle, symbol: "doc.text") { navigator.open(.taskDetail(task.id)) }]
    }
}
