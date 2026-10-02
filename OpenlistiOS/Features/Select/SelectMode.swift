//
//  SelectMode.swift
//  OpenlistiOS
//

import SwiftUI

/// Select many (mockup 11): a mode of a list's page, its open tasks in one
/// run to pick from, and the bulk bar in the dock's place: Mark done, Move to
/// today, Move to tomorrow, Move to another list, Move to Trash. Each is one
/// step with Undo in the tray, and ends the mode.
struct SelectMode: ViewModifier {
    @Binding var isSelecting: Bool
    let listTitle: String
    /// The page's open tasks, in its order.
    let tasks: [Block]
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.olStyle) private var style
    @Environment(\.olDockDrop) private var dockDrop
    @State private var token = UUID()
    @State private var selection: Set<UUID> = []
    @State private var picksList = false

    func body(content: Content) -> some View {
        content
            // The page under the mode is out of reach while it's up.
            .accessibilityHidden(isSelecting)
            .overlay {
                if isSelecting {
                    page
                        .transition(style.reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(style.fading(.snappy(duration: 0.3)), value: isSelecting)
            .onChange(of: isSelecting, initial: true) { _, selecting in
                env.navigator.hidesDock(selecting, for: token)
                if !selecting { selection = [] }
            }
            .onDisappear { env.navigator.hidesDock(false, for: token) }
    }

    private var page: some View {
        let picked = tasks.filter { selection.contains($0.id) }
        let allPicked = !tasks.isEmpty && picked.count == tasks.count
        return OLScreen(identifier: "screen.select") {
            OLTopBar {
                Button(allPicked ? "Select none" : "Select all") {
                    selection = allPicked ? [] : Set(tasks.map(\.id))
                }
                .buttonStyle(.olLink())
                .accessibilityIdentifier("select.all")
            } trailing: {
                Button("Done") { isSelecting = false }
                    .buttonStyle(.olLink(strong: true))
                    .accessibilityIdentifier("select.done")
            }
        } content: {
            OLHeader("\(picked.count) selected", sub: listTitle)
            if !tasks.isEmpty {
                OLCardRows(tasks, lazy: true) { task, separator in
                    row(task, separator: separator)
                }
                .padding(.top, OLMetrics.headerGap)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OLBulkBar(actions: [
                .init(symbol: "checkmark", label: "Mark done", isEnabled: !picked.isEmpty) { finish { env.actions.complete(picked) } },
                .init(symbol: "sun.max", label: "Move to today", isEnabled: !picked.isEmpty) {
                    finish { env.actions.schedule(picked, on: PhoneDay.today.date(now: env.now, calendar: env.settings.calendar)) }
                },
                .init(symbol: "arrow.right", label: "Move to tomorrow", isEnabled: !picked.isEmpty) {
                    finish { env.actions.schedule(picked, on: PhoneDay.tomorrow.date(now: env.now, calendar: env.settings.calendar)) }
                },
                .init(symbol: "square.grid.2x2", label: "Move to another list", isEnabled: !picked.isEmpty) { picksList = true },
                .init(symbol: "trash", label: "Move to Trash", isEnabled: !picked.isEmpty) { finish { env.actions.trash(picked) } },
            ])
            // In the dock's place.
            .offset(y: dockDrop)
        }
        .confirmationDialog("Move \(picked.count == 1 ? "1 task" : "\(picked.count) tasks") to", isPresented: $picksList,
                            titleVisibility: .visible) {
            ForEach(library.lists.filter { list in picked.contains { $0.listID != list.id } }) { list in
                Button("\(list.isSystemInbox ? "📥" : list.icon) \(list.displayTitle)") {
                    finish { env.actions.move(picked, to: list) }
                }
            }
        }
    }

    private func row(_ task: Block, separator: OLSeparator) -> some View {
        let isOn = selection.contains(task.id)
        let trailing = PhoneTaskRow.trailing(for: task, context: .select, now: env.now, calendar: env.settings.calendar)
        let toggle = {
            if isOn { selection.remove(task.id) } else { selection.insert(task.id) }
        }
        // The checkbox and the rest of the row both pick it.
        return OLTaskRow(title: task.displayTitle, state: isOn ? .selected : .open, trailing: trailing, separator: separator,
                         isHighlighted: isOn, onToggle: toggle, onOpen: toggle)
            .olFeedback(.selection, trigger: isOn)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(task.displayTitle)
            .accessibilityValue(trailing.map { $0.accessibilityLabel ?? $0.text ?? "" } ?? "")
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { toggle() }
            .accessibilityIdentifier("select.row")
    }

    private func finish(_ action: () -> Void) {
        action()
        isSelecting = false
    }
}
