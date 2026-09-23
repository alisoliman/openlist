//
//  NextOverlays.swift
//  openlist
//

import SwiftUI

/// Capture, search and the command palette. Only one shows at a time; the
/// key monitor drives their arrows, Return, Tab and Escape.
struct NextOverlays: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style

    var body: some View {
        let workbench = env.workbench
        let navigator = env.navigator
        ZStack(alignment: .top) {
            if workbench.captureOpen {
                NXOverlayBackdrop(top: 96, close: { workbench.closeCapture() }) {
                    NXCaptureCard()
                }
            } else if navigator.isSearchOpen {
                NXOverlayBackdrop(top: 72, close: { navigator.isSearchOpen = false }) {
                    NXSearchCard()
                }
            } else if navigator.isCommandPaletteOpen {
                NXOverlayBackdrop(top: 84, close: { navigator.isCommandPaletteOpen = false }) {
                    NXPaletteCard()
                }
            }
        }
        .animation(style.ease(140), value: workbench.captureOpen)
        .animation(style.ease(140), value: navigator.isSearchOpen)
        .animation(style.ease(140), value: navigator.isCommandPaletteOpen)
        .onChange(of: navigator.isCommandPaletteOpen) { _, isOpen in
            guard isOpen else { return }
            workbench.paletteQuery = ""
            workbench.paletteIndex = 0
            navigator.isSearchOpen = false
            if workbench.captureOpen { workbench.closeCapture() }
        }
        .onChange(of: navigator.isSearchOpen) { _, isOpen in
            guard isOpen else { return }
            workbench.searchQuery = ""
            workbench.searchIndex = 0
            workbench.searchIncludesCompleted = false
            navigator.isCommandPaletteOpen = false
            if workbench.captureOpen { workbench.closeCapture() }
        }
    }
}

/// The dim backdrop (click closes) and the popping card.
private struct NXOverlayBackdrop<Card: View>: View {
    @Environment(\.nextStyle) private var style
    let top: CGFloat
    let close: () -> Void
    @ViewBuilder var card: () -> Card
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(hex: 0x17161A, opacity: 0.16)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
            card()
                .background(NX.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NX.ink(0.18), lineWidth: 0.5))
                .shadow(color: Color(hex: 0x17161A, opacity: 0.3), radius: 35, y: 30)
                .padding(.horizontal, 20)
                .padding(.top, top)
                .scaleEffect(shown ? 1 : 0.97, anchor: .top)
                .offset(y: shown ? 0 : -6)
                .opacity(shown ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity)
        .onAppear { withAnimation(style.ease(180)) { shown = true } }
    }
}

/// Puts the caret in an overlay's field once it is on screen.
private struct NXAutofocus: ViewModifier {
    @FocusState private var focused: Bool
    var refocus: AnyHashable = 0

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onAppear { DispatchQueue.main.async { focused = true } }
            .onChange(of: refocus) { _, _ in focused = true }
    }
}

// MARK: - Capture

private struct NXCaptureCard: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    @State private var refocus = 0

    var body: some View {
        @Bindable var workbench = env.workbench
        let parse = CaptureParse(workbench.captureText)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                Circle()
                    .strokeBorder(style.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [2.6, 2.2]))
                    .frame(width: 17, height: 17)
                    .padding(.top, 3)
                ZStack(alignment: .leading) {
                    styled(parse)
                        .font(.system(size: 16))
                        .lineLimit(1)
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                    TextField("", text: $workbench.captureText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .foregroundStyle(.clear)
                        .modifier(NXAutofocus(refocus: refocus))
                }
                .frame(height: 24)
                .clipped()
            }
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 6, trailing: 18))

            NXFlow(spacing: 6) {
                ForEach(chips(parse)) { NXChip(chip: $0, fresh: true) }
            }
            .frame(minHeight: 22, alignment: .leading)
            .padding(EdgeInsets(top: 6, leading: 46, bottom: 12, trailing: 18))

            HStack(alignment: .center, spacing: 8) {
                NXFlow(spacing: 6) {
                    Text("Add to")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NX.ink(0.45))
                        .padding(.trailing, 2)
                        .frame(height: 23)
                    ForEach(library.lists) { list in
                        destination(list, isOn: workbench.captureListID == list.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("⇥ destination · ↩ add · ⇧↩ add another")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NX.ink(0.4))
                    .fixedSize()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(NX.ink(0.02))
            .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.08)).frame(height: 0.5) }
        }
        .frame(maxWidth: 600)
    }

    /// The typed text with its tokens tinted, plus the placeholder ghost.
    private func styled(_ parse: CaptureParse) -> Text {
        guard !parse.text.isEmpty else {
            return Text("Pay deposit friday 6pm #travel ~15m").foregroundStyle(NX.ink(0.3))
        }
        var result = AttributedString()
        for segment in parse.segments {
            var run = AttributedString(segment.text)
            if let kind = segment.kind {
                let tone = Self.tone(kind, accent: style.accent)
                run.foregroundColor = tone
                run.backgroundColor = tone.opacity(0.1)
                run.underlineStyle = Text.LineStyle(pattern: .solid, color: tone.opacity(0.33))
            } else {
                run.foregroundColor = NX.ink
            }
            result += run
        }
        return Text(result)
    }

    static func tone(_ kind: CaptureParse.Kind, accent: Color) -> Color {
        switch kind {
        case .label: Color(hex: 0x12807F)
        case .priority: NX.redText
        default: accent
        }
    }

    private func chips(_ parse: CaptureParse) -> [NXChipModel] {
        let workbench = env.workbench
        var chips: [NXChipModel] = []
        var hasDate = false
        for (index, mark) in parse.marks.enumerated() {
            let id = "\(index)-\(mark.kind.rawValue)-\(mark.raw.lowercased())"
            switch mark.kind {
            case .date:
                if let date = TaskCaptureDraft(text: mark.raw).preview.date {
                    hasDate = true
                    chips.append(NXChipModel(id: id, label: "\(NXFormat.dueLabel(date)) · \(NXFormat.relativeDay(date))",
                                             icon: "calendar", tone: .accent))
                }
            case .time:
                chips.append(NXChipModel(id: id, label: CaptureParse.timeLabel(mark.raw) ?? mark.raw, icon: "bell", tone: .accent))
            case .repeatRule:
                chips.append(NXChipModel(id: id, label: mark.raw, icon: "repeat", tone: .accent))
            case .label:
                let name = String(mark.raw.dropFirst())
                let color = library.labels.first { $0.name.lowercased() == name.lowercased() }?.nxColor ?? Color(hex: 0x12807F)
                chips.append(NXChipModel(id: id, label: name, tone: .label(color)))
            case .priority:
                chips.append(NXChipModel(id: id, label: "High", icon: "exclamationmark", tone: .over, fill: true))
            case .estimate:
                chips.append(NXChipModel(id: id, label: "\(mark.raw.dropFirst()) estimate", icon: "timer", tone: .accent))
            }
        }
        if workbench.captureForToday && !hasDate {
            chips.insert(NXChipModel(id: "today", label: "Today", icon: "calendar", tone: .accent), at: 0)
        }
        return chips
    }

    private func destination(_ list: TaskList, isOn: Bool) -> some View {
        Button {
            env.workbench.captureListID = list.id
            refocus += 1
        } label: {
            HStack(spacing: 4) {
                NXListGlyph(list: list, size: 11)
                Text(list.displayTitle).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .foregroundStyle(isOn ? Color.white : NX.ink(0.66))
            .background(isOn ? style.accent : NX.ink(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: isOn)
    }
}

// MARK: - Search

struct NXSearchHit: Identifiable {
    var id: UUID
    var text: String
    var match: Range<String.Index>?
    var icon: String
    var list: TaskList?
    var sub: String
    var run: @MainActor () -> Void
}

enum NXSearch {
    @MainActor
    static func hits(env: AppEnvironment, library: NextLibrary) -> [NXSearchHit] {
        let workbench = env.workbench
        let query = workbench.searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        var hits: [NXSearchHit] = []
        for list in library.lists {
            guard let match = list.displayTitle.range(of: query, options: .caseInsensitive) else { continue }
            hits.append(NXSearchHit(id: list.id, text: list.displayTitle, match: match, icon: "square.stack", sub: "List") {
                workbench.go(workbench.route(for: list))
            })
        }
        for task in library.tasks {
            if task.isCompleted && !workbench.searchIncludesCompleted { continue }
            let title = task.displayTitle
            let match = title.range(of: query, options: .caseInsensitive)
            guard match != nil || task.note.localizedCaseInsensitiveContains(query) else { continue }
            let list = library.list(task.listID)
            var sub = list?.displayTitle ?? "Inbox"
            if let due = task.dueDate, !task.isCompleted { sub += " · " + NXFormat.dueLabel(due) }
            if task.isCompleted { sub += " · Completed" }
            if match == nil { sub += " · matched in note" }
            let id = task.id
            hits.append(NXSearchHit(id: id, text: title, match: match,
                                    icon: task.isCompleted ? "checkmark.circle.fill" : "circle", list: list, sub: sub) {
                if let list { workbench.go(workbench.route(for: list)) }
                workbench.navigator.isSearchOpen = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    workbench.focusID = id
                    workbench.inspect(id)
                }
            })
        }
        return Array(hits.prefix(12))
    }
}

private struct NXSearchCard: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library

    var body: some View {
        @Bindable var workbench = env.workbench
        let hits = NXSearch.hits(env: env, library: library)
        let index = min(workbench.searchIndex, max(0, hits.count - 1))
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(NX.ink(0.4))
                TextField("Find a task, note, or list", text: $workbench.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15.5))
                    .foregroundStyle(NX.ink)
                    .modifier(NXAutofocus())
                    .onChange(of: workbench.searchQuery) { _, _ in workbench.searchIndex = 0 }
                Button("Include completed") { workbench.searchIncludesCompleted.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(workbench.searchIncludesCompleted ? Color.white : NX.ink(0.55))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(workbench.searchIncludesCompleted ? style.accent : NX.ink(0.06),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .fixedSize()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.08)).frame(height: 0.5) }

            NXOverlayList(selection: hits.isEmpty ? nil : hits[index].id) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { offset, hit in
                    NXSearchRow(hit: hit, isOn: offset == index)
                        .id(hit.id)
                        .onHover { if $0 { workbench.searchIndex = offset } }
                        .onTapGesture { hit.run() }
                }
                Text(footer(hits))
                    .font(.system(size: 12.5))
                    .foregroundStyle(NX.ink(0.42))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(14)
            }
        }
        .frame(maxWidth: 640)
    }

    private func footer(_ hits: [NXSearchHit]) -> String {
        let workbench = env.workbench
        let query = workbench.searchQuery
        if query.trimmingCharacters(in: .whitespaces).isEmpty { return "Search tasks, notes and lists" }
        if !hits.isEmpty { return "\(hits.count) \(hits.count == 1 ? "result" : "results") · ↑↓ choose · ↩ open" }
        return "Nothing matches “\(query)”" + (workbench.searchIncludesCompleted ? "" : " — try including completed")
    }
}

private struct NXSearchRow: View {
    @Environment(\.nextStyle) private var style
    let hit: NXSearchHit
    let isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: hit.icon)
                .font(.system(size: 14))
                .foregroundStyle(isOn ? style.accent : NX.ink(0.4))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NX.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    if let list = hit.list { NXListGlyph(list: list, size: 10) }
                    Text(hit.sub).lineLimit(1)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NX.ink(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(isOn ? style.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(isOn ? style.accent.opacity(0.2) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private var title: AttributedString {
        var text = AttributedString(hit.text)
        if let match = hit.match,
           let lower = AttributedString.Index(match.lowerBound, within: text),
           let upper = AttributedString.Index(match.upperBound, within: text) {
            text[lower..<upper].backgroundColor = style.accent.opacity(0.15)
            text[lower..<upper].foregroundColor = style.accent
        }
        return text
    }
}

/// Up to 380pt of rows, scrolling only when they overflow, keeping the
/// chosen row in view.
private struct NXOverlayList<Content: View>: View {
    var selection: UUID?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    content()
                }
                .padding(6)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: selection) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
        .frame(maxHeight: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Palette

struct NXCommand: Identifiable {
    var id: String
    var icon: String
    var label: String
    var key = ""
    var tone: Color?
    var needsTarget = false
    var run: @MainActor () -> Void
}

enum NXPalette {
    @MainActor
    static func commands(env: AppEnvironment, library: NextLibrary) -> [NXCommand] {
        let workbench = env.workbench
        let hasTarget = !workbench.targetTasks.isEmpty
        let query = workbench.paletteQuery.trimmingCharacters(in: .whitespaces).lowercased()
        func act(_ body: @escaping @MainActor ([UUID]) -> Void) -> @MainActor () -> Void {
            {
                let ids = workbench.targetTasks.map(\.id)
                if !ids.isEmpty { body(ids) }
            }
        }
        let nav: [(AppRoute, String, String, String)] = [
            (.inbox, "tray", "Go to Inbox", "G I"),
            (.today, "sun.max", "Go to Today", "G T"),
            (.calendar, "calendar", "Go to Calendar", "G C"),
            (.tasks, "checklist", "Go to Tasks", "G A"),
            (.lists, "square.stack", "Go to Lists", "G L"),
            (.activity, "square.grid.2x2", "Go to Activity", "G H"),
            (.trash, "trash", "Go to Trash", ""),
            (.settings, "gearshape", "Open Settings", "⌘,"),
        ]
        var all: [NXCommand] = [
            NXCommand(id: "done", icon: "checkmark.circle", label: "Mark as done", key: "E", tone: NX.green, needsTarget: true,
                      run: act { workbench.complete($0) }),
            NXCommand(id: "today", icon: "calendar", label: "Due today", key: "T", needsTarget: true,
                      run: act { workbench.schedule($0, offset: 0) }),
            NXCommand(id: "tomorrow", icon: "sunrise", label: "Due tomorrow", key: "M", needsTarget: true,
                      run: act { workbench.schedule($0, offset: 1) }),
            NXCommand(id: "plan", icon: "calendar.badge.clock", label: "Plan for today", key: "P", needsTarget: true,
                      run: act { workbench.plan($0) }),
            NXCommand(id: "fit", icon: "sparkles", label: "Find a slot in the calendar", needsTarget: true,
                      run: act { $0.forEach { workbench.fit($0) } }),
            NXCommand(id: "work", icon: "play.fill", label: "Start working", needsTarget: true,
                      run: act { workbench.startWork($0[0]) }),
            NXCommand(id: "star", icon: "star", label: "Star", key: "F", tone: NX.amberText, needsTarget: true,
                      run: act { workbench.star($0) }),
        ]
        all += library.lists.map { list in
            NXCommand(id: "move-\(list.id)", icon: "arrow.turn.down.right", label: "Move to \(list.displayTitle)", needsTarget: true,
                      run: act { workbench.move($0, to: list.id) })
        }
        all += [
            NXCommand(id: "details", icon: "sidebar.right", label: "Open details", key: "↩", needsTarget: true,
                      run: act { workbench.inspect($0[0]) }),
            NXCommand(id: "trash", icon: "trash", label: "Move to Trash", key: "D", tone: NX.redText, needsTarget: true,
                      run: act { workbench.trash($0) }),
            NXCommand(id: "new", icon: "plus.circle", label: "New task", key: "N") { workbench.openCapture() },
            NXCommand(id: "search", icon: "magnifyingglass", label: "Search", key: "/") { env.navigator.isSearchOpen = true },
            NXCommand(id: "undo", icon: "arrow.uturn.backward", label: "Undo last change", key: "⌘Z") { workbench.undoLast() },
        ]
        all += nav.map { route, icon, label, key in
            NXCommand(id: "go-\(label)", icon: icon, label: label, key: key) { workbench.go(route) }
        }
        all += library.destinations.map { list in
            NXCommand(id: "open-\(list.id)", icon: "square.stack", label: "Open \(list.displayTitle)") { workbench.go(.list(list.id)) }
        }
        let filtered = all.enumerated().filter { _, command in
            (!command.needsTarget || hasTarget) && (query.isEmpty || command.label.lowercased().contains(query))
        }
        guard !query.isEmpty else { return filtered.map(\.element) }
        return filtered.sorted { a, b in
            let x = a.element.label.lowercased().range(of: query).map { a.element.label.lowercased().distance(from: a.element.label.lowercased().startIndex, to: $0.lowerBound) } ?? 0
            let y = b.element.label.lowercased().range(of: query).map { b.element.label.lowercased().distance(from: b.element.label.lowercased().startIndex, to: $0.lowerBound) } ?? 0
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element)
    }

    /// Closes the palette, then runs the command once the card is gone.
    @MainActor
    static func run(_ command: NXCommand, env: AppEnvironment) {
        env.navigator.isCommandPaletteOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { command.run() }
    }
}

private struct NXPaletteCard: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library

    var body: some View {
        @Bindable var workbench = env.workbench
        let commands = NXPalette.commands(env: env, library: library)
        let index = min(workbench.paletteIndex, max(0, commands.count - 1))
        let targets = workbench.targetTasks
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "bolt").font(.system(size: 16)).foregroundStyle(NX.ink(0.4))
                TextField("Type an action or a place…", text: $workbench.paletteQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15.5))
                    .foregroundStyle(NX.ink)
                    .modifier(NXAutofocus())
                    .onChange(of: workbench.paletteQuery) { _, _ in workbench.paletteIndex = 0 }
                Text(targets.isEmpty ? "No task focused"
                     : targets.count == 1 ? NXFormat.short(targets[0].displayTitle) : "\(targets.count) selected")
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(targets.isEmpty ? NX.ink(0.45) : style.accent)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(targets.isEmpty ? NX.ink(0.06) : style.accent.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(maxWidth: 200, alignment: .trailing)
                    .fixedSize()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(NX.ink(0.08)).frame(height: 0.5) }

            NXOverlayList(selection: nil) {
                ForEach(Array(commands.enumerated()), id: \.element.id) { offset, command in
                    NXPaletteRow(command: command, isOn: offset == index)
                        .onHover { if $0 { workbench.paletteIndex = offset } }
                        .onTapGesture { NXPalette.run(command, env: env) }
                }
            }
            .modifier(NXScrollToIndex(ids: commands.map(\.id), index: index))
        }
        .frame(maxWidth: 560)
    }
}

/// Keeps the palette's chosen row visible as arrows move through it.
private struct NXScrollToIndex: ViewModifier {
    let ids: [String]
    let index: Int

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.onChange(of: index) { _, index in
                guard ids.indices.contains(index) else { return }
                proxy.scrollTo(ids[index])
            }
        }
    }
}

private struct NXPaletteRow: View {
    @Environment(\.nextStyle) private var style
    let command: NXCommand
    let isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.icon)
                .font(.system(size: 14))
                .foregroundStyle(isOn ? Color.white : command.tone ?? NX.ink(0.5))
                .frame(width: 16)
            Text(command.label).font(.system(size: 13, weight: .medium)).lineLimit(1)
            Spacer(minLength: 8)
            Text(command.key).font(NX.mono(10.5)).opacity(0.5)
        }
        .foregroundStyle(isOn ? Color.white : NX.ink)
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(isOn ? style.accent : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .id(command.id)
    }
}
