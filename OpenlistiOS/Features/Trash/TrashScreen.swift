//
//  TrashScreen.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI

/// Trash (mockup 16), pushed inside Settings: what was moved there, newest
/// first, where from and when. Restore puts one back, with Undo; holding ×
/// erases one for good, and holding the button below empties Trash.
struct TrashScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @State private var entries: [TrashEntry] = []

    var body: some View {
        let navigator = env.navigator
        let now = env.now
        OLScreen(identifier: PhoneRoute.trash.screenIdentifier) {
            OLTopBar { OLBackButton(env.backTitle(for: .trash)) { navigator.pop() } }
        } content: {
            OLHeader("Trash", sub: "\(entries.count) \(entries.count == 1 ? "item" : "items") · hold × to erase one for good")
            if entries.isEmpty {
                Text("Trash is empty.")
                    .font(OLFont.note)
                    .foregroundStyle(OL.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .accessibilityIdentifier("trash.empty")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        row(entry, now: now)
                            .overlay(alignment: .top) { OLSeparatorLine(separator: index == 0 ? .none : .plain) }
                    }
                }
                .olCard()
                .padding(.top, OLMetrics.headerGap)
                Text("Hold to empty Trash")
                    .font(OLFont.button)
                    .foregroundStyle(OL.danger)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(OL.dangerSoft, in: .capsule)
                    .olHold(Capsule()) { erase(entries.map(\.id), all: true) }
                    .padding(.top, OLMetrics.cardGap)
                    .accessibilityLabel("Empty Trash")
                    .accessibilityHint("Erases everything in Trash for good")
                    .accessibilityIdentifier("trash.emptyAll")
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in reload() }
    }

    private func row(_ entry: TrashEntry, now: Date) -> some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .font(OLFont.rowTitle)
                    .foregroundStyle(OL.ink)
                    .lineLimit(2)
                Text(detail(entry, now: now))
                    .font(OLFont.meta)
                    .foregroundStyle(OL.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button("Restore") { env.actions.restore([entry.id]) }
                .buttonStyle(.olLink(small: true))
                .accessibilityIdentifier("trash.restore")
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(OL.muted)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .olHold(Circle()) { erase([entry.id], all: false) }
                .accessibilityLabel("Hold to erase \(entry.title)")
                .accessibilityHint("Erases it for good")
        }
        .padding(.vertical, 11)
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: 62)
    }

    /// "Q3 planning · 3h ago", or "List · 4 items · yesterday".
    private func detail(_ entry: TrashEntry, now: Date) -> String {
        let when = entry.metadata.map { Self.ago($0.deletedAt, now: now) }
        if entry.isList {
            let items = entry.blockCount == 1 ? "1 item" : "\(entry.blockCount) items"
            return ["List", items, when].compactMap(\.self).joined(separator: " · ")
        }
        return [entry.metadata?.formerLocation, entry.nestedSummary, when].compactMap(\.self).joined(separator: " · ")
    }

    /// "12 min ago", "3h ago", "yesterday", "4 days ago".
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        case ..<86_400: return "\(Int(seconds / 3600))h ago"
        default: return CompactText.ago(date, now: now)
        }
    }

    private func erase(_ ids: [UUID], all: Bool) {
        guard !ids.isEmpty else { return }
        env.store.trashError = nil
        if env.store.permanentlyEraseTrash(ids: ids) {
            env.haptics.play(.warning)
            env.tray.show(ids.count == 1 ? "Erased for good" : "Erased \(ids.count) items for good", icon: "trash.slash",
                          tone: .danger, seconds: 4)
        } else {
            env.tray.show(env.store.trashError ?? "That could not be erased.", icon: "exclamationmark.circle",
                          tone: .danger, seconds: 5)
        }
        reload()
    }

    private func reload() {
        entries = (try? env.store.trashEntries()) ?? []
    }
}
