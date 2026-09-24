//
//  NextInbox.swift
//  openlist
//

import SwiftUI

struct NextInboxScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library

    var body: some View {
        // The design's 20s clock: the card's "Captured …" age moves on, and
        // its days and the rows' chips read the day it is.
        TimelineView(.periodic(from: .now, by: 20)) { context in
            page(now: context.date)
        }
    }

    /// The header's "N to triage · M kept for later", which the Inbox's
    /// document mode shows too.
    @MainActor
    static func subtitle(queue: [Block], kept: [Block], workbench: Workbench) -> String {
        "\(queue.count) to triage" + (workbench.kept.isEmpty ? "" : " · \(kept.count) kept for later")
    }

    private func page(now: Date) -> some View {
        let workbench = env.workbench
        let queue = library.inboxQueue(workbench)
        let kept = library.keptInbox(workbench)
        var groups: [NXGroup] = []
        if queue.count > 1 {
            groups.append(NXGroup(id: "next", title: "Up next", icon: "text.append", color: NX.inbox,
                                  rows: Array(queue.dropFirst())))
        }
        if !kept.isEmpty {
            groups.append(NXGroup(id: "kept", title: "Kept for later", icon: "clock.fill", color: NX.ink(0.45), rows: kept,
                                  collapsible: true))
        }
        // Only the rows below are focus targets: the triage card's keys work while nothing is focused.
        let rowIDs = NXGroupsStack.rowIDs(groups, workbench: workbench)
        return NXPage(rowIDs: rowIDs) {
            NXScreenHeader(tile: .icon("tray.fill"), color: NX.inbox, title: "Inbox",
                           subtitle: Self.subtitle(queue: queue, kept: kept, workbench: workbench)) {
                if let inbox = library.inbox {
                    Button { env.navigator.setListViewMode(.document, for: inbox.id) } label: {
                        Image(systemName: "doc.text").font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), radius: 7,
                                                    padding: EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5),
                                                    foreground: NX.ink(0.45), hoverForeground: NX.ink))
                    .help("Show notes and headings")
                    .accessibilityLabel("Show as Document")
                }
            }
            Group {
                // One card for the whole session, as in the design: it takes
                // each task in turn, so the progress dots can slide between them.
                if let task = queue.first {
                    NXTriageCard(task: task, remaining: queue.count, now: now)
                } else {
                    NXTriageEmpty()
                }
            }
            .padding(.top, 22)
            NXGroupsStack(groups: groups, options: NXRowOptions(showList: false, now: now), topPadding: 10)
        }
        // A focused row that becomes the card, or leaves the page, gives the keys back to triage.
        .onChange(of: rowIDs) { _, ids in dropStaleFocus(ids) }
        .onChange(of: workbench.focusID) { _, _ in dropStaleFocus(rowIDs) }
    }

    private func dropStaleFocus(_ rowIDs: [UUID]) {
        if let id = env.workbench.focusID, !rowIDs.contains(id) { env.workbench.focusID = nil }
    }
}

/// The Inbox as its document, a native extra: the list document every list
/// shows, under the Inbox's own header. Triage stays the Inbox's default.
struct NextInboxDocumentScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    let inbox: TaskList
    /// The document's task rows, which lead the page's J/K order.
    @State private var documentRowIDs: [UUID] = []

    var body: some View {
        let workbench = env.workbench
        let groups = NextListScreen.completedGroups(library.tasks(in: inbox.id), workbench: workbench,
                                                    showsCompleted: inbox.showsCompleted(default: env.settings.showsCompletedTasks),
                                                    inDocument: Set(documentRowIDs))
        NXPage(rowIDs: documentRowIDs + NXGroupsStack.rowIDs(groups, workbench: workbench)) {
            NXScreenHeader(tile: .icon("tray.fill"), color: NX.inbox, title: "Inbox",
                           subtitle: NextInboxScreen.subtitle(queue: library.inboxQueue(workbench),
                                                              kept: library.keptInbox(workbench), workbench: workbench)) {
                Button { env.navigator.setListViewMode(.tasks, for: inbox.id) } label: {
                    Image(systemName: "rectangle.stack").font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), radius: 7,
                                                padding: EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5),
                                                foreground: NX.ink(0.45), hoverForeground: NX.ink))
                .help("Triage one task at a time")
                .accessibilityLabel("Show as Triage")
            }
            NXDocumentOutline(list: inbox)
                // The Turn into card draws over the Completed group.
                .zIndex(1)
                .onPreferenceChange(NXDocumentRowsKey.self) { documentRowIDs = $0 }
            // The design's 20s clock, so Completed's done-ago chips move on.
            TimelineView(.periodic(from: .now, by: 20)) { context in
                NXGroupsStack(groups: groups, options: NXRowOptions(showList: false, listID: inbox.id, notes: true,
                                                                    now: context.date))
            }
        }
    }
}

private struct NXTriageCard: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextStyle) private var style
    @Environment(\.nextLibrary) private var library
    let task: Block
    let remaining: Int
    /// The Inbox's clock, which the card's age and days read.
    let now: Date
    /// The task whose lift-in has played. Each new task starts lowered and
    /// faded, like the design's liftIn, while the dots animate across.
    @State private var liftedID: UUID?

    var body: some View {
        let workbench = env.workbench
        let exit = workbench.triageExit
        let lifted = liftedID == task.id
        VStack(alignment: .leading, spacing: 0) {
            topLine
            // The design's 22/1.3: 2.6pt between lines, half of it above and below.
            Text(task.displayTitle)
                .font(.system(size: 22, weight: .medium))
                .kerning(-0.11)
                .lineSpacing(2.6)
                .foregroundStyle(NX.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 13.3)
                .padding(.horizontal, 18)
                .padding(.bottom, 5.3)
            HStack(spacing: 6) {
                ForEach(chips) { NXChip(chip: $0) }
            }
            .frame(minHeight: 4)
            .padding(.top, 4)
            .padding(.horizontal, 18)

            HStack(alignment: .top, spacing: 18) {
                fileInto.frame(maxWidth: .infinity, alignment: .topLeading)
                schedule.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)

            footer
        }
        .background(NX.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Done rings the card in place of its shadow, on the design's own
        // `box-shadow 200ms ease`, which motion doesn't scale.
        .transaction { transaction in
            if exit != nil, transaction.animation != nil { transaction.animation = NX.cssEase(200) }
        } body: { card in
            card
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(exit == .done ? NX.green : NX.ink(0.12), lineWidth: exit == .done ? 2 : 0.5))
                .shadow(color: NX.shadowWarm.opacity(exit == .done ? 0 : 0.09), radius: 20, y: 14)
        }
        .offset(x: exit == .left ? -90 : exit == .right ? 90 : 0,
                y: exit == .up ? -26 : exit == .down ? 26 : 0)
        .rotationEffect(.degrees(exit == .left ? -1.5 : exit == .right ? 1.5 : 0))
        .scaleEffect(exit == .up ? 0.97 : exit == .done ? 0.95 : 1)
        // The card moves on the standard curve but fades on plain `ease`.
        .transaction { transaction in
            if exit != nil, transaction.animation != nil {
                transaction.animation = style.cssEase(230)
            }
        } body: { $0.opacity(exit == nil ? 1 : 0) }
        .offset(y: lifted ? 0 : 10)
        .scaleEffect(lifted ? 1 : 0.985)
        .opacity(lifted ? 1 : 0)
        // The next task swaps in at once, hidden, and lifts in on a later
        // update so the two changes don't merge.
        .transaction(value: task.id) { $0.animation = nil }
        .task(id: task.id) { withAnimation(style.ease(320)) { liftedID = task.id } }
    }

    private var chips: [NXChipModel] {
        var chips: [NXChipModel] = []
        if let due = task.dueDate {
            chips.append(NXChipModel(id: "due", label: NXFormat.dueLabel(due, now: now), icon: "calendar",
                                     tone: NXFormat.dayOffset(due, now: now) <= 0 ? .accent : .neutral))
        }
        if task.priority != .none {
            chips.append(NXChipModel(id: "prio", label: task.priority == .high ? "High priority" : task.priority.title,
                                     icon: "flag.fill", tone: .over))
        }
        return chips
    }

    private var topLine: some View {
        let workbench = env.workbench
        let total = min(12, workbench.reviewed + remaining)
        return HStack(spacing: 10) {
            Text("Triage")
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.84)
                .textCase(.uppercase)
                .foregroundStyle(NX.inbox)
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index <= workbench.reviewed ? NX.inbox : NX.ink(0.12))
                        .frame(width: index == workbench.reviewed ? 16 : 5, height: 5)
                }
            }
            // The design's `transition: all 300ms ease`.
            .animation(NX.cssEase(300), value: workbench.reviewed)
            Text("\(remaining) to go")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NX.ink(0.42))
            Spacer(minLength: 8)
            Text("Captured \(NXFormat.relative(task.createdAt, now: now))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NX.ink(0.4))
        }
        .padding(.top, 14)
        .padding(.horizontal, 18)
    }

    private var fileInto: some View {
        VStack(alignment: .leading, spacing: 0) {
            caps("File into")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(library.destinations.prefix(9).enumerated()), id: \.element.id) { index, list in
                    NXTriageListRow(key: index + 1, list: list, count: library.openCount(in: list.id)) {
                        env.workbench.triage(task, action: .left, listID: list.id)
                    }
                }
            }
        }
    }

    private var schedule: some View {
        let load = Dictionary(grouping: library.open.compactMap { $0.dueDate.map { NXFormat.dayOffset($0, now: now) } }, by: { $0 })
            .mapValues(\.count)
        return VStack(alignment: .leading, spacing: 0) {
            caps("Or schedule — stays in Inbox")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 4), spacing: 4) {
                ForEach(0..<8, id: \.self) { offset in
                    NXTriageDay(offset: offset, load: load[offset] ?? 0, now: now) {
                        env.workbench.triage(task, action: .up, offset: offset)
                    }
                }
            }
            // The design's 10.5/1.4 over a 13pt line: 1.7pt between lines, half of it above and below.
            Text("T today · M tomorrow · dots show what’s already due")
                .font(.system(size: 10.5, weight: .medium))
                .lineSpacing(1.7)
                .foregroundStyle(NX.ink(0.4))
                .padding(.top, 8.85)
                .padding(.bottom, 0.85)
        }
    }

    private var footer: some View {
        let workbench = env.workbench
        return HStack(spacing: 6) {
            footerButton("Already done", icon: "checkmark.circle", key: "E", hover: NX.green.opacity(0.12), hoverText: NX.greenText) {
                workbench.triage(task, action: .done)
            }
            footerButton("Discard", icon: "trash", key: "D", hover: NX.red.opacity(0.1), hoverText: NX.redText) {
                workbench.triage(task, action: .down)
            }
            // Opens the inspector without focusing the card, so triage keys still apply once it closes.
            footerButton("Details", icon: "sidebar.right", key: "↩", hover: NX.ink(0.06), hoverText: NX.ink) {
                env.navigator.openTask(task.id)
            }
            Spacer(minLength: 8)
            Button { workbench.triage(task, action: .right) } label: {
                HStack(spacing: 6) {
                    Text("Keep for later").font(.system(size: 12, weight: .semibold))
                    Text("→").font(NX.mono(10, weight: .medium)).opacity(0.6)
                }
            }
            .buttonStyle(NXHoverButtonStyle(hover: NX.primaryButtonHover, rest: NX.primaryButton, radius: 8,
                                            padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
                                            foreground: .white, hoverForeground: .white))
            .accessibilityLabel("Keep for later")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(NX.ink(0.02))
        .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.08)).frame(height: 0.5) }
    }

    private func caps(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.74)
            .textCase(.uppercase)
            .foregroundStyle(NX.ink(0.36))
            // Wraps, as the design's does, when the column is narrow.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 8)
    }

    private func footerButton(_ title: String, icon: String, key: String, hover: Color, hoverText: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium))
                Text(key).font(NX.mono(9.5, weight: .medium)).opacity(0.5)
            }
        }
        .buttonStyle(NXHoverButtonStyle(hover: hover, radius: 8,
                                        padding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10),
                                        foreground: NX.ink(0.7), hoverForeground: hoverText))
        .accessibilityLabel(title)
    }
}

private struct NXTriageListRow: View {
    let key: Int
    let list: TaskList
    let count: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Text("\(key)")
                .font(NX.mono(10, weight: .semibold))
                .foregroundStyle(NX.ink(0.5))
                .frame(width: 16, height: 16)
                .background(NX.ink(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            NXListGlyph(list: list, size: 13)
            Text(list.displayTitle).font(.system(size: 13, weight: .medium)).foregroundStyle(NX.ink).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(count)").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(NX.ink(0.34))
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(hovering ? NX.inbox.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .help("File into \(list.displayTitle) (\(key))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("File into \(list.displayTitle)")
        .accessibilityValue("\(count) open")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

private struct NXTriageDay: View {
    @Environment(\.nextStyle) private var style
    let offset: Int
    let load: Int
    let now: Date
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let date = NXFormat.day(offset: offset, now: now)
        VStack(spacing: 4) {
            Text(offset == 0 ? "Today" : offset == 1 ? "Tmrw" : date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.38)
                .textCase(.uppercase)
                .foregroundStyle(NX.ink(0.42))
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 16, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(NX.ink)
            HStack(spacing: 2) {
                ForEach(0..<min(load, 4), id: \.self) { _ in
                    Circle().fill(load >= 3 ? NX.red : NX.ink(0.3)).frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 7)
        .background(hovering ? style.accent.opacity(0.12) : NX.ink(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .help(load == 0 ? "Nothing due" : "\(load) already due")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schedule for " + (offset == 0 ? "today" : offset == 1 ? "tomorrow"
            : date.formatted(.dateTime.weekday(.wide).day().month(.wide))))
        .accessibilityValue(load == 0 ? "Nothing due" : "\(load) already due")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

private struct NXTriageEmpty: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let workbench = env.workbench
        HStack(spacing: 18) {
            Circle().fill(NX.green)
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 4) {
                Text("Inbox triaged").font(NX.serif(26)).padding(.vertical, NX.serifLeading(26, lineHeight: 1.1)).foregroundStyle(NX.ink)
                // The design's 13/1.45 over a 16pt line: 2.85pt between lines, half of it above and below.
                Text("\(workbench.reviewed) reviewed this session. Tasks you kept or scheduled stay in Inbox until you file them.")
                    .font(.system(size: 13))
                    .lineSpacing(2.85)
                    .foregroundStyle(NX.ink(0.56))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 1.425)
            }
            Spacer(minLength: 8)
            // Always offered, as in the design; with nothing kept it just starts the count again.
            Button("Review kept tasks") {
                workbench.kept = []
                workbench.reviewed = 0
            }
            .font(.system(size: 12, weight: .semibold))
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.1), rest: NX.ink(0.06), radius: 8,
                                            padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
                                            foreground: NX.ink(0.7)))
        }
        .padding(.vertical, 34)
        .padding(.horizontal, 28)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .nxCardShadow(radius: 16, hairline: 0.1, drop: 0.06, y: 10, blur: 30)
        .modifier(NXLiftIn())
    }
}
