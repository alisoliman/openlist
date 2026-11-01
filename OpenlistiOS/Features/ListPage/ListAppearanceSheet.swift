//
//  ListAppearanceSheet.swift
//  OpenlistiOS
//

import SwiftUI
import UIKit

/// A list's Icon & colour, from its page's tile or menu, as the Mac's Icon &
/// Colour: the suggested emoji, any other from the emoji keyboard, and the
/// list colours. Each pick shows on the page at once, one step with Undo.
struct ListAppearanceSheet: View {
    let list: TaskList
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)

    var body: some View {
        let glyph = list.glyph
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Icon & colour").font(OLFont.linkStrong)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.olLink(strong: true))
            }
            .padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    OLGroup("Icon", topSpacing: 12) {
                        VStack(spacing: 0) {
                            LazyVGrid(columns: Self.columns, spacing: 4) {
                                ForEach(ListIcon.suggestions, id: \.self) { emoji in
                                    Button { env.actions.setAppearance(icon: emoji, for: list) } label: {
                                        EmojiCell(emoji: emoji, isOn: glyph == emoji)
                                    }
                                    .buttonStyle(OLPressStyle())
                                    .accessibilityAddTraits(glyph == emoji ? .isSelected : [])
                                    .accessibilityIdentifier("appearance.icon.\(emoji)")
                                }
                            }
                            .padding(10)
                            .olFeedback(.selection, trigger: glyph)
                            otherEmoji(glyph)
                        }
                        .olCard()
                    }
                    OLGroup("Colour") {
                        LazyVGrid(columns: Self.columns, spacing: 4) {
                            ForEach(ListAccent.allCases) { accent in
                                let isOn = list.accent == accent
                                Button { env.actions.setAppearance(accent: accent, for: list) } label: {
                                    Circle()
                                        .fill(accent.color)
                                        .frame(width: 30, height: 30)
                                        .overlay(Circle().strokeBorder(OL.ink, lineWidth: 2).padding(-4).opacity(isOn ? 1 : 0))
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(OLPressStyle())
                                .accessibilityLabel(accent.title)
                                .accessibilityAddTraits(isOn ? .isSelected : [])
                                .accessibilityIdentifier("appearance.colour.\(accent.rawValue)")
                            }
                        }
                        .padding(10)
                        .olCard()
                        .olFeedback(.selection, trigger: list.accent)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The emoji keyboard has no key that puts it away.
            .scrollDismissesKeyboard(.immediately)
            .accessibilityIdentifier("appearance.scroll")
        }
        .padding(.horizontal, OLMetrics.gutter)
        .presentationDetents([.medium, .large])
        .olSheet()
    }

    /// Any emoji the suggestions don't have, from the emoji keyboard, with
    /// the list's own beside it while it's one of those.
    private func otherEmoji(_ glyph: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "face.smiling").foregroundStyle(OL.muted)
            EmojiField(prompt: "Any emoji") { env.actions.setAppearance(icon: $0, for: list) }
                .frame(maxWidth: .infinity)
            if !ListIcon.suggestions.contains(glyph), !ListIcon.isSymbolName(glyph) {
                EmojiCell(emoji: glyph, isOn: true)
                    .frame(width: 48)
                    .accessibilityAddTraits(.isSelected)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(minHeight: 52)
        .overlay(alignment: .top) { OLSeparatorLine(separator: .inset(16)) }
    }
}

/// An emoji to pick, ringed in ink while it's the list's.
private struct EmojiCell: View {
    let emoji: String
    let isOn: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Text(emoji)
            .font(.system(size: 26))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background { if isOn { shape.fill(OL.sunken) } }
            .overlay { if isOn { shape.strokeBorder(OL.ink, lineWidth: 2) } }
            .contentShape(shape)
    }
}

/// A field that opens on the emoji keyboard, where the phone has one. An
/// emoji typed or pasted goes to `pick`, and the field empties and puts the
/// keyboard away, so the pick shows; whatever isn't one doesn't stay.
private struct EmojiField: UIViewRepresentable {
    let prompt: String
    let pick: (String) -> Void

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.placeholder = prompt
        field.font = .preferredFont(forTextStyle: .callout)
        field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .done
        field.accessibilityIdentifier = "appearance.emoji"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: EmojiTextField, context: Context) {
        context.coordinator.pick = pick
    }

    func makeCoordinator() -> Coordinator { Coordinator(pick: pick) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var pick: (String) -> Void

        init(pick: @escaping (String) -> Void) { self.pick = pick }

        @objc func changed(_ field: UITextField) {
            // Not while a keyboard is still composing what it will insert.
            guard let text = field.text, !text.isEmpty, field.markedTextRange == nil else { return }
            field.text = ""
            guard let emoji = ListIcon.emoji(in: text) else { return }
            pick(emoji)
            field.resignFirstResponder()
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            return false
        }
    }
}

/// Asks for the emoji keyboard rather than the one last used.
private final class EmojiTextField: UITextField {
    // A context of its own is what lets the field choose its keyboard.
    override var textInputContextIdentifier: String? { "" }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}
