//
//  TriageScreen.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI

/// Triage (mockup 08), a full-screen cover dealing one card at a time from
/// the pass its switch picks. The Inbox, oldest first: pick a list to move it
/// to (the one its words point to first, every list behind More), a day for
/// it, or both, then Next files it in one step: a day alone leaves it in the
/// Inbox. A tap on the title edits it, tokens and all. No date: the lists'
/// tasks with no day yet, in the lists' order, where a day's chip dates the
/// card at once. Either way Delete sends it to Trash, ✓ marks it done,
/// Snooze puts it away until a day, when it comes back by itself, and Later
/// sets it aside for now. Each is one step with Undo in the tray.
struct TriageScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.olStyle) private var style
    /// The documents' blocks, for the lists' order No date deals in.
    @Query(filter: #Predicate<Block> { $0.trashID == nil }) private var blocks: [Block]
    @State private var picksDate = false
    /// The list and day picked on the card on show, for Next.
    @State private var draft = TriageDraft()
    /// The card on show, so a date picked for one never lands on the next.
    @State private var shownCard: UUID?
    /// The day picked for a No date card, given once the picker has gone:
    /// the next card mustn't come in under a sheet still closing.
    @State private var pickedDay: (id: UUID, date: Date, includesTime: Bool)?
    /// More's list picker, for the Inbox card on show.
    @State private var picksList = false
    /// Snooze's own date picker, and the day picked there, given once it has
    /// gone, as No date's is.
    @State private var picksSnooze = false
    @State private var snoozeDay: (id: UUID, date: Date)?

    var body: some View {
        @Bindable var navigator = env.navigator
        let mode = navigator.triageMode
        let session = env.triage(for: mode)
        let queue = switch mode {
        case .inbox: library.inboxQueue(triage: session, closing: env.actions.closing, now: env.now)
        case .undated: library.undatedQueue(blocks: blocks, triage: session, closing: env.actions.closing, now: env.now)
        }
        let reviewed = session.reviewed(queue: queue)
        let total = reviewed + queue.count
        let card = queue.first
        // A card with many lists, or at large text sizes, scrolls; the
        // finished state fills the screen.
        OLScreen(identifier: PhoneRoute.triage(mode).screenIdentifier, scrolls: card != nil) {
            OLTopBar {
                OLIconButton("xmark", label: "Close triage", kind: .bare, iconSize: 22) { navigator.dismissCover() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("triage.close")
            } trailing: {
                // "1 of 6" as it goes, and "6 of 6" once it's done.
                if total > 0 {
                    Text("\(card == nil ? reviewed : reviewed + 1) of \(total)")
                        .font(OLFont.eyebrow)
                        .foregroundStyle(OL.muted)
                        .padding(.horizontal, 10)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("triage.position")
                }
            }
        } content: {
            OLViewPicker("Triage", options: TriageMode.allCases.map { pass in
                OLViewPicker.Option(value: pass, title: pass.title, symbol: pass.symbol, identifier: "triage.mode.\(pass.rawValue)")
            }, selection: $navigator.triageMode)
                .padding(.top, 6)
            OLProgressBar(value: total == 0 ? 1 : Double(reviewed) / Double(total), tint: OL.info,
                          turnsGreenWhenFull: false)
                .padding(.top, 16)
            if let card {
                Group {
                    switch mode {
                    case .inbox:
                        TriageCard(task: card, now: env.now, draft: $draft, picksDate: $picksDate, picksList: $picksList)
                    case .undated:
                        UndatedTriageCard(task: card, now: env.now, picksDate: $picksDate) { date(card, on: $0) }
                    }
                }
                .id(card.id)
                .sheet(isPresented: $picksList) {
                    let id = card.id
                    ListPickerSheet(title: "Move to", excluding: Set([card.listID].compactMap(\.self)),
                                    suggested: library.suggestedDestination(for: card)) { list in
                        guard shownCard == id else { return }
                        draft.listID = list.id
                    }
                }
                // With Reduce Motion the next card fades in rather than sliding.
                .transition(style.reduceMotion ? .opacity
                            : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                .padding(.top, 24)
                Spacer(minLength: 0)
            } else {
                finished(mode, reviewed: reviewed)
                    .frame(maxHeight: .infinity)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let card { buttons(card, mode: mode) }
        }
        .animation(style.fading(.snappy(duration: 0.3)), value: card?.id)
        .animation(style.fading(.snappy(duration: 0.2)), value: draft)
        .onChange(of: card?.id, initial: true) { _, id in
            draft = TriageDraft()
            shownCard = id
        }
        .sheet(isPresented: $picksDate, onDismiss: datePicked) {
            if let card {
                let id = card.id
                switch mode {
                case .inbox:
                    DuePickerSheet(date: pickerDate(for: card), includesTime: draft.timed ?? card.includesTime,
                                   now: env.now, clears: false) { date, timed in
                        guard shownCard == id else { return }
                        draft.due = date
                        draft.timed = date == nil ? nil : timed
                    }
                case .undated:
                    DuePickerSheet(date: nil, includesTime: false, now: env.now, clears: false) { date, timed in
                        guard shownCard == id, let date else { return }
                        pickedDay = (id, date, timed)
                    }
                }
            }
        }
        .onAppear {
            env.triage.begin()
            env.undatedTriage.begin()
        }
    }

    private func buttons(_ task: Block, mode: TriageMode) -> some View {
        let session = env.triage(for: mode)
        let calendar = env.settings.calendar
        return OLActionDock {
            OLIconButton("trash", label: "Delete", kind: .bad, size: .large) {
                if env.actions.trash([task]) { session.finish(task.id) }
            }
            .accessibilityIdentifier("triage.delete")
            OLIconButton("checkmark", label: "Already done", kind: .ok, size: .large) {
                let due = task.recurrence != nil ? task.dueDate : nil
                let repeats = task.recurrence != nil
                env.actions.complete([task])
                // A repeat rolls to its next date and stays open: set it
                // aside once it has, as the Mac's triage does, so the next
                // card comes, and Undo brings it back.
                if let due { session.rollOn(task.id, from: due) }
                else if repeats { session.keep(task.id) }
                else { session.finish(task.id) }
            }
            .accessibilityIdentifier("triage.done")
            // Away until a day, when it comes back to triage by itself.
            Menu {
                ForEach(Store.snoozeDays(from: env.now, calendar: calendar), id: \.title) { option in
                    Button("\(option.title) · \(CompactText.day(option.day, now: env.now, calendar: calendar))") {
                        snooze(task, until: option.day, session: session)
                    }
                }
                Button("Pick a date…", systemImage: "calendar") { picksSnooze = true }
            } label: {
                Image(systemName: "moon.zzz")
                    .font(.system(size: OLIconButton.Size.large.icon, weight: .semibold))
                    .foregroundStyle(OL.ink)
                    .frame(width: OLIconButton.Size.large.rawValue, height: OLIconButton.Size.large.rawValue)
                    .background(Circle().fill(OL.sunken))
                    .contentShape(.circle)
            }
            .buttonStyle(OLPressStyle())
            .accessibilityLabel("Snooze")
            .accessibilityHint("Puts the task away until a day, when it comes back by itself")
            .accessibilityIdentifier("triage.snooze")
            Spacer(minLength: 0)
            // No date's days date the card as they're tapped, so it never needs Next.
            if mode == .undated || draft.isEmpty {
                Button("Later") { session.keep(task.id) }
                    .buttonStyle(.ol(.ink, size: .large))
                    .accessibilityIdentifier("triage.later")
            } else {
                Button { file(task) } label: { Label("Next", systemImage: "arrow.right") }
                    .buttonStyle(.ol(.primary, size: .large))
                    .accessibilityIdentifier("triage.next")
                    .accessibilityHint(draft.summary(list: draft.listID.flatMap { env.store.list(id: $0) }, now: env.now,
                                                     calendar: env.settings.calendar))
            }
        }
        .sheet(isPresented: $picksSnooze, onDismiss: { snoozePicked(session: session) }) {
            let id = task.id
            DuePickerSheet(title: "Snooze until", date: nil, includesTime: false, now: env.now, clears: false) { date, _ in
                guard shownCard == id, let date else { return }
                snoozeDay = (id, date)
            }
        }
    }

    /// Snoozes the card on show: it leaves the pass, and comes back to
    /// triage that morning; the tray's Undo brings it back now.
    private func snooze(_ task: Block, until day: Date, session: TriageSession) {
        env.actions.snooze([task], until: day)
        env.haptics.play(.selection)
        session.finish(task.id)
    }

    /// Snoozes the card the picker was opened on, once it has gone.
    private func snoozePicked(session: TriageSession) {
        guard let picked = snoozeDay else { return }
        snoozeDay = nil
        guard let task = env.store.block(id: picked.id) else { return }
        snooze(task, until: picked.date, session: session)
    }

    /// The pass done: how many it reviewed, and for No date, the tasks it
    /// set aside to go over again.
    @ViewBuilder private func finished(_ mode: TriageMode, reviewed: Int) -> some View {
        let navigator = env.navigator
        switch mode {
        case .inbox:
            OLEmptyState(symbol: "checkmark", tint: OL.successText, fill: OL.successSoft, title: "Inbox triaged",
                         message: reviewed == 0 ? "Nothing is waiting in the Inbox."
                            : "\(reviewed) reviewed this session.",
                         actionTitle: "Back to Inbox") { navigator.dismissCover() }
        case .undated:
            // With none left on the pass, what's still undated was set aside.
            let kept = library.undatedCount(kept: [], closing: env.actions.closing, now: env.now)
            if reviewed == 0, kept == 0 {
                OLEmptyState(symbol: "checkmark", tint: OL.successText, fill: OL.successSoft, title: "Nothing without a date",
                             message: "Every open task in your lists has a day.",
                             actionTitle: "Back to Inbox") { navigator.dismissCover() }
            } else {
                OLEmptyState(symbol: "checkmark", tint: OL.successText, fill: OL.successSoft, title: "All triaged",
                             message: reviewed == 0 ? "\(kept) set aside for later." : "\(reviewed) reviewed this session.",
                             actionTitle: kept > 0 ? "Review what you kept" : "Back to Inbox") {
                    if kept > 0 { env.undatedTriage.reviewKept() } else { navigator.dismissCover() }
                }
            }
        }
    }

    /// Files the card as picked: moved to its list, dated, or both, as one
    /// step. Moved, it leaves the Inbox; only dated, it waits there aside.
    private func file(_ task: Block) {
        let list = draft.listID.flatMap { env.store.list(id: $0) }
        let moves = list.map { $0.id != task.listID } ?? false
        // The Inbox picked for an Inbox task, with no day: nothing to file.
        guard moves || draft.due != nil else { return env.triage.keep(task.id) }
        guard env.actions.file(task, to: list, due: draft.due, includesTime: draft.timed) else { return }
        if moves {
            env.triage.finish(task.id)
        } else if let due = env.store.block(id: task.id)?.dueDate ?? draft.due {
            env.triage.schedule(task.id, due: due)
        }
    }

    /// Gives a No date card its day as one step: it leaves the pass, and the
    /// tray's Undo brings it back.
    private func date(_ task: Block, on day: Date, includesTime: Bool? = nil) {
        guard env.actions.file(task, to: nil, due: day, includesTime: includesTime) else { return }
        env.haptics.play(.selection)
        env.undatedTriage.finish(task.id)
    }

    /// Dates the No date card the picker was opened on, once it has gone.
    private func datePicked() {
        guard let picked = pickedDay else { return }
        pickedDay = nil
        guard let task = env.store.block(id: picked.id) else { return }
        date(task, on: picked.date, includesTime: picked.includesTime)
    }

    /// Where the picker opens: the day picked, at the card's own time when
    /// it has one and a chip gave only the day; else the card's date.
    private func pickerDate(for card: Block) -> Date? {
        guard let due = draft.due else { return card.dueDate }
        guard draft.timed == nil, card.includesTime, let time = card.dueDate else { return due }
        let clock = env.settings.calendar.dateComponents([.hour, .minute], from: time)
        return env.settings.calendar.date(bySettingHour: clock.hour ?? 9, minute: clock.minute ?? 0, second: 0, of: due) ?? due
    }
}

/// What's picked on the card before Next: a list, a day, or both.
struct TriageDraft: Equatable {
    var listID: UUID?
    var due: Date?
    /// Set by the picker; nil for a chip's day, which keeps the card's time.
    var timed: Bool?

    var isEmpty: Bool { listID == nil && due == nil }

    /// "Files it in Home, due tomorrow", for Next's hint.
    func summary(list: TaskList?, now: Date, calendar: Calendar) -> String {
        let day = due.map { "due \(CompactText.day($0, now: now, calendar: calendar).lowercased())" }
        return ["Files it", list.map { "in \($0.displayTitle)" }, day].compactMap(\.self).joined(separator: " ")
    }
}

private struct TriageCard: View {
    let task: Block
    let now: Date
    @Binding var draft: TriageDraft
    @Binding var picksDate: Bool
    @Binding var picksList: Bool
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    /// The edit line's text while it's open, in the title's place.
    @State private var editing: String?
    @FocusState private var editFocused: Bool

    /// The lists Move to shows as chips before More.
    private static let shownLists = 8

    var body: some View {
        let calendar = env.settings.calendar
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 0) {
                TriageCardHeader(caps: "Triage", task: task)
                if let editing {
                    editLine(editing)
                } else {
                    Button { open() } label: {
                        Text(task.displayTitle)
                            .font(OLFont.triageTitle)
                            .foregroundStyle(OL.ink)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint("Edits the title, or adds a date, @list, #label, !priority or ~estimate")
                    .accessibilityIdentifier("triage.title")
                }
                Text(CompactText.captured(task.createdAt, now: now))
                    .font(OLFont.meta)
                    .foregroundStyle(OL.muted)
                    .padding(.top, 6)
                TriageContext(task: task, now: now)
            }
            VStack(alignment: .leading, spacing: 10) {
                OLGroupHeader("Move to").padding(.horizontal, -4)
                OLFlowLayout {
                    let suggested = library.suggestedDestination(for: task)
                    let lists = moveTargets(suggested: suggested)
                    ForEach(lists) { list in
                        let on = draft.listID == list.id
                        let isSuggested = list.id == suggested?.id
                        OLChipButton(OLChip(name(of: list), symbol: isSuggested ? "sparkles" : nil,
                                            glyph: isSuggested ? nil : list.icon, style: on ? .on : .plain)) {
                            draft.listID = on ? nil : list.id
                        }
                        .accessibilityLabel(name(of: list) + (isSuggested ? ", suggested" : ""))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    if library.destinations.count > Self.shownLists {
                        OLChipButton(OLChip("More", symbol: "magnifyingglass")) { picksList = true }
                            .accessibilityLabel("More lists")
                            .accessibilityHint("Find any list by name")
                            .accessibilityIdentifier("triage.moreLists")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                OLGroupHeader("When").padding(.horizontal, -4)
                OLFlowLayout {
                    let presets = PhoneDay.allCases
                    ForEach(presets) { day in
                        let date = day.date(now: now, calendar: calendar)
                        let on = draft.timed == nil && draft.due.map { calendar.isDate($0, inSameDayAs: date) } == true
                        OLChipButton(OLChip(day.title, style: on ? .on : .plain)) {
                            draft.due = on ? nil : date
                            draft.timed = nil
                        }
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    // A date from the picker, not one of the presets, shows on it.
                    let custom = draft.due != nil && (draft.timed != nil || !presets.contains { day in
                        draft.due.map { calendar.isDate($0, inSameDayAs: day.date(now: now, calendar: calendar)) } == true
                    })
                    OLChipButton(OLChip(custom ? pickedLabel(calendar: calendar) : "", icon: .calendar,
                                        style: custom ? .on : .plain)) { picksDate = true }
                        .accessibilityLabel(custom ? "Date, \(pickedLabel(calendar: calendar))" : "Pick a date")
                        .accessibilityAddTraits(custom ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .olCard()
    }

    /// The suggested list first, then the lists in the sidebar's order, up
    /// to `shownLists`, and the one picked from More when it's further down.
    private func moveTargets(suggested: TaskList?) -> [TaskList] {
        var lists = library.destinations
        if let suggested { lists = [suggested] + lists.filter { $0.id != suggested.id } }
        var shown = Array(lists.prefix(Self.shownLists))
        if let picked = library.list(draft.listID), !shown.contains(where: { $0.id == picked.id }) { shown.append(picked) }
        return shown
    }

    /// A nested list by its path, as Move to has no room to show where it is otherwise.
    private func name(of list: TaskList) -> String {
        library.hierarchy.parent(of: list.id) == nil ? list.displayTitle : library.hierarchy.path(for: list.id)
    }

    /// "Fri 25", "Fri 25, 18:00".
    private func pickedLabel(calendar: Calendar) -> String {
        guard let due = draft.due else { return "" }
        return CompactText.captureWhen(due, includesTime: draft.timed ?? false, now: now, calendar: calendar)
    }

    // MARK: Edit line

    private func open() {
        editing = task.displayTitle
        editFocused = true
    }

    /// The title as a capture line: a new title, and tokens. Done writes the
    /// title, repeat, labels, priority and estimate over the task; a day it
    /// names, and an `@` list, are picked on the card for Next.
    private func editLine(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title, a date, @list, #label…", text: Binding(get: { editing ?? "" }, set: { editing = $0 }),
                      axis: .vertical)
                .font(OLFont.triageTitle)
                .foregroundStyle(OL.ink)
                .focused($editFocused)
                .submitLabel(.done)
                .onSubmit { apply(text: editing ?? text) }
                // A field that wraps takes Return as a new line; here it's Done.
                .onChange(of: editing) { _, typed in
                    guard let typed, typed.contains("\n") else { return }
                    apply(text: typed.replacingOccurrences(of: "\n", with: " "))
                }
                .accessibilityIdentifier("triage.edit")
            HStack(spacing: 16) {
                Button("Cancel") { editing = nil }
                    .buttonStyle(.olLink(small: true))
                Button("Done") { apply(text: editing ?? text) }
                    .buttonStyle(.olLink(strong: true, small: true))
                    .accessibilityIdentifier("triage.editDone")
            }
        }
        .padding(.top, 8)
        .onAppear { editFocused = true }
    }

    private func apply(text: String) {
        let parse = CaptureParse(text, parsesDates: env.settings.parsesNaturalLanguageDates, reference: now,
                                 lists: library.lists.map { ($0.id, $0.displayTitle) })
        var snapshot = parse.snapshot()
        if let due = snapshot.date {
            draft.due = due
            draft.timed = snapshot.includesTime
        }
        if let listID = parse.listID, listID != task.listID { draft.listID = listID }
        snapshot.date = nil
        snapshot.includesTime = false
        env.actions.write(snapshot, over: task)
        editing = nil
        editFocused = false
    }
}

/// The top of a triage card: what pass it's on, and Details, which opens
/// the task's page over triage, Back returning to the card.
private struct TriageCardHeader: View {
    let caps: String
    let task: Block
    @Environment(PhoneEnvironment.self) private var env

    var body: some View {
        HStack(alignment: .center) {
            Text(caps).olCaps().foregroundStyle(OL.infoText)
            Spacer(minLength: 8)
            OLIconButton("info.circle", label: "Details", kind: .bare, iconSize: 18) {
                env.navigator.open(.taskDetail(task.id))
            }
            .padding(.vertical, -12)
            .padding(.trailing, -10)
            .accessibilityHint("Opens the task's page")
            .accessibilityIdentifier("triage.details")
        }
    }
}

/// What a card's task holds, so it can be filed without opening it: its
/// note's first lines, then its day, priority, labels, subtasks and files.
private struct TriageContext: View {
    let task: Block
    let now: Date
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library

    var body: some View {
        let facts = facts
        if !task.note.isEmpty || !facts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !task.note.isEmpty {
                    Text(task.note)
                        .font(OLFont.meta)
                        .foregroundStyle(OL.ink)
                        .lineLimit(3)
                        .accessibilityLabel("Note: \(task.note)")
                }
                if !facts.isEmpty {
                    Text(facts.joined(separator: " · "))
                        .font(OLFont.meta)
                        .foregroundStyle(OL.muted)
                }
            }
            .padding(.top, 10)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("triage.context")
        }
    }

    private var facts: [String] {
        var facts: [String] = []
        if let due = CompactText.due(task.dueDate, includesTime: task.includesTime, now: now, calendar: env.settings.calendar) {
            facts.append(due.text)
        }
        if task.priority != .none { facts.append("\(task.priority.title) priority") }
        facts += task.labelIDs.compactMap { library.label($0) }.map { "#" + $0.name }
        let subtasks = task.listID.map { listID in library.tasks(in: listID).filter { $0.parentID == task.id } } ?? []
        if !subtasks.isEmpty { facts.append(subtasks.count == 1 ? "1 subtask" : "\(subtasks.count) subtasks") }
        let files = env.store.attachments(for: task.id).count
        if files > 0 { facts.append(files == 1 ? "1 file" : "\(files) files") }
        return facts
    }
}

/// A No date card: the task, its list and how long it has waited, and the
/// days it can have. A day's chip, or the picker's Set, dates it at once.
private struct UndatedTriageCard: View {
    let task: Block
    let now: Date
    @Binding var picksDate: Bool
    let date: (Date) -> Void
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library

    var body: some View {
        let calendar = env.settings.calendar
        let list = library.list(task.listID)
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 0) {
                TriageCardHeader(caps: "No date", task: task)
                Text(task.displayTitle)
                    .font(OLFont.triageTitle)
                    .foregroundStyle(OL.ink)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                // "🏡 Home · added 4 days ago": a nested list by its path.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let list { OLListGlyph(icon: list.icon, accent: list.accent.color, size: 13) }
                    Text([ListsTaskOverview.source(of: task, in: library), CompactText.added(task.createdAt, now: now)]
                        .compactMap(\.self).joined(separator: " · "))
                }
                .font(OLFont.meta)
                .foregroundStyle(OL.muted)
                .padding(.top, 6)
                TriageContext(task: task, now: now)
            }
            VStack(alignment: .leading, spacing: 10) {
                OLGroupHeader("When").padding(.horizontal, -4)
                OLFlowLayout {
                    ForEach(PhoneDay.allCases) { day in
                        OLChipButton(OLChip(day.title)) { date(day.date(now: now, calendar: calendar)) }
                            .accessibilityHint("Dates it and shows the next task")
                    }
                    OLChipButton(OLChip("", icon: .calendar)) { picksDate = true }
                        .accessibilityLabel("Pick a date")
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .olCard()
    }
}
