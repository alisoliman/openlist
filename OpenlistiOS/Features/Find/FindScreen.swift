//
//  FindScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// Find (mockup 13), pushed from Lists. The shell's stub: the Find feature
/// adds tokens, filters and results.
struct FindScreen: View {
    let query: String
    @Environment(PhoneEnvironment.self) private var env
    @State private var text: String

    init(query: String) {
        self.query = query
        _text = State(initialValue: query)
    }

    var body: some View {
        let navigator = env.navigator
        OLScreen(identifier: PhoneRoute.find(query).screenIdentifier) {
            OLTopBar { OLBackButton(env.backTitle(for: .find(query))) { navigator.pop() } }
        } content: {
            OLHeader("Find")
            OLSearchField(text: $text, prompt: "Add words or filters")
                .padding(.top, OLMetrics.headerGap)
            OLFlowLayout {
                ForEach(["today", "overdue", "starred", "done"], id: \.self) { OLChip($0, small: true) }
            }
            .padding(.top, 12)
            FeaturePlaceholder(summary: "Results come with the Find feature.")
        }
    }
}
