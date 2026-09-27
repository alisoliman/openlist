//
//  SelectMode.swift
//  OpenlistiOS
//

import SwiftUI

/// Select many (mockup 11): a mode of a list's page, whose bulk bar takes the
/// dock's place. The shell's stub: the Lists feature adds the selection and
/// what each action does.
struct SelectMode: ViewModifier {
    @Binding var isSelecting: Bool
    let listTitle: String
    @Environment(PhoneEnvironment.self) private var env
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .overlay {
                if isSelecting {
                    OLScreen(identifier: "screen.select") {
                        OLTopBar {
                            Button("Select all") {}.buttonStyle(.olLink())
                        } trailing: {
                            Button("Done") { isSelecting = false }.buttonStyle(.olLink(strong: true))
                        }
                    } content: {
                        OLHeader("0 selected", sub: listTitle)
                        FeaturePlaceholder(summary: "Selecting tasks comes with the Lists feature.")
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        OLBulkBar(actions: [
                            .init(symbol: "checkmark", label: "Mark done", isEnabled: false) {},
                            .init(symbol: "sun.max", label: "Move to today", isEnabled: false) {},
                            .init(symbol: "arrow.right", label: "Move to tomorrow", isEnabled: false) {},
                            .init(symbol: "square.grid.2x2", label: "Move to another list", isEnabled: false) {},
                            .init(symbol: "trash", label: "Move to Trash", isEnabled: false) {},
                        ])
                    }
                }
            }
            .onChange(of: isSelecting, initial: true) { _, selecting in env.navigator.hidesDock(selecting, for: token) }
            .onDisappear { env.navigator.hidesDock(false, for: token) }
    }
}
