//
//  NextGallery.swift
//  openlist
//
//  Lists gallery and Trash.
//

import SwiftData
import SwiftUI

// MARK: Lists

struct NextListsGallery: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library

    private struct Shelf: Identifiable {
        static let archivedID = "archived"
        var id: String
        var title: String
        var lists: [TaskList]
    }

    /// Each section's lists, then the rest, then archived lists, with nested
    /// lists after their parent.
    private var shelves: [Shelf] {
        var shelves = library.sections.map { Shelf(id: $0.id.uuidString, title: $0.displayTitle, lists: nested(library.lists(in: $0))) }
        shelves.append(Shelf(id: "other", title: "Other lists", lists: nested(library.unsectioned)))
        shelves.append(Shelf(id: Shelf.archivedID, title: "Archived", lists: library.archived))
        return shelves.filter { !$0.lists.isEmpty }
    }

    private func nested(_ lists: [TaskList]) -> [TaskList] { library.outline(lists).map { $0.list } }

    private func subtitle(_ shelves: [Shelf]) -> String {
        let filed = shelves.filter { $0.id != Shelf.archivedID }
        let count = filed.reduce(0) { $0 + $1.lists.count }
        var text = "\(count) \(count == 1 ? "list" : "lists") in \(filed.count) \(filed.count == 1 ? "section" : "sections")"
        if !library.archived.isEmpty { text += " · \(library.archived.count) archived" }
        return text
    }

    var body: some View {
        let shelves = shelves
        NXPage(wide: true) {
            NXScreenHeader(tile: .icon("square.2.layers.3d.fill"), color: NX.lists, title: "Lists", subtitle: subtitle(shelves))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(shelves) { shelf in
                    VStack(alignment: .leading, spacing: 0) {
                        NXCapsTitle(text: shelf.title).padding(.bottom, 10)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], alignment: .leading, spacing: 14) {
                            ForEach(shelf.lists) { list in
                                let tasks = library.tasks(in: list.id)
                                NXListCard(list: list, tasks: tasks, peek: peek(list, tasks: tasks),
                                           path: library.hierarchy.ancestors(of: list.id).map(\.displayTitle).joined(separator: " › "),
                                           isArchived: shelf.id == Shelf.archivedID)
                            }
                        }
                    }
                    .padding(.top, 20)
                }
                if shelves.isEmpty {
                    NXDashedEmpty(text: "No lists yet. Press ⇧⌘N to make one.").padding(.top, 20)
                }
            }
            .padding(.top, 8)
        }
    }

    /// The first three open top-level tasks, in the list's document order.
    /// Worked out here, once per library change, so hovering a card never fetches.
    private func peek(_ list: TaskList, tasks: [Block]) -> [Block] {
        let top = tasks.filter { !$0.isCompleted && !library.isSubtask($0) }
        guard top.count > 1 else { return top }
        let ids = Set(top.map(\.id))
        var ordered = BlockTree.flatten(env.store.blocks(inList: list.id), respectCollapse: false)
            .map(\.block).filter { ids.contains($0.id) }
        // Tasks the outline could not reach still belong on the card.
        let seen = Set(ordered.map(\.id))
        ordered += top.filter { !seen.contains($0.id) }
        return Array(ordered.prefix(3))
    }
}

private struct NXListCard: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let list: TaskList
    /// Every task in the list, subtasks included, as the list header counts them.
    let tasks: [Block]
    /// The open tasks the card previews.
    let peek: [Block]
    /// The lists it sits inside, or empty at the top level.
    let path: String
    /// Archived directly or through a parent.
    let isArchived: Bool
    @State private var hovering = false

    var body: some View {
        let open = tasks.filter { !$0.isCompleted }
        let done = tasks.count - open.count
        let dueToday = open.filter(\.isDueOnOrBeforeToday).count
        let fraction = tasks.isEmpty ? 0 : Double(done) / Double(tasks.count)
        let color = list.nxColor
        let stats = "\(open.count) open" + (dueToday > 0 ? " · \(dueToday) due today" : "") + (done > 0 ? " · \(done) done" : "")
        VStack(alignment: .leading, spacing: 0) {
            LinearGradient(colors: [color.opacity(0.2), color.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 58)
                .overlay(alignment: .bottomLeading) {
                    NXListGlyph(list: list, size: 30)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 2)
                        .offset(x: 16, y: 14)
                }
                .zIndex(1)
            VStack(alignment: .leading, spacing: 9) {
                // Long names and paths wrap, as in the design; every card in
                // the row grows to match.
                Text(list.displayTitle)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(NX.ink)
                    .lineLimit(2)
                Text(path.isEmpty ? stats : "In \(path) · \(stats)")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NX.ink(0.5))
                    .lineLimit(2)
                Capsule().fill(NX.ink(0.07))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(color).frame(width: proxy.size.width * fraction)
                        }
                    }
                    .clipShape(Capsule())
                    .animation(.easeOut(duration: 0.5), value: fraction)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(peek) { task in
                        HStack(spacing: 7) {
                            Circle().strokeBorder(NX.ink(0.28), lineWidth: 1.3).frame(width: 9, height: 9)
                            Text(task.displayTitle)
                                .font(.system(size: 12))
                                .foregroundStyle(NX.ink(0.62))
                                .lineLimit(1)
                        }
                    }
                }
                // Room for three peek rows, whatever the card previews.
                .frame(minHeight: 3 * 16 + 8, alignment: .top)
                .padding(.top, 2)
            }
            .padding(EdgeInsets(top: 20, leading: 16, bottom: 14, trailing: 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NX.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NX.ink(hovering ? 0.14 : 0.12), lineWidth: 0.5))
        .shadow(color: NX.shadowWarm.opacity(hovering ? 0.1 : 0.04), radius: hovering ? 14 : 3, y: hovering ? 12 : 2)
        .offset(y: hovering ? -2 : 0)
        .animation(style.ease(200), value: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { env.workbench.go(env.workbench.route(for: list)) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { env.workbench.go(env.workbench.route(for: list)) }
        .contextMenu { menu }
    }

    @ViewBuilder
    private var menu: some View {
        let workbench = env.workbench
        Button("Open") { workbench.go(workbench.route(for: list)) }
        CopyItemLinkButton(target: .list(list.id))
        Divider()
        // Nested lists show under their parent, so only top-level ones can be pinned.
        if !isArchived && path.isEmpty {
            Button(list.isPinned ? "Remove from Sidebar" : "Pin to Sidebar") { workbench.setPinned(!list.isPinned, for: list) }
        }
        Button("Duplicate") { workbench.go(.list(env.store.duplicateList(list).id)) }
        Button("Use as Template…") { env.templateCopyRequest = TemplateCopyRequest(source: .list(list.id), undoManager: nil) }
        Button("Export as Markdown…") { MarkdownExporter.presentSavePanel(for: list, store: env.store) }
        Button("Move List…") { env.listPendingMove = list }
        Button("New Child List") { workbench.createChildList(in: list) }
            .disabled(isArchived)
        // A list archived with its parent comes back when the parent does.
        if list.isArchived || !isArchived {
            Button(list.isArchived ? "Unarchive List" : "Archive List") { workbench.setArchived(!list.isArchived, for: list) }
                .help("Archived lists stay here and stop contributing tasks or reminders.")
        }
        Divider()
        Button("Delete List", role: .destructive) { env.requestDeleteList(list) }
    }
}

// MARK: Trash

struct NextTrashScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    @Query(filter: #Predicate<Block> { $0.trashID != nil }) private var blocks: [Block]
    @Query(filter: #Predicate<TaskList> { $0.trashID != nil }) private var lists: [TaskList]
    @State private var entries: [TrashEntry] = []

    var body: some View {
        let workbench = env.workbench
        let listIDs = Dictionary(blocks.map { ($0.id, $0.listID) }, uniquingKeysWith: { first, _ in first })
        NXPage {
            NXScreenHeader(tile: .icon("trash.fill"), color: NX.grey, title: "Trash", subtitle: "Stays here until you erase it")
            VStack(alignment: .leading, spacing: 0) {
                if !entries.isEmpty {
                    HStack(spacing: 10) {
                        Text("Restoring puts a task back in its list, in its old position. Erasing can’t be undone — press and hold.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(NX.ink(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        NXHoldButton(title: "Hold to empty Trash", icon: "trash.slash",
                                     size: 11.5, padding: EdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 11),
                                     radius: 8, rest: 0.1, confirmation: "Erase everything in Trash?",
                                     confirmLabel: "Empty Trash") {
                            workbench.erase(entries.map(\.id))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 10)
                }
                VStack(spacing: 2) {
                    ForEach(entries) { entry in
                        NXTrashRow(entry: entry, list: listIDs[entry.id].flatMap { library.list($0) })
                            .transition(.opacity.combined(with: .offset(x: -56)))
                    }
                }
                if entries.isEmpty {
                    Text("Trash is empty.")
                        .font(.system(size: 13))
                        .foregroundStyle(NX.ink(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(34)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(NX.ink(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .padding(.top, 6)
                        .transition(.opacity)
                }
            }
            .padding(.top, 18)
        }
        .onAppear(perform: reload)
        .onChange(of: blocks.map(\.id) + lists.map(\.id)) {
            withAnimation(style.standard(300)) { reload() }
        }
    }

    private func reload() {
        do { entries = try env.store.trashEntries() }
        catch { env.store.trashError = "Trash could not be read. \(error.localizedDescription)" }
    }
}

private struct NXTrashRow: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let entry: TrashEntry
    /// The list a trashed task still belongs to, while it exists.
    let list: TaskList?
    @State private var hovering = false

    var body: some View {
        let workbench = env.workbench
        let flying = workbench.flying.contains(entry.id)
        HStack(spacing: 11) {
            Image(systemName: entry.isList ? "square.2.layers.3d" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(NX.ink(0.3))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(NX.ink(0.72))
                    .lineLimit(2)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    meta(now: context.date)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NX.ink(0.4))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { workbench.restore(entry) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.bin").font(.system(size: 12))
                    Text("Restore")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(NXHoverButtonStyle(hover: style.accent.opacity(0.18), rest: style.accent.opacity(0.1), radius: 7,
                                            padding: EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9),
                                            foreground: style.accent, hoverForeground: style.accent))
            .help("Put it back where it was")
            NXHoldButton(title: "Hold to erase", holdingTitle: "Keep holding…", size: 11,
                         padding: EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9), radius: 7, rest: 0.08,
                         confirmation: "Erase “\(title)”?") {
                workbench.erase([entry.id])
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(hovering ? NX.ink(0.03) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(flying ? 0 : 1)
        .offset(x: flying ? -56 : 0)
        .animation(style.standard(300), value: flying)
        .onHover { hovering = $0 }
    }

    private var title: String { entry.title.isEmpty ? "Untitled" : entry.title }

    private func meta(now: Date) -> Text {
        let deleted = entry.metadata.map { "deleted \(NXFormat.relative($0.deletedAt, now: now))" } ?? "deleted"
        if entry.isList {
            let items = entry.blockCount == 1 ? "1 item" : "\(entry.blockCount) items"
            return Text(verbatim: "List · \(items) · \(deleted)")
        }
        guard let metadata = entry.metadata else { return Text(verbatim: deleted.capitalizedFirstLetter) }
        // The icon the list had when this was deleted; older items use the list's current one.
        let icon = metadata.listIcon.map { $0.isEmpty ? "📋" : $0 } ?? list?.glyph ?? ""
        if icon.isEmpty { return Text(verbatim: "From \(metadata.formerLocation) · \(deleted)") }
        if NXListGlyph.isSymbolName(icon) {
            return Text("From \(Image(systemName: icon)) \(metadata.formerLocation) · \(deleted)")
        }
        // The emoji at the size the design's 11px line draws it, not Core Text's larger one.
        let glyph = Text(verbatim: icon).font(.system(size: NXListGlyph.emojiPointSize(11)))
        return Text("From \(glyph) \(metadata.formerLocation) · \(deleted)")
    }
}

/// Press and hold for 900 ms; releasing or leaving early cancels. The fill
/// grows left to right while held. VoiceOver can't hold, so its action asks
/// `confirmation` first.
struct NXHoldButton: View {
    let title: String
    /// Replaces the title while held; nil keeps it.
    var holdingTitle: String?
    var icon: String?
    var size: CGFloat = 11
    var padding = EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9)
    var radius: CGFloat = 7
    /// Red opacity at rest.
    var rest: Double = 0.08
    let confirmation: String
    var confirmLabel = "Erase"
    let action: () -> Void

    @State private var holding = false
    @State private var progress: CGFloat = 0
    @State private var bounds: CGSize = .zero
    @State private var timer: Task<Void, Never>?
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: size + 2)) }
            Text(holding ? holdingTitle ?? title : title)
        }
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(NX.redText)
        .padding(padding)
        .background {
            ZStack(alignment: .leading) {
                NX.red.opacity(rest)
                GeometryReader { proxy in
                    NX.red.opacity(0.28).frame(width: proxy.size.width * progress)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .onGeometryChange(for: CGSize.self, of: \.size) { bounds = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let inside = CGRect(origin: .zero, size: bounds).insetBy(dx: -4, dy: -4).contains(value.location)
                    if !inside { cancel() } else if !holding && timer == nil { start() }
                }
                .onEnded { _ in cancel() }
        )
        .onHover { if !$0 { cancel() } }
        .onDisappear { cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { confirming = true }
        .confirmationDialog(confirmation, isPresented: $confirming) {
            Button(confirmLabel, role: .destructive, action: action)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone.")
        }
    }

    private func start() {
        holding = true
        withAnimation(.linear(duration: 0.9)) { progress = 1 }
        timer = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            action()
            reset()
        }
    }

    private func cancel() {
        guard holding || timer != nil else { return }
        timer?.cancel()
        reset()
    }

    private func reset() {
        timer = nil
        holding = false
        withAnimation(.easeOut(duration: 0.15)) { progress = 0 }
    }
}
