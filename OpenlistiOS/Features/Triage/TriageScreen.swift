//
//  TriageScreen.swift
//  OpenlistiOS
//

import SwiftUI

/// Triage (mockup 08), a full-screen cover: the Inbox one card at a time,
/// oldest first. Pick a list to move it to, a day for it, or both, then Next
/// files it in one step: a day alone leaves it in the Inbox. Delete sends it
/// to Trash, ✓ marks it done, Later sets it aside for now. Each is one step
/// with Undo in the tray.
struct TriageScreen: View {
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.olStyle) private var style
    @State private var picksDate = false
    /// The list and day picked on the card on show, for Next.
    @State private var draft = TriageDraft()
    /// The card on show, so a date picked for one never lands on the next.
    @State private var shownCard: UUID?

    var body: some View {
        let navigator = env.navigator
        let session = env.triage
        let queue = library.inboxQueue(triage: session, closing: env.actions.closing)
        let reviewed = session.reviewed(queue: queue)
        let total = reviewed + queue.count
        let card = queue.first
        // A card with many lists, or at large text sizes, scrolls; the
        // finished state fills the screen.
        OLScreen(identifier: PhoneRoute.triage.screenIdentifier, scrolls: card != nil) {
            OLTopBar {
                OLIconButton("xmark", label: "Close triage", kind: .bare, iconSize: 22) { navigator.dismissCover() }
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
            OLProgressBar(value: total == 0 ? 1 : Double(reviewed) / Double(total), tint: OL.info,
                          turnsGreenWhenFull: false)
                .padding(.top, 6)
            if let card {
                TriageCard(task: card, now: env.now, draft: $draft, picksDate: $picksDate)
                    .id(card.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    .padding(.top, 24)
                Spacer(minLength: 0)
            } else {
                OLEmptyState(symbol: "checkmark", tint: OL.successText, fill: OL.successSoft, title: "Inbox triaged",
                             message: reviewed == 0 ? "Nothing is waiting in the Inbox."
                                : "\(reviewed) reviewed this session.",
                             actionTitle: "Back to Inbox") { navigator.dismissCover() }
                    .frame(maxHeight: .infinity)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let card { buttons(card) }
        }
        .animation(style.fading(.snappy(duration: 0.3)), value: card?.id)
        .animation(style.fading(.snappy(duration: 0.2)), value: draft)
        .onChange(of: card?.id, initial: true) { _, id in
            draft = TriageDraft()
            shownCard = id
        }
        .sheet(isPresented: $picksDate) {
            if let card {
                let id = card.id
                DuePickerSheet(date: pickerDate(for: card), includesTime: draft.timed ?? card.includesTime,
                               now: env.now, clears: false) { date, timed in
                    guard shownCard == id else { return }
                    draft.due = date
                    draft.timed = date == nil ? nil : timed
                }
            }
        }
        .onAppear { session.begin() }
    }

    private func buttons(_ task: Block) -> some View {
        OLActionDock {
            OLIconButton("trash", label: "Delete", kind: .bad, size: .large) {
                if env.actions.trash([task]) { env.triage.finish(task.id) }
            }
            .accessibilityIdentifier("triage.delete")
            OLIconButton("checkmark", label: "Already done", kind: .ok, size: .large) {
                let due = task.recurrence != nil ? task.dueDate : nil
                let repeats = task.recurrence != nil
                env.actions.complete([task])
                // A repeat rolls to its next date and stays in the Inbox: set
                // it aside once it has, as the Mac's triage does, so the next
                // card comes, and Undo brings it back.
                if let due { env.triage.rollOn(task.id, from: due) }
                else if repeats { env.triage.keep(task.id) }
                else { env.triage.finish(task.id) }
            }
            .accessibilityIdentifier("triage.done")
            Spacer(minLength: 0)
            if draft.isEmpty {
                Button("Later") { env.triage.keep(task.id) }
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
