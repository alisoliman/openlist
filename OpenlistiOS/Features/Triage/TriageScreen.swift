//
//  TriageScreen.swift
//  OpenlistiOS
//

import SwiftData
import SwiftUI

/// Triage (mockup 08), a full-screen cover dealing one card at a time from
/// the pass its switch picks. The Inbox, oldest first: pick a list to move it
/// to, a day for it, or both, then Next files it in one step: a day alone
/// leaves it in the Inbox. No date: the lists' tasks with no day yet, in the
/// lists' order, where a day's chip dates the card at once. Either way Delete
/// sends it to Trash, ✓ marks it done, Later sets it aside for now. Each is
/// one step with Undo in the tray.
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

    var body: some View {
        @Bindable var navigator = env.navigator
        let mode = navigator.triageMode
        let session = env.triage(for: mode)
        let queue = switch mode {
        case .inbox: library.inboxQueue(triage: session, closing: env.actions.closing)
        case .undated: library.undatedQueue(blocks: blocks, triage: session, closing: env.actions.closing)
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
                        TriageCard(task: card, now: env.now, draft: $draft, picksDate: $picksDate)
                    case .undated:
                        UndatedTriageCard(task: card, now: env.now, picksDate: $picksDate) { date(card, on: $0) }
                    }
                }
                .id(card.id)
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
            let kept = library.undatedCount(kept: [], closing: env.actions.closing)
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
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library

    var body: some View {
        let calendar = env.settings.calendar
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Triage").olCaps().foregroundStyle(OL.infoText)
                Text(task.displayTitle)
                    .font(OLFont.triageTitle)
                    .foregroundStyle(OL.ink)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                Text(CompactText.captured(task.createdAt, now: now))
                    .font(OLFont.meta)
                    .foregroundStyle(OL.muted)
                    .padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 10) {
                OLGroupHeader("Move to").padding(.horizontal, -4)
                OLFlowLayout {
                    ForEach(library.destinations) { list in
                        let on = draft.listID == list.id
                        OLChipButton(OLChip(list.displayTitle, glyph: list.icon, style: on ? .on : .plain)) {
                            draft.listID = on ? nil : list.id
                        }
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                OLGroupHeader("When").padding(.horizontal, -4)
                OLFlowLayout {
                    let presets = [PhoneDay.today, .tomorrow, .weekend]
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

    /// "Fri 25", "Fri 25, 18:00".
    private func pickedLabel(calendar: Calendar) -> String {
        guard let due = draft.due else { return "" }
        return CompactText.captureWhen(due, includesTime: draft.timed ?? false, now: now, calendar: calendar)
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
                Text("No date").olCaps().foregroundStyle(OL.infoText)
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
