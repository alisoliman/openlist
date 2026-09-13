import Foundation

/// A reviewed merge is tied to concrete identities and reference snapshots.
/// A changed label or task requires fresh confirmation, never a silent retarget.
struct LabelMergePlan: Equatable {
    struct Request: Identifiable {
        let id = UUID()
        let sourceID: UUID
        let name: String
    }

    struct LabelState: Equatable {
        let id: UUID
        let name: String
        let accentRaw: String
        let sortIndex: Double
        let createdAt: Date

        init(_ label: TaskLabel) {
            id = label.id
            name = label.name
            accentRaw = label.accentRaw
            sortIndex = label.sortIndex
            createdAt = label.createdAt
        }

        var accent: ListAccent { ListAccent(rawValue: accentRaw) ?? .violet }

        func restore() -> TaskLabel {
            let label = TaskLabel(name: name, accent: accent, sortIndex: sortIndex)
            label.id = id
            label.accentRaw = accentRaw
            label.createdAt = createdAt
            return label
        }
    }

    struct Reference: Equatable {
        let id: UUID
        let isTask: Bool
        let labels: [UUID]
    }

    let source: LabelState
    let destination: LabelState
    let references: [Reference]

    var affectedTaskCount: Int { references.filter { $0.isTask && mergedLabels($0.labels) != $0.labels }.count }
    var resultingTaskCount: Int { references.filter(\.isTask).count }

    func mergedLabels(_ labels: [UUID]) -> [UUID] {
        var hasDestination = false
        return labels.compactMap { id in
            let replacement = id == source.id ? destination.id : id
            guard replacement == destination.id else { return replacement }
            guard !hasDestination else { return nil }
            hasDestination = true
            return replacement
        }
    }
}
