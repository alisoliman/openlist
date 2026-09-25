import SwiftData
import SwiftUI

struct WorkTaskChooser: View {
    let choose: (WorkTaskReference) -> Void
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Block> { $0.trashID == nil && $0.kindRaw == "task" && !$0.isCompleted }) private var tasks: [Block]
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NXPanelField(icon: "magnifyingglass") {
                TextField("Find a task", text: $search)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(candidates) { task in
                        Button { choose(WorkTaskReference(task)) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.displayTitle).font(.system(size: 13, weight: .medium)).foregroundStyle(NX.ink)
                                Text("\(env.store.list(id: task.listID)?.displayTitle ?? "Task") · \(env.calendar.remainingMinutes(for: task).formatted(.number.precision(.fractionLength(0)))) min remaining")
                                    .font(.system(size: 11.5)).foregroundStyle(NX.ink(0.45))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), rest: NX.ink(0.035), radius: 8,
                                                        padding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)))
                    }
                    if candidates.isEmpty {
                        Text("No matching tasks").font(.system(size: 12)).foregroundStyle(NX.ink(0.45))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                    }
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
