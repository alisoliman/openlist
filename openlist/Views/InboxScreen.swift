import SwiftData
import SwiftUI

/// A single rich capture document. Filing changes ownership and removes the
/// entire branch from Inbox, preserving identity, notes and attachments.
struct InboxScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var blocks: [Block]

    var body: some View {
        if let inbox = env.store.inboxList() {
            let captured = blocks.filter { $0.modelContext != nil && !$0.isDeleted && !$0.isTrashed && $0.listID == inbox.id }
            let openCount = captured.filter { $0.isTask && !$0.isCompleted }.count
            ScreenScaffold(headerSpacing: 24) {
                ScreenHeader(icon: "tray", title: "Inbox",
                    subtitle: "Capture now. File into a list when you’re ready.")
                    .padding(.leading, DocumentView.markerInset)
            } content: {
                HStack {
                    Text(openCount == 1 ? "1 open task" : "\(openCount) open tasks")
                        .font(Theme.Font.metadata)
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    CompletedTasksControl(list: inbox)
                }
                .padding(.leading, DocumentView.markerInset)
                .padding(.bottom, 12)

                if captured.isEmpty {
                    Text("Nothing to organize. Add a task or note below.")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.leading, DocumentView.markerInset)
                        .padding(.bottom, 8)
                }

                DocumentView(document: .init(listID: inbox.id),
                    emptyPlaceholder: "Capture a task or type / for a note…",
                    showsCompleted: inbox.showsCompleted(default: env.settings.showsCompletedTasks),
                    appendButtonTitle: "Capture a task or note", usesInboxActions: true)
                    .id(inbox.id)
            }
        } else {
            MissingContentView(message: "The Inbox could not be loaded.")
        }
    }
}
