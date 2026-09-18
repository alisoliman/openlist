import SwiftUI

/// Capture destination picker. Selection is always explicit.
struct CaptureDestinationPicker: View {
    let lists: [TaskList]
    @Binding var selection: UUID?
    var onWillOpen: (() -> Void)?
    var onDidClose: (() -> Void)?
    @State private var isOpen = false
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFocused: Bool

    private var matches: [TaskList] {
        lists.filter { query.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(query) || ($0.isSystemInbox && "Inbox".localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        Button {
            onWillOpen?()
            query = ""
            highlighted = 0
            isOpen = true
        } label: {
            Label(sourceTitle(lists.first(where: { $0.id == selection })), systemImage: "tray.and.arrow.down")
        }
        .accessibilityLabel("Destination list")
        .accessibilityValue(sourceTitle(lists.first(where: { $0.id == selection })))
        .help("Choose a list. Unfiled tasks stay in Inbox.")
        .popover(isPresented: $isOpen) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search lists", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onChange(of: query) { _, _ in highlighted = 0 }
                    .onSubmit { choose(matches[safe: highlighted]) }
                    .onKeyPress(.downArrow) {
                        highlighted = min(max(0, matches.count - 1), highlighted + 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        highlighted = max(0, highlighted - 1)
                        return .handled
                    }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, list in
                                Button { choose(list) } label: {
                                    HStack {
                                        Text(list.icon)
                                        Text(sourceTitle(list))
                                        Spacer()
                                        if list.id == selection { Image(systemName: "checkmark") }
                                    }
                                    .padding(8)
                                    .contentShape(Rectangle())
                                    .background(index == highlighted ? Theme.chipFill : .clear, in: .rect(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .id(list.id)
                            }
                            if matches.isEmpty { Text("No matching lists").foregroundStyle(.secondary).padding(8) }
                        }
                    }
                    .onChange(of: highlighted) { _, value in
                        if let list = matches[safe: value] { proxy.scrollTo(list.id) }
                    }
                }
            }
            .padding(12)
            .frame(width: 300, height: 260)
            .onAppear { isFocused = true }
            .onDisappear { onDidClose?() }
            .onExitCommand { isOpen = false }
        }
    }

    private func sourceTitle(_ list: TaskList?) -> String {
        guard let list, !list.isSystemInbox else { return "Inbox" }
        return list.displayTitle
    }

    private func choose(_ list: TaskList?) {
        guard let list else { return }
        selection = list.id
        isOpen = false
    }
}
