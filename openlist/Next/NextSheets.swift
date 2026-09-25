//
//  NextSheets.swift
//  openlist
//

import SwiftUI

/// Format ▸ Add Link… (⌘L), for the text selected in a list document line: a
/// Next sheet like Move List's, with the URL field prefilled with the link it
/// has, or "https://". Return applies and Esc cancels; Remove link shows only
/// when there is a link to remove. A native extra: the design has no links.
struct NXLinkSheet: View {
    let prompt: LinkPrompt
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String

    init(prompt: LinkPrompt) {
        self.prompt = prompt
        _draft = State(initialValue: prompt.currentURL.isEmpty ? "https://" : prompt.currentURL)
    }

    var body: some View {
        let style = env.workbench.style
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                NXPanelTitle(prompt.currentURL.isEmpty ? "Add link" : "Edit link")
                Text("For “\(prompt.text)”")
                    .font(.system(size: 12.5))
                    .foregroundStyle(NX.ink(0.55))
                    .lineLimit(2)
            }
            NXPanelField(icon: "link") {
                TextField("Link URL", text: $draft, prompt: Text(verbatim: "https://example.com"))
            }
            HStack(spacing: 8) {
                // Grey, as Remove reminder: it takes the link off the text,
                // which ⌘Z puts back, and red is for deleting things.
                if !prompt.currentURL.isEmpty {
                    Button("Remove link") { answer(.remove) }
                        .buttonStyle(NXPanelButtonStyle(kind: .secondary))
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(NXPanelButtonStyle(kind: .secondary))
                Button("Apply") { answer(.apply(draft)) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(NXPanelButtonStyle(kind: .primary))
                    .disabled(BlockNSTextView.linkURL(from: draft) == nil)
            }
        }
        .padding(24)
        .frame(width: 430)
        .presentationBackground(NX.card)
        .tint(style.accent)
        // Presented from the window, outside the Next shell's style.
        .environment(\.nextStyle, style)
    }

    private func answer(_ answer: LinkPrompt.Answer) {
        dismiss()
        prompt.answer(answer)
    }
}
