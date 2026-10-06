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
        static let otherID = "other"
        static let archivedID = "archived"
        var id: String
        var title: String
        var lists: [TaskList]
    }

    /// Each section's lists, then the rest, then archived lists, with nested
    /// lists after their parent. When lists exist but no section holds one,
    /// the default section shows empty, so its New list card has a place.
    private var shelves: [Shelf] {
        var shelves = library.sections.map { Shelf(id: $0.id.uuidString, title: $0.displayTitle, lists: nested(library.lists(in: $0))) }
        let keptEmpty = shelves.allSatisfy(\.lists.isEmpty) && !library.destinations.isEmpty
            ? library.sections.first(where: \.isDefault).map(\.id.uuidString) : nil
        shelves.append(Shelf(id: Shelf.otherID, title: "Other lists", lists: nested(library.unsectioned)))
        shelves.append(Shelf(id: Shelf.archivedID, title: "Archived", lists: library.archived))
        return shelves.filter { !$0.lists.isEmpty || $0.id == keptEmpty }
    }

    private func nested(_ lists: [TaskList]) -> [TaskList] { library.outline(lists).map { $0.list } }

    /// The design's "N lists in 2 sections", of the sections that hold
    /// lists. Other lists, which have none, and archived ones say so after.
    private func subtitle(_ shelves: [Shelf]) -> String {
        func lists(_ count: Int) -> String { "\(count) \(count == 1 ? "list" : "lists")" }
        let sections = shelves.filter { $0.id != Shelf.otherID && $0.id != Shelf.archivedID && !$0.lists.isEmpty }
        let other = shelves.first { $0.id == Shelf.otherID }?.lists.count ?? 0
        var text: String
        if sections.isEmpty {
            text = lists(other)
        } else {
            text = "\(lists(sections.reduce(0) { $0 + $1.lists.count })) in \(sections.count) \(sections.count == 1 ? "section" : "sections")"
            if other > 0 { text += " · \(other) in Other lists" }
        }
        if !library.archived.isEmpty { text += " · \(library.archived.count) archived" }
        return text
    }

    var body: some View {
        let shelves = shelves
        NXPage(measure: nil) {
            NXScreenHeader(tile: .icon("square.2.layers.3d.fill"), color: NX.lists, title: "Lists", subtitle: subtitle(shelves))
            VStack(alignment: .leading, spacing: 0) {
                // With no list to use, archived ones aside, the first card makes one.
                if library.destinations.isEmpty {
                    LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 14) {
                        NXNewListCard(title: "Make your first list") { env.workbench.createList() }
                            .help("New list (⇧⌘N)")
                    }
                    .padding(.top, 20)
                }
                ForEach(shelves) { shelf in
                    VStack(alignment: .leading, spacing: 0) {
                        NXCapsTitle(text: shelf.title).padding(.bottom, 10)
                        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 14) {
                            ForEach(shelf.lists) { list in
                                let tasks = library.tasks(in: list.id)
                                NXListCard(list: list, tasks: tasks, peek: peek(list, tasks: tasks),
                                           path: library.hierarchy.ancestors(of: list.id).map(\.displayTitle).joined(separator: " › "))
                            }
                            // Each section ends with a place to start another list in it.
                            if let section = library.sections.first(where: { $0.id.uuidString == shelf.id }) {
                                NXNewListCard(title: "New list") { env.workbench.createList(in: section) }
                                    .help("New list in \(section.displayTitle)")
                            }
                        }
                    }
                    .padding(.top, 20)
                }
            }
            .padding(.top, 8)
        }
    }

    private static let columns = [GridItem(.adaptive(minimum: 230), spacing: 14)]

    /// The first three open tasks, subtasks included as the design's card
    /// takes them, in the list's document order. Worked out here, once per
    /// library change, so hovering a card never fetches.
    private func peek(_ list: TaskList, tasks: [Block]) -> [Block] {
        let open = tasks.filter { !$0.isCompleted }
        guard open.count > 1 else { return open }
        let ids = Set(open.map(\.id))
        var ordered = BlockTree.flatten(env.store.blocks(inList: list.id), respectCollapse: false)
            .map(\.block).filter { ids.contains($0.id) }
        // Tasks the outline could not reach still belong on the card.
        let seen = Set(ordered.map(\.id))
        ordered += open.filter { !seen.contains($0.id) }
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
    @State private var hovering = false

    var body: some View {
        let open = tasks.filter { !$0.isCompleted }
        let done = tasks.count - open.count
        let dueToday = open.filter(\.isDueOnOrBeforeToday).count
        let fraction = tasks.isEmpty ? 0 : Double(done) / Double(tasks.count)
        let color = list.nxColor
        let stats = "\(open.count) open" + (dueToday > 0 ? " · \(dueToday) due today" : "") + (done > 0 ? " · \(done) done" : "")
        VStack(alignment: .leading, spacing: 0) {
            color.opacity(0.08)
                .frame(height: 58)
                .overlay(alignment: .bottomLeading) {
                    NXListGlyph(list: list, size: 30)
                        .offset(x: 16, y: 14)
                }
                .zIndex(1)
            VStack(alignment: .leading, spacing: 9) {
                // Long names and paths wrap, as in the design; every card in
                // the row grows to match. The design's 600 14.5/1.2 is 0.6pt
                // under SwiftUI's 18pt line, which lineSpacing can't close up
                // (lineHeight(.exact) rounds to the screen's pixels and sets
                // the name half a point low), so half of it comes off above
                // and below.
                Text(list.displayTitle)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(NX.ink)
                    .lineLimit(2)
                    .padding(.vertical, (14.5 * 1.2 - NX.lineHeight(14.5)) / 2)
                // The design's 500 11.5/1.3 over SwiftUI's 14pt line, its extra
                // leading between lines and, halved, around them.
                let metaLeading = max(0, 11.5 * 1.3 - NX.lineHeight(11.5))
                Text(path.isEmpty ? stats : "In \(path) · \(stats)")
                    .font(.system(size: 11.5, weight: .medium))
                    .lineSpacing(metaLeading)
                    .foregroundStyle(NX.textTertiary)
                    .lineLimit(2)
                    .padding(.vertical, metaLeading / 2)
                Capsule().fill(NX.ink(0.07))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(fraction >= 1 ? NX.green : style.accent).frame(width: proxy.size.width * fraction)
                        }
                    }
                    .clipShape(Capsule())
                    .animation(NX.cssEase(500), value: fraction)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(peek) { task in
                        HStack(spacing: 7) {
                            // The design's 9px ring inside its 1.3px border.
                            Circle().strokeBorder(NX.ink(0.28), lineWidth: 1.3).frame(width: 11.6, height: 11.6)
                            // 400 12/1.3, over SwiftUI's 15pt line.
                            Text(task.displayTitle)
                                .font(.system(size: 12))
                                .foregroundStyle(NX.textSecondary)
                                .lineLimit(1)
                                .padding(.vertical, max(0, 12 * 1.3 - NX.lineHeight(12)) / 2)
                        }
                    }
                }
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
        // The design's 200ms lift, whatever the Motion setting.
        .animation(NX.ease(200), value: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { env.workbench.go(env.workbench.route(for: list)) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { env.workbench.go(env.workbench.route(for: list)) }
        .contextMenu { NXListMenu(list: list, surface: .gallery) }
    }
}

/// The dashed card after a section's lists that makes another there. It
/// takes the row's height beside real cards, and a card's own on a row by itself.
private struct NXNewListCard: View {
    @Environment(\.nextStyle) private var style
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(hovering ? style.accent.opacity(0.14) : NX.ink(0.05), in: Circle())
                    .foregroundStyle(hovering ? style.accent : NX.ink(0.45))
                Text(title).font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(hovering ? NX.textSecondary : NX.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
            .background(hovering ? NX.ink(0.02) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(NX.ink(hovering ? 0.22 : 0.13), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(NX.cssEase(120), value: hovering)
        }
        .buttonStyle(NXPressStyle())
        .onHover { hovering = $0 }
    }
}

// MARK: Trash

struct NextTrashScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    @Query(filter: #Predicate<Block> { $0.trashID != nil }) private var blocks: [Block]
    @Query(filter: #Predicate<TaskList> { $0.trashID != nil }) private var lists: [TaskList]
    @State private var entries: [TrashEntry] = []
    /// Whether the last read of Trash failed, which rows read before still show.
    @State private var unreadable = false

    var body: some View {
        let workbench = env.workbench
        let listIDs = Dictionary(blocks.map { ($0.id, $0.listID) }, uniquingKeysWith: { first, _ in first })
        // An entry leaves as the store writes its restore or erase, as in the
        // design, not one reload later: a restored row that had flown out
        // never shows again, and an erased one just goes.
        let held = Set(blocks.compactMap(\.trashID)).union(lists.compactMap(\.trashID))
        let rows = entries.filter { held.contains($0.id) }
        NXPage {
            NXScreenHeader(tile: .icon("trash.fill"), color: NX.grey, title: "Trash", subtitle: "Stays here until you erase it")
            VStack(alignment: .leading, spacing: 0) {
                if !rows.isEmpty {
                    HStack(spacing: 10) {
                        // The design's 400 12.5/1.4 over SwiftUI's 15pt line, its extra
                        // leading between lines and, halved, around them.
                        let leading = max(0, 12.5 * 1.4 - NX.lineHeight(12.5))
                        Text("Erasing can’t be undone.")
                            .font(.system(size: 12.5))
                            .lineSpacing(leading)
                            .foregroundStyle(NX.textTertiary)
                            .padding(.vertical, leading / 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        NXHoldButton(title: "Hold to empty Trash", icon: "trash.slash",
                                     size: 11.5, padding: EdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 11),
                                     radius: 8, rest: 0.1, confirmation: "Erase everything in Trash?",
                                     confirmLabel: "Empty Trash") {
                            workbench.erase(rows.map(\.id))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 10)
                }
                VStack(spacing: 2) {
                    ForEach(rows) { entry in
                        NXTrashRow(entry: entry, list: listIDs[entry.id].flatMap { library.list($0) })
                            .transition(.opacity)
                    }
                }
                // Only a read that worked can say it's empty; the notice says why one didn't.
                if rows.isEmpty {
                    NXDashedEmpty(text: unreadable ? "Trash could not be read." : "Trash is empty.").padding(.top, 6)
                }
            }
            .padding(.top, 18)
        }
        .onAppear(perform: reload)
        .onChange(of: blocks.map(\.id) + lists.map(\.id)) {
            withAnimation(NX.standard(300)) { reload() }
        }
    }

    private func reload() {
        do {
            entries = try env.store.trashEntries()
            unreadable = false
        } catch {
            unreadable = true
            env.store.trashError = "Trash could not be read. \(error.localizedDescription)"
        }
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
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                // The design's 400 13.5/1.3 over a 500 11/1 line: each line box
                // as CSS draws it over SwiftUI's 16pt and 14pt lines, the extra
                // leading halved around it.
                let leading = max(0, 13.5 * 1.3 - NX.lineHeight(13.5))
                Text(title)
                    .font(.system(size: 13.5))
                    .lineSpacing(leading)
                    .foregroundStyle(NX.textSecondary)
                    .lineLimit(2)
                    .padding(.vertical, leading / 2)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    meta(now: context.date)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NX.textTertiary)
                        .lineLimit(1)
                        // The line without its list's glyph, which reads as a symbol's name.
                        .accessibilityLabel(metaText(now: context.date))
                }
                .padding(.vertical, (11 - NX.lineHeight(11)) / 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One element, as it reads; Restore and Hold to erase stay buttons of their own.
            .accessibilityElement(children: .combine)
            Button { workbench.restore(entry) } label: {
                // The design's 13pt icon box, so the button is its 25pt, 6 + 13 + 6.
                Image(systemName: "arrow.up.bin").font(.system(size: 12)).frame(height: 13)
            }
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 7,
                                            padding: EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9),
                                            foreground: NX.ink(0.5), hoverForeground: NX.ink))
            .help("Restore")
            .accessibilityLabel("Restore")
            NXHoldButton(title: "Hold to erase", holdingTitle: "Keep holding…", size: 11,
                         padding: EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9), radius: 7, rest: 0,
                         confirmation: "Erase “\(title)”?") {
                workbench.erase([entry.id])
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(hovering ? NX.ink(0.03) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        // The design's fixed flight, whatever the Motion setting: the fade on
        // CSS's ease, the slide on the standard curve. Reduce Motion only
        // fades it, as its hint promises.
        .animation(NX.cssEase(300)) { $0.opacity(flying ? 0 : 1) }
        .animation(NX.standard(300)) { $0.offset(x: flying && style.slides ? -56 : 0) }
        .onHover { hovering = $0 }
    }

    private var title: String { entry.title.isEmpty ? "Untitled" : entry.title }

    /// The line after the entry's kind and where it was: when it was deleted,
    /// and what a task's Restore and Hold to erase take with it.
    private func tail(now: Date) -> String {
        let deleted = entry.metadata.map { "deleted \(NXFormat.relative($0.deletedAt, now: now))" } ?? "deleted"
        if entry.isList {
            let items = entry.blockCount == 1 ? "1 item" : "\(entry.blockCount) items"
            return "\(items) · \(deleted)"
        }
        return [deleted, entry.nestedSummary].compactMap { $0 }.joined(separator: " · ")
    }

    /// The meta line as VoiceOver reads it.
    private func metaText(now: Date) -> String {
        if entry.isList { return "List · \(tail(now: now))" }
        guard let metadata = entry.metadata else { return tail(now: now).capitalizedFirstLetter }
        return "From \(metadata.formerLocation) · \(tail(now: now))"
    }

    private func meta(now: Date) -> Text {
        if entry.isList { return Text(verbatim: "List · \(tail(now: now))") }
        // One entry holds a task with its subtasks, so the row says what
        // Restore and Hold to erase take with it, after the design's line so
        // a narrow row truncates the summary first.
        let rest = tail(now: now)
        guard let metadata = entry.metadata else { return Text(verbatim: rest.capitalizedFirstLetter) }
        // The icon the list had when this was deleted; older items use the list's current one.
        let icon = metadata.listIcon.map { $0.isEmpty ? "📋" : $0 } ?? list?.glyph ?? ""
        if icon.isEmpty { return Text(verbatim: "From \(metadata.formerLocation) · \(rest)") }
        if NXListGlyph.isSymbolName(icon) {
            return Text("From \(Image(systemName: icon)) \(metadata.formerLocation) · \(rest)")
        }
        // The emoji at the size the design's 11px line draws it, not Core Text's larger one.
        let glyph = Text(verbatim: icon).font(.system(size: NXListGlyph.emojiPointSize(11)))
        return Text("From \(glyph) \(metadata.formerLocation) · \(rest)")
    }
}

/// Press and hold for 900 ms; releasing or leaving early cancels. The fill
/// grows left to right while held. VoiceOver can't hold, so its action asks
/// `confirmation` first, in a Next sheet like Settings' confirmations.
struct NXHoldButton: View {
    let title: String
    /// Replaces the title while held; nil keeps it.
    var holdingTitle: String?
    var icon: String?
    var size: CGFloat = 11
    var padding = EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9)
    var radius: CGFloat = 7
    /// Red opacity at rest; at least 0.08 under the pointer.
    var rest: Double = 0.08
    let confirmation: String
    var confirmLabel = "Erase"
    let action: () -> Void

    @State private var holding = false
    @State private var hovering = false
    @State private var progress: CGFloat = 0
    @State private var bounds: CGSize = .zero
    @State private var timer: Task<Void, Never>?
    @State private var confirming = false

    var body: some View {
        // A line-height 1 label and the design's 14pt icon box, whatever the
        // symbol's own height: Hold to erase is its 23pt, Hold to empty Trash 28.
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: size + 2)).frame(height: 14) }
            Text(holding ? holdingTitle ?? title : title)
                .padding(.vertical, (size - NX.lineHeight(size)) / 2)
        }
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(NX.redText)
        .padding(padding)
        .background {
            ZStack(alignment: .leading) {
                NX.red.opacity(hovering ? max(rest, 0.08) : rest)
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
        .onHover {
            hovering = $0
            if !$0 { cancel() }
        }
        .onDisappear { cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { confirming = true }
        .sheet(isPresented: $confirming) {
            NXConfirmationSheet(title: confirmation, message: "This can’t be undone.", confirm: confirmLabel, action: action)
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
        // The fill goes at once as the hold ends, as the design's.
        progress = 0
    }
}
