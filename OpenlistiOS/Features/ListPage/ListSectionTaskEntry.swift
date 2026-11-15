import SwiftUI

/// A section footer that stays in the document while the next task is typed.
struct ListSectionTaskEntry: View {
    let headingID: UUID
    let headingTitle: String
    @Binding var activeSection: UUID?
    @Binding var draft: String
    let addTask: (String) -> Bool
    @FocusState private var isFocused: Bool

    private var title: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isActive: Bool { activeSection == headingID }

    var body: some View {
        Group {
            if isActive {
                HStack(spacing: 6) {
                    TextField("Task name", text: $draft, prompt: Text("Task name").foregroundStyle(OL.muted))
                        .font(OLFont.rowTitle)
                        .padding(.leading, 14)
                        .frame(minHeight: 44)
                        .focused($isFocused)
                        .submitLabel(.next)
                        .onSubmit(submit)
                        .task { isFocused = true }
                        .accessibilityLabel("Task name under \(headingTitle)")
                        .accessibilityIdentifier("list.inlineTaskField")
                    Button(action: submit) {
                        Image(systemName: title.isEmpty ? "xmark" : "arrow.up.circle.fill")
                            .font(.system(size: title.isEmpty ? 14 : 25, weight: .semibold))
                            .foregroundStyle(title.isEmpty ? OL.muted : OL.accentText)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(OLPressStyle())
                    .accessibilityLabel(title.isEmpty ? "Close task entry" : "Add task")
                }
            } else {
                Button { activeSection = headingID } label: {
                    Label(title.isEmpty ? "Add task" : "Continue task", systemImage: "plus")
                        .font(OLFont.note)
                        .foregroundStyle(OL.muted)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(OLPressStyle())
                .accessibilityLabel(title.isEmpty ? "Add task under \(headingTitle)" : "Continue task under \(headingTitle)")
                .accessibilityIdentifier("list.inlineAdd.\(headingID)")
            }
        }
        .background(OL.sunken, in: .rect(cornerRadius: 14))
        .overlay {
            if isActive && isFocused {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(OL.accentText.opacity(0.55))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func submit() {
        if title.isEmpty {
            draft = ""
            isFocused = false
            activeSection = nil
        } else if addTask(title) {
            draft = ""
            isFocused = true
        }
    }
}
