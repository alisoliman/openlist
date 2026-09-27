//
//  SettingsScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// Settings (mockup 15), a sheet with its own stack. The shell's stub: the
/// Settings feature adds every row.
struct SettingsScreen: View {
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        let navigator = env.navigator
        OLScreen(identifier: PhoneRoute.settings.screenIdentifier) {
            OLTopBar {
                EmptyView()
            } trailing: {
                Button("Done") { navigator.dismissSheet() }
                    .buttonStyle(.olLink(strong: true))
                    .accessibilityIdentifier("settings.done")
            }
        } content: {
            OLHeader("Settings")
            FeaturePlaceholder(summary: "Every setting comes with the Settings feature.", links: links(navigator))
        }
    }

    private func links(_ navigator: PhoneNavigator) -> [FeaturePlaceholder.Link] {
        var links: [FeaturePlaceholder.Link] = [
            .init("Activity", symbol: "waveform.path.ecg", route: .activity, navigator: navigator),
            .init("Trash", symbol: "trash", route: .trash, navigator: navigator),
        ]
        #if DEBUG
        links.append(.init(title: "Component gallery", symbol: "square.grid.3x3") { navigator.showComponentGallery() })
        #endif
        return links
    }
}
