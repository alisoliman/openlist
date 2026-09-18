import SwiftData
import SwiftUI

struct WorkTaskChooser: View {
    let choose: (WorkTaskReference) -> Void
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Block> { $0.trashID == nil && $0.kindRaw == "task" && !$0.isCompleted }) private var tasks: [Block]
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Find a task", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(candidates) { task in
                        Button { choose(WorkTaskReference(task)) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.displayTitle).font(.body).foregroundStyle(.primary)
                                Text("\(env.store.list(id: task.listID)?.displayTitle ?? "Task") · \(env.calendar.remainingMinutes(for: task).formatted(.number.precision(.fractionLength(0)))) min remaining")
                                    .font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(Theme.chrome, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(.rect)
                        }.buttonStyle(.plain)
                    }
                    if candidates.isEmpty { Text("No matching tasks").foregroundStyle(Theme.secondaryText).padding() }
                }
            }.frame(maxHeight: 300)
        }
    }

    private var candidates: [Block] {
        tasks.filter { env.calendar.validWorkTask(WorkTaskReference($0)) != nil && (search.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(search)) }
            .sorted { left, right in
                let a = env.calendar.plannedWork(WorkTaskReference(left))?.start ?? .distantFuture
                let b = env.calendar.plannedWork(WorkTaskReference(right))?.start ?? .distantFuture
                return a == b ? left.displayTitle.localizedStandardCompare(right.displayTitle) == .orderedAscending : a < b
            }
    }
}
