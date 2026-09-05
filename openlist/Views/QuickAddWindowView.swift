//
//  QuickAddWindowView.swift
//  openlist
//

import SwiftUI

/// The floating capture panel opened by ⇧⌥Space or the menu bar.
///
/// It is deliberately one field: type, optionally pick a list, press Return.
struct QuickAddWindowView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var text = ""
    @State private var destinationID: UUID?
    @State private var justSaved = false
    @FocusState private var isFocused: Bool

    private var parsed: ParsedSchedule {
        env.settings.parsesNaturalLanguageDates
            ? DateParser.parse(text)
            : ParsedSchedule(cleanedText: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.accent)

                TextField("What needs doing?", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($isFocused)
                    .onSubmit(save)
                    .onKeyPress(.escape) {
                        close()
                        return .handled
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            HStack(spacing: 8) {
                Menu {
                    ForEach(env.store.allLists()) { list in
                        Button("\(list.icon)  \(list.displayTitle)") {
                            destinationID = list.id
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(destinationList?.icon ?? "📥")
                            .font(.system(size: 10))
                        Text(destinationList?.displayTitle ?? "Inbox")
                            .font(Theme.Font.metadata)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if let date = parsed.date {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9))
                        Text(
                            parsed.includesTime
                                ? date.formatted(date: .abbreviated, time: .shortened)
                                : date.formatted(date: .abbreviated, time: .omitted)
                        )
                    }
                    .chipStyle(accent: Theme.accent)
                }

                if let recurrence = parsed.recurrence {
                    HStack(spacing: 3) {
                        Image(systemName: "repeat")
                            .font(.system(size: 9))
                        Text(recurrence.displayText)
                    }
                    .chipStyle(accent: Theme.accent)
                }

                Spacer()

                if justSaved {
                    Text("Added")
                        .font(Theme.Font.metadata)
                        .foregroundStyle(ListAccent.green.color)
                        .transition(.opacity)
                }

                Text("↩ to add · esc to close")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .frame(width: 520)
        .background(.regularMaterial)
        .onAppear {
            isFocused = true
            if destinationID == nil { destinationID = env.store.inboxList()?.id }
        }
    }

    private var destinationList: TaskList? {
        env.store.list(id: destinationID) ?? env.store.inboxList()
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let list = destinationList else { return }

        env.store.captureTask(text: trimmed, in: list, defaults: env.captureDefaults)

        text = ""
        withAnimation { justSaved = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { justSaved = false }
        }
    }

    private func close() {
        text = ""
        dismissWindow(id: WindowID.quickAdd)
    }
}
