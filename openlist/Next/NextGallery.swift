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
        var id: String
        var title: String
        var lists: [TaskList]
    }

    private var shelves: [Shelf] {
        var shelves = library.sections.map { Shelf(id: $0.id.uuidString, title: $0.displayTitle, lists: library.lists(in: $0)) }
        shelves.append(Shelf(id: "other", title: "Other lists", lists: library.unsectioned))
        return shelves.filter { !$0.lists.isEmpty }
    }

    var body: some View {
        let shelves = shelves
        let count = shelves.reduce(0) { $0 + $1.lists.count }
        NXPage {
            NXScreenHeader(tile: .icon("square.stack"), color: NX.lists, title: "Lists",
                           subtitle: "\(count) \(count == 1 ? "list" : "lists") in \(shelves.count) \(shelves.count == 1 ? "section" : "sections")")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(shelves) { shelf in
                    VStack(alignment: .leading, spacing: 0) {
                        NXCapsTitle(text: shelf.title).padding(.bottom, 10)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], alignment: .leading, spacing: 14) {
                            ForEach(shelf.lists) { list in
                                NXListCard(list: list, tasks: library.tasks.filter { $0.listID == list.id && !library.isSubtask($0) })
                            }
                        }
                    }
                    .padding(.top, 20)
                }
                if shelves.isEmpty {
                    NXDashedEmpty(text: "No lists yet. Press ⌘N in the sidebar to make one.").padding(.top, 20)
                }
            }
            .padding(.top, 8)
        }
    }
}

private struct NXListCard: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    let list: TaskList
    let tasks: [Block]
    @State private var hovering = false

    var body: some View {
        let open = tasks.filter { !$0.isCompleted }
        let done = tasks.count - open.count
        let dueToday = open.filter { $0.dueDate.map { NXFormat.dayOffset($0) <= 0 } == true }.count
        let fraction = tasks.isEmpty ? 0 : Double(done) / Double(tasks.count)
        let color = list.nxColor
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
                Text(list.displayTitle)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(NX.ink)
                    .lineLimit(1)
                Text("\(open.count) open" + (dueToday > 0 ? " · \(dueToday) due today" : "") + (done > 0 ? " · \(done) done" : ""))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NX.ink(0.5))
                    .lineLimit(1)
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
                    ForEach(open.prefix(3)) { task in
                        HStack(spacing: 7) {
                            Circle().strokeBorder(NX.ink(0.28), lineWidth: 1.3).frame(width: 9, height: 9)
                            Text(task.displayTitle)
                                .font(.system(size: 12))
                                .foregroundStyle(NX.ink(0.62))
                                .lineLimit(1)
                        }
                    }
                }
                // Three peek rows keep every card in a row the same height.
                .frame(minHeight: 3 * 16 + 8, alignment: .top)
                .padding(.top, 2)
            }
            .padding(EdgeInsets(top: 20, leading: 16, bottom: 14, trailing: 16))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}

// MARK: Trash

struct NextTrashScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Query(filter: #Predicate<Block> { $0.trashID != nil }) private var blocks: [Block]
    @Query(filter: #Predicate<TaskList> { $0.trashID != nil }) private var lists: [TaskList]
    @State private var entries: [TrashEntry] = []

    var body: some View {
        let workbench = env.workbench
        NXPage {
            NXScreenHeader(tile: .icon("trash"), color: NX.grey, title: "Trash", subtitle: "Stays here until you erase it")
            VStack(alignment: .leading, spacing: 0) {
                if !entries.isEmpty {
                    HStack(spacing: 10) {
                        Text("Restoring puts a task back in its list, in its old position. Erasing can’t be undone — press and hold.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(NX.ink(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        NXHoldButton(title: "Hold to empty Trash", holdingTitle: "Keep holding…", icon: "trash.slash",
                                     size: 11.5, padding: EdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 11),
                                     radius: 8, rest: 0.1) {
                            workbench.erase(entries.map(\.id))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 10)
                }
                VStack(spacing: 2) {
                    ForEach(entries) { entry in
                        NXTrashRow(entry: entry)
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
    @State private var hovering = false

    var body: some View {
        let workbench = env.workbench
        let flying = workbench.flying.contains(entry.id)
        HStack(spacing: 11) {
            Image(systemName: entry.isList ? "square.stack" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(NX.ink(0.3))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(NX.ink(0.72))
                    .lineLimit(2)
                Text(meta)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NX.ink(0.4))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { workbench.restore(entry) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.bin").font(.system(size: 12))
                    Text("Restore")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(NXHoverButtonStyle(hover: style.accent.opacity(0.18), radius: 7,
                                            padding: EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9),
                                            foreground: style.accent, hoverForeground: style.accent))
            .background(style.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .help("Put it back where it was")
            NXHoldButton(title: "Hold to erase", holdingTitle: "Keep holding…", size: 11,
                         padding: EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9), radius: 7, rest: 0.08) {
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

    private var meta: String {
        let deleted = entry.metadata.map { "deleted \(NXFormat.relative($0.deletedAt))" } ?? "deleted"
        if entry.isList {
            let items = entry.blockCount == 1 ? "1 item" : "\(entry.blockCount) items"
            return "List · \(items) · \(deleted)"
        }
        guard let metadata = entry.metadata else { return deleted.capitalizedFirst }
        return "From \(metadata.formerLocation) · \(deleted)"
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Press and hold for 900 ms; releasing or leaving early cancels. The fill
/// grows left to right while held.
struct NXHoldButton: View {
    let title: String
    let holdingTitle: String
    var icon: String?
    var size: CGFloat = 11
    var padding = EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9)
    var radius: CGFloat = 7
    /// Red opacity at rest.
    var rest: Double = 0.08
    let action: () -> Void

    @State private var holding = false
    @State private var progress: CGFloat = 0
    @State private var bounds: CGSize = .zero
    @State private var timer: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: size + 2)) }
            Text(holding ? holdingTitle : title)
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
        .accessibilityAction { action() }
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
