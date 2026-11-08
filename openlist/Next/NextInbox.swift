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

    /// The header's "N to triage · M kept for later · K snoozed", which the
    /// Inbox's document mode shows too.
    @MainActor
    static func subtitle(queue: [Block], kept: [Block], snoozed: Int, workbench: Workbench) -> String {
        "\(queue.count) to triage" + (workbench.kept.isEmpty ? "" : " · \(kept.count) kept for later")
            + (snoozed == 0 ? "" : " · \(snoozed) snoozed")
    }

    private func page(now: Date) -> some View {
        let workbench = env.workbench
        let queue = library.inboxQueue(workbench)
        let kept = library.keptInbox(workbench)
        let snoozed = library.snoozedInbox(now: now)
        var groups: [NXGroup] = []
        if queue.count > 1 {
            groups.append(NXGroup(id: "next", title: "Up next", icon: "text.append", color: NX.ink(0.45),
                                  rows: Array(queue.dropFirst())))
        }
        if !kept.isEmpty {
            groups.append(NXGroup(id: "kept", title: "Kept for later", icon: "clock.fill", color: NX.ink(0.45), rows: kept,
                                  collapsible: true))
        }
        // Back by themselves on their day; folded, as they're out of the way.
        if !snoozed.isEmpty {
            groups.append(NXGroup(id: "snoozed", title: "Snoozed", icon: "moon.zzz.fill", color: NX.ink(0.45), rows: snoozed,
                                  collapsible: true, defaultOpen: false))
        }
        // Only the rows below are focus targets: the triage card's keys work while nothing is focused.
        let rowIDs = NXGroupsStack.rowIDs(groups, workbench: workbench)
        return NXPage(rowIDs: rowIDs) {
            NXScreenHeader(tile: .icon("tray.fill"), title: "Inbox",
                           subtitle: Self.subtitle(queue: queue, kept: kept, snoozed: snoozed.count, workbench: workbench)) {
                if let inbox = library.inbox {
                    Button { env.navigator.setListViewMode(.document, for: inbox.id) } label: {
                        Image(systemName: "doc.text").font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), radius: 7,
                                                    padding: EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5),
                                                    foreground: NX.ink(0.45), hoverForeground: NX.ink))
                    .help("Document")
                    .accessibilityLabel("Show as Document")
                }
            }
            Group {
                // One card for the whole session, as in the design: it takes
                // each task in turn, so the progress dots can slide between them.
                if let task = queue.first {
                    NXTriageCard(task: task, remaining: queue.count, now: now)
                } else {
                    NXTriageEmpty(hasKept: !kept.isEmpty)
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
        let groups = NextListScreen.completedGroups(library.tasks(in: inbox.id), in: inbox.id, workbench: workbench,
                                                    showsCompleted: inbox.showsCompleted(default: env.settings.showsCompletedTasks),
                                                    inDocument: Set(documentRowIDs))
        NXPage(rowIDs: documentRowIDs + NXGroupsStack.rowIDs(groups, workbench: workbench)) {
            NXScreenHeader(tile: .icon("tray.fill"), title: "Inbox",
                           subtitle: NextInboxScreen.subtitle(queue: library.inboxQueue(workbench),
                                                              kept: library.keptInbox(workbench),
                                                              snoozed: library.snoozedInbox().count, workbench: workbench)) {
                Button { env.navigator.setListViewMode(.tasks, for: inbox.id) } label: {
                    Image(systemName: "rectangle.stack").font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.07), radius: 7,
                                                padding: EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5),
                                                foreground: NX.ink(0.45), hoverForeground: NX.ink))
                .help("Triage")
                .accessibilityLabel("Show as Triage")
            }
            NXDocumentOutline(list: inbox)
                // The Turn into card draws over the Completed group.
                .zIndex(1)
                .onPreferenceChange(NXDocumentRowsKey.self) { documentRowIDs = $0 }
            // The design's 20s clock, so Completed's done-ago chips move on.
            TimelineView(.periodic(from: .now, by: 20)) { context in
                NXGroupsStack(groups: groups, options: NXRowOptions(showList: false, listID: inbox.id,
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
    /// The edit line has the keyboard.
    @FocusState private var editFocused: Bool

    var body: some View {
        let workbench = env.workbench
        let exit = workbench.triageExit
        let lifted = liftedID == task.id
        let editing = workbench.triageEdit?.taskID == task.id
        // The design's 22/1.3 over SwiftUI's 26pt line: 2.6pt between lines,
        // half of it above the first and below the last.
        let titleLeading = 22 * 1.3 - NX.lineHeight(22)
        VStack(alignment: .leading, spacing: 0) {
            topLine
            Group {
                if editing {
                    editLine
                } else {
                    Text(task.displayTitle)
                        .font(.system(size: 22, weight: .medium))
                        .kerning(-0.11)
                        .lineSpacing(titleLeading)
                        .foregroundStyle(NX.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        // A click on the title edits it, as R does.
                        .contentShape(Rectangle())
                        .onTapGesture { workbench.beginTriageEdit(task) }
                        .help("Edit the title, or type a date, @list, #label, !priority or ~estimate (R)")
                        .accessibilityAction(named: "Edit") { workbench.beginTriageEdit(task) }
                }
            }
            .padding(.top, 12 + titleLeading / 2)
            .padding(.horizontal, 18)
            .padding(.bottom, 4 + titleLeading / 2)
            // What the task holds, so it can be filed without opening it: its
            // note's words, without the Markdown they're written in.
            let note = editing ? "" : NoteMarkdown.plainText(task.note)
            if !note.isEmpty {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(NX.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
                    .accessibilityLabel("Note: \(note)")
            }
            HStack(spacing: 6) {
                ForEach(editing ? editChips : chips) { chip in
                    if chip.schedules { NXScheduleChip(task: task, chip: chip) } else { NXChip(chip: chip) }
                }
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
        .offset(x: exit == .left ? -90 : exit == .right || exit == .snooze ? 90 : 0,
                y: exit == .up ? -26 : exit == .down || exit == .snooze ? 26 : 0)
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
        // An edit line left open on a card that moved on goes with it.
        .onChange(of: task.id) { _, _ in
            if let line = workbench.triageEdit, line.taskID != task.id { workbench.triageEdit = nil }
        }
    }

    /// The card's edit line, in the title's place: the title to keep or
    /// change, and the capture grammar's tokens to add. Return writes it
    /// over the task, filing it when it names a list and dating it when it
    /// names a day; Escape puts it away.
    private var editLine: some View {
        let workbench = env.workbench
        return TextField("Title, a date, @list, #label, !priority, ~estimate",
                         text: Binding(get: { workbench.triageEdit?.text ?? "" },
                                       set: { workbench.triageEdit?.text = $0 }))
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .medium))
            .kerning(-0.11)
            .foregroundStyle(NX.ink)
            .focused($editFocused)
            .onSubmit { workbench.commitTriageEdit(task) }
            .onExitCommand { workbench.triageEdit = nil }
            .onAppear { DispatchQueue.main.async { editFocused = true } }
            .accessibilityLabel("Edit task")
            .accessibilityHint("Type a new title, or a date, @list, #label, !priority or ~estimate. Return applies it, Escape cancels.")
            .accessibilityIdentifier("triage.edit")
    }

    /// What the edit line will write, as capture's chips preview it.
    private var editChips: [NXChipModel] {
        guard let line = env.workbench.triageEdit, line.taskID == task.id else { return [] }
        let parse = CaptureParse(line.text, parsesDates: env.settings.parsesNaturalLanguageDates, reference: now,
                                 lists: library.lists.map { ($0.id, $0.displayTitle) })
        return parse.chips(for: parse.snapshot(), forToday: false, now: now).map { chip in
            var model = NXChipModel.capture(chip, library: library)
            // Here a chip only previews; the line itself is edited.
            model.raw = nil
            return model
        }
    }

    private var chips: [NXChipModel] {
        var chips: [NXChipModel] = []
        if let due = task.dueDate {
            // As a row's due chip reads it: an earlier day is overdue, in red.
            let offset = NXFormat.dayOffset(due, now: now)
            chips.append(NXChipModel(id: "due", label: NXFormat.dueLabel(due, now: now),
                                     icon: offset < 0 ? "exclamationmark.circle.fill" : "calendar",
                                     tone: offset < 0 ? .over : offset == 0 ? .accent : .neutral, fill: offset < 0,
                                     schedules: true))
        }
        if let recurrence = task.recurrence {
            chips.append(NXChipModel(id: "repeat", label: recurrence.displayText, icon: "repeat"))
        }
        if task.priority != .none {
            // Only High reads as urgent, in red; the others name their level
            // in the chip's quiet ink, which stays legible on the card.
            chips.append(NXChipModel(id: "prio", label: "\(task.priority.title) priority", icon: "flag.fill",
                                     tone: task.priority == .high ? .over : .neutral))
        }
        for id in task.labelIDs {
            if let label = library.label(id) {
                chips.append(NXChipModel(id: "label-\(id)", label: label.name, tone: .label(label.nxColor)))
            }
        }
        // Its subtasks go with it, and its files.
        let subtasks = task.listID.map { listID in library.tasks(in: listID).filter { $0.parentID == task.id } } ?? []
        if !subtasks.isEmpty {
            let open = subtasks.count { !$0.isCompleted }
            chips.append(NXChipModel(id: "subtasks", label: open == subtasks.count ? "\(open) subtask\(open == 1 ? "" : "s")"
                                     : "\(open) of \(subtasks.count) subtasks open", icon: "checklist"))
        }
        let files = env.store.attachments(for: task.id).count
        if files > 0 {
            chips.append(NXChipModel(id: "files", label: "\(files) file\(files == 1 ? "" : "s")", icon: "paperclip"))
        }
        return chips
    }

    private var topLine: some View {
        let workbench = env.workbench
        let total = min(12, workbench.reviewed + remaining)
        // Each label takes the design's line-height 1 box, so the row is its
        // 11pt, the count's and age's.
        return HStack(spacing: 10) {
            Text("Triage")
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.84)
                .textCase(.uppercase)
                .foregroundStyle(NX.textTertiary)
                .padding(.vertical, (10.5 - NX.lineHeight(10.5)) / 2)
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index <= workbench.reviewed ? style.accent : NX.ink(0.12))
                        .frame(width: index == workbench.reviewed ? 16 : 5, height: 5)
                }
            }
            // The design's `transition: all 300ms ease`.
            .animation(NX.cssEase(300), value: workbench.reviewed)
            Text("\(remaining) to go")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NX.textTertiary)
                .padding(.vertical, (11 - NX.lineHeight(11)) / 2)
            Spacer(minLength: 8)
            Text("Captured \(NXFormat.relative(task.createdAt, now: now))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NX.textTertiary)
                .padding(.vertical, (11 - NX.lineHeight(11)) / 2)
        }
        .padding(.top, 14)
        .padding(.horizontal, 18)
    }

    private var fileInto: some View {
        let workbench = env.workbench
        let picked = workbench.triagePickedDay.map { NXFormat.dueLabel(NXFormat.day(offset: $0, now: now), now: now) }
        let suggested = library.suggestedDestination(for: task)
        let numbered = Array(library.destinations.prefix(9))
        return VStack(alignment: .leading, spacing: 0) {
            caps(picked.map { "File into · due \($0)" } ?? "File into")
            VStack(alignment: .leading, spacing: 2) {
                // The list its words point to, which 0 files into, is marked
                // among the numbered ones, or leads them when it's further down.
                if let suggested, !numbered.contains(where: { $0.id == suggested.id }) {
                    NXTriageListRow(key: "0", list: suggested, count: library.openCount(in: suggested.id), suggested: true) {
                        workbench.triage(task, action: .left, listID: suggested.id)
                    }
                }
                ForEach(Array(numbered.enumerated()), id: \.element.id) { index, list in
                    NXTriageListRow(key: "\(index + 1)", list: list, count: library.openCount(in: list.id),
                                    suggested: list.id == suggested?.id) {
                        workbench.triage(task, action: .left, listID: list.id)
                    }
                }
                // Every list, by name, in the palette.
                if !library.destinations.isEmpty {
                    NXTriageMoreRow { workbench.fileFromPalette(task) }
                }
            }
        }
    }

    private var schedule: some View {
        let workbench = env.workbench
        let load = Dictionary(grouping: library.open.compactMap { $0.dueDate.map { NXFormat.dayOffset($0, now: now) } }, by: { $0 })
            .mapValues(\.count)
        // The hint's 10.5/1.4 over a 13pt line: 1.7pt between lines, half of
        // it above the first and below the last.
        let hintLeading = 10.5 * 1.4 - NX.lineHeight(10.5)
        let picked = workbench.triagePickedDay
        return VStack(alignment: .leading, spacing: 0) {
            caps("Or schedule — stays in Inbox")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 4), spacing: 4) {
                ForEach(0..<8, id: \.self) { offset in
                    NXTriageDay(offset: offset, load: load[offset] ?? 0, now: now, picked: picked == offset) {
                        // ⇧-click picks the day for the list it's filed into next.
                        if NSEvent.modifierFlags.contains(.shift) {
                            workbench.triagePickedDay = picked == offset ? nil : offset
                        } else {
                            workbench.triage(task, action: .up, offset: offset)
                        }
                    }
                }
            }
            Text(picked == nil ? "T today · M tomorrow · ⇧ picks a day to file with"
                 : "A list's number files it with that day · esc unpicks")
                .font(.system(size: 10.5, weight: .medium))
                .lineSpacing(hintLeading)
                .foregroundStyle(NX.textQuaternary)
                .padding(.top, 8 + hintLeading / 2)
                .padding(.bottom, hintLeading / 2)
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
            // Out of the way until a day, back on its own that morning.
            Menu {
                ForEach(Workbench.snoozeDays(now: now), id: \.title) { option in
                    Button("\(option.title) · \(NXFormat.dueLabel(option.day, now: now))") {
                        workbench.triage(task, action: .snooze, until: option.day)
                    }
                }
            } label: {
                footerLabel("Snooze", icon: "moon.zzz")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.06), radius: 8,
                                            padding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10),
                                            foreground: NX.textSecondary))
            .fixedSize()
            .help("Snooze (S until tomorrow, ⇧S until next week)")
            .accessibilityLabel("Snooze")
            // Opens the inspector without focusing the card, so triage keys still apply once it closes.
            // Only its fill changes on hover, as the design's.
            footerButton("Details", icon: "sidebar.right", key: "↩", hover: NX.ink(0.06)) {
                env.navigator.openTask(task.id)
            }
            Spacer(minLength: 8)
            // The label takes the design's line-height 1 box, so the button
            // is its 28pt: 8 + 12 + 8.
            Button { workbench.triage(task, action: .right) } label: {
                Text("Keep for later").font(.system(size: 12, weight: .semibold))
                    .padding(.vertical, (12 - NX.lineHeight(12)) / 2)
            }
            .buttonStyle(NXHoverButtonStyle(hover: NX.primaryButtonHover, rest: NX.primaryButton, radius: 8,
                                            padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
                                            foreground: NX.onPrimary, hoverForeground: NX.onPrimary))
            .help("Keep for later (→)")
            .accessibilityLabel("Keep for later")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(NX.ink(0.02))
        .overlay(alignment: .top) { Rectangle().fill(NX.ink(0.08)).frame(height: 0.5) }
    }

    private func caps(_ text: String) -> some View {
        NXCapsTitle(text: text)
            // Wraps, as the design's does, when the column is narrow.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 8)
    }

    /// The design's 15pt icon box and 12/1 label, so each button is its
    /// 29pt, 7 + 15 + 7, whatever the symbol's height, and the footer its 53pt.
    private func footerLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium))
                .frame(height: 15)
            Text(title).font(.system(size: 12, weight: .medium))
                .padding(.vertical, (12 - NX.lineHeight(12)) / 2)
        }
    }

    private func footerButton(_ title: String, icon: String, key: String, hover: Color, hoverText: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) { footerLabel(title, icon: icon) }
            .buttonStyle(NXHoverButtonStyle(hover: hover, radius: 8,
                                            padding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10),
                                            foreground: NX.textSecondary, hoverForeground: hoverText))
            .help("\(title) (\(key))")
            .accessibilityLabel(title)
    }
}

private struct NXTriageListRow: View {
    let key: String
    let list: TaskList
    let count: Int
    /// The list the card's words point to, which 0 files into.
    var suggested = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Text(key)
                .font(NX.mono(10, weight: .semibold))
                .foregroundStyle(NX.textQuaternary)
                .frame(width: 16, height: 16)
            NXListGlyph(list: list, size: 13)
            // The design's 13/1, wrapping inside the row when the column is
            // narrow: exact 13pt lines, which trim SwiftUI's 16 from below,
            // raised by half the trim so the ink is centred as CSS centres it.
            // Never inside a word: a column too narrow for its longest one
            // gets one truncated line instead.
            Text(list.displayTitle).font(.system(size: 13, weight: .medium)).foregroundStyle(NX.ink)
                .lineHeight(.exact(points: 13))
                .offset(y: (13 - NX.lineHeight(13)) / 2)
                .nxWordFloor(NX.wordFloor(list.displayTitle, size: 13, weight: .medium))
            if suggested {
                Image(systemName: "sparkle")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(NX.ink(0.5))
                    .help("Suggested from the task's words: 0 files into it")
            }
            // The design's `flex: 1`, so the name can come within two gaps of the count.
            Spacer(minLength: 0)
            Text("\(count)").font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(NX.textTertiary)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(hovering ? NX.hoverFill : suggested ? NX.ink(0.035) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("File into \(list.displayTitle)" + (suggested ? ", suggested" : ""))
        .accessibilityValue("\(count) open")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

/// "Other list…" under the numbered lists: the palette, listing every list
/// to type the name of, nested ones by their path.
private struct NXTriageMoreRow: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Text("L")
                .font(NX.mono(10, weight: .semibold))
                .foregroundStyle(NX.textQuaternary)
                .frame(width: 16, height: 16)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NX.textTertiary)
                .frame(width: 13)
            Text("Other list…").font(.system(size: 13, weight: .medium)).foregroundStyle(NX.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(hovering ? NX.ink(0.05) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .help("File into any list by name (L)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("File into another list")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

private struct NXTriageDay: View {
    let offset: Int
    let load: Int
    let now: Date
    /// ⇧ picked it for the list the card is filed into next.
    var picked = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let date = NXFormat.day(offset: offset, now: now)
        // A button, which Tab reaches with Keyboard navigation on. Both
        // labels take the design's line-height 1 box, so the tile is its
        // 52.5pt: 8 + 9.5 + 4 + 16 + 4 + 4 + 7.
        Button(action: action) {
            VStack(spacing: 4) {
                Text(offset == 0 ? "Today" : offset == 1 ? "Tmrw" : date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(0.38)
                    .textCase(.uppercase)
                    .foregroundStyle(picked ? NX.ink : NX.textTertiary)
                    .padding(.vertical, (9.5 - NX.lineHeight(9.5)) / 2)
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 16, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(NX.ink)
                    .padding(.vertical, (16 - NX.lineHeight(16)) / 2)
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
            .background(picked ? NX.selectedFill : hovering ? NX.hoverFill : NX.ink(0.035),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                if picked { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(NX.ink(0.5), lineWidth: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NXBareButtonStyle(radius: 9))
        .onHover { hovering = $0 }
        .help("Schedule, or ⇧-click to pick the day for the list it's filed into")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schedule for " + (offset == 0 ? "today" : offset == 1 ? "tomorrow"
            : date.formatted(.dateTime.weekday(.wide).day().month(.wide))))
        .accessibilityValue(load == 0 ? "Nothing due" : "\(load) already due")
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { action() }
    }
}

private struct NXTriageEmpty: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.nextLibrary) private var library
    /// Tasks kept for later this session are still in the Inbox.
    let hasKept: Bool

    var body: some View {
        let workbench = env.workbench
        // Nothing triaged and nothing kept, as on a first run, is just empty.
        let untouched = workbench.reviewed == 0 && !hasKept
        // The summary's 13/1.45 over a 16pt line: 2.85pt between lines, half
        // of it above the first and below the last.
        let summaryLeading = 13 * 1.45 - NX.lineHeight(13)
        HStack(spacing: 18) {
            Circle().fill(untouched ? NX.ink(0.05) : NX.green.opacity(0.12))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: untouched ? "tray" : "checkmark")
                    .font(.system(size: 22, weight: untouched ? .medium : .bold))
                    .foregroundStyle(untouched ? NX.ink(0.4) : NX.greenText))
            VStack(alignment: .leading, spacing: 4) {
                Text(untouched ? "Inbox is empty" : "Inbox triaged")
                    .font(NX.serif(26)).padding(.vertical, NX.serifLeading(26, lineHeight: 1.1)).foregroundStyle(NX.ink)
                Text(untouched ? "Tasks you capture land here, ready to sort into lists." : "\(workbench.reviewed) reviewed this session.")
                    .font(.system(size: 13))
                    .lineSpacing(summaryLeading)
                    .foregroundStyle(NX.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, summaryLeading / 2)
            }
            Spacer(minLength: 8)
            // Kept tasks come back for review; with none kept, a new task goes in.
            // The design's 600 12/1, so the button is its 28pt: 8 + 12 + 8.
            Button {
                if hasKept {
                    workbench.kept = []
                    workbench.reviewed = 0
                } else {
                    workbench.openCapture(listID: library.inbox?.id, forToday: false)
                }
            } label: {
                Text(hasKept ? "Review kept tasks" : "New task")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.vertical, (12 - NX.lineHeight(12)) / 2)
            }
            .buttonStyle(NXHoverButtonStyle(hover: NX.ink(0.1), rest: NX.ink(0.06), radius: 8,
                                            padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
                                            foreground: NX.textSecondary))
            .help(hasKept ? "" : "New task (N)")
        }
        .padding(.vertical, 34)
        .padding(.horizontal, 28)
        .background(NX.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .nxCardShadow(radius: 16, hairline: 0.1, drop: 0.06, y: 10, blur: 30)
        .modifier(NXLiftIn())
    }
}
