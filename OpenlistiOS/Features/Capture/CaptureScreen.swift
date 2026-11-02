//
//  CaptureScreen.swift
//  OpenlistiOS
//

import SwiftUI
import UIKit

/// The Capture sheet (mockup 06): a field that tints the date, time, repeat,
/// estimate, priority, labels and `@list` as they're typed, suggesting the
/// list or label being typed, chips for what Add saves, a note, and the list
/// it goes to. Add saves it at once and closes, with Undo in the tray; Return
/// saves it and clears the field for the next, aimed at the same list. A
/// chip's menu keeps its words as text. The mic listens for tasks said
/// instead, and lines pasted at once are a task each: one lands in the field
/// to edit, several wait as rows, each with the list, day and labels said or
/// typed with it. What's typed outlives the sheet: something else taking the
/// screen keeps it for the next Capture (`PhoneNavigator.captureDraft`), and
/// Cancel asks before throwing it away.
struct CaptureScreen: View {
    let request: CaptureRequest
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.olStyle) private var style
    @State private var text = ""
    @State private var listID: UUID?
    @State private var dueDate = CaptureDueDate.automatic
    /// The date picker, shown in the sheet in place of the field.
    @State private var showsDuePicker = false
    @State private var resumesTyping = false
    @State private var confirmsDiscard = false
    /// Added or discarded: nothing is left to keep for later.
    @State private var isFinished = false
    @State private var height: CGFloat = 236
    @State private var voice = VoiceCapture()
    @State private var hasAppeared = false
    /// Tasks heard, when there were several, which Add saves together.
    @State private var spoken: [SpokenTask] = []
    /// Why the last Add failed, shown in the sheet: the window's tray is
    /// under it, out of sight.
    @State private var saveError: String?
    /// The note under the task, which Add saves with it, and whether its
    /// line is open.
    @State private var note = ""
    @State private var writesNote = false
    /// Tokens kept as text: plain words wherever they're typed.
    @State private var literals: Set<String> = []
    /// What Return just added, said in the sheet with its Undo, as the
    /// sheet stays for the next task.
    @State private var added: String?
    /// Lines last taken as rows, and when: the field sends a paste again
    /// while it catches up with the text it kept, and it's taken once.
    @State private var takenPaste: (text: String, at: Date)?
    @FocusState private var isFocused: Bool
    @FocusState private var noteFocused: Bool

    init(request: CaptureRequest, draft: CaptureDraft? = nil, spoken: [SpokenTask] = []) {
        self.request = request
        _listID = State(initialValue: draft.map(\.listID) ?? request.listID)
        _text = State(initialValue: draft?.text ?? "")
        _dueDate = State(initialValue: draft?.dueDate ?? .automatic)
        _note = State(initialValue: draft?.note ?? "")
        _writesNote = State(initialValue: !(draft?.note ?? "").isEmpty)
        _spoken = State(initialValue: spoken)
        #if DEBUG
        // A review session's `OpenlistCaptureText`, typed in for a screenshot.
        if ReviewSession.identifier != nil, let typed = ProcessInfo.processInfo.environment["OpenlistCaptureText"] {
            _text = State(initialValue: typed)
        }
        #endif
    }

    var body: some View {
        let parse = parse(text)
        let snapshot = snapshot(parse)
        Group {
            if showsDuePicker {
                DuePickerForm(date: snapshot.date, includesTime: snapshot.includesTime, now: env.now,
                              close: closeDuePicker) { date, timed in
                    setDueDate(date, includesTime: timed)
                }
                .padding(.bottom, 20)
                .transition(.opacity)
            } else {
                capture(parse, snapshot: snapshot)
                    .transition(.opacity)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        .presentationDetents([.height(height)])
        // A swipe down, often meant only to lower the keyboard, would throw
        // away what's typed or heard; Cancel asks first.
        .interactiveDismissDisabled(hasDraft || voice.isActive || showsDuePicker)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New task")
        .accessibilityIdentifier(PhoneRoute.capture(request).screenIdentifier)
        .accessibilityAction(.escape) { showsDuePicker ? closeDuePicker() : cancel() }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            if request.listens || env.navigator.captureListenRequestID == request.id {
                env.navigator.captureListenRequestID = nil
                startVoice()
            } else {
                isFocused = true
            }
        }
        .onChange(of: env.navigator.captureListenRequestID) {
            guard env.navigator.captureListenRequestID == request.id else { return }
            env.navigator.captureListenRequestID = nil
            startVoice()
        }
        .onChange(of: draft, initial: true) { _, draft in env.navigator.captureDraft = draft }
        .onChange(of: spoken.map(\.id)) { env.navigator.capturedSpoken = spoken }
        .onDisappear {
            voice.cancel()
            keptDraft()
        }
        // Leaving the app ends listening with what was said so far.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { voice.sceneDepartedActive(isBackground: phase == .background) }
        }
        .onChange(of: voice.phase) { _, phase in
            if phase == .listening { env.haptics.play(.selection) }
        }
        .onChange(of: text) { voice.dismissFailure() }
        .confirmationDialog(spoken.count > 1 ? "Discard these \(spoken.count) tasks?" : "Discard this task?",
                            isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive, action: discard)
            Button("Keep for Later", action: close)
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Keep it for later, and it’s back the next time you add a task.")
        }
        .animation(style.animation(.snappy(duration: 0.25)), value: voice.isActive)
        .animation(style.fading(.snappy(duration: 0.25)), value: showsDuePicker)
    }

    /// The field, its chips and the lists, or what voice heard.
    private func capture(_ parse: CaptureParse, snapshot: CaptureSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // With nothing typed after Return added some, Done closes.
            let done = spoken.isEmpty && parse.title.isEmpty && added != nil && !hasDraft
            OLSheetHeader(confirmTitle: done ? "Done" : spoken.count > 1 ? "Add \(spoken.count)" : "Add",
                          canConfirm: !voice.isActive && (done || !spoken.isEmpty || !parse.title.isEmpty),
                          cancel: cancel,
                          confirm: { done ? finish() : spoken.isEmpty ? add(parse) : addSpoken() })
            if voice.isActive {
                CaptureVoicePanel(voice: voice, stop: toggleVoice)
                    .padding(.top, 10)
            } else if !spoken.isEmpty {
                heard
                    .padding(.top, 10)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    field(parse)
                    OLIconButton("text.alignleft", label: writesNote ? "Note" : "Add a note", kind: .bare, iconSize: 18) {
                        writesNote = true
                        noteFocused = true
                    }
                    .accessibilityIdentifier("capture.addNote")
                    OLIconButton("mic", label: "Say tasks", action: toggleVoice)
                        .accessibilityHint("Listens for one or more tasks, with their dates, lists and labels.")
                        .accessibilityIdentifier("capture.voice")
                }
                .padding(.top, 10)
                if let completion = completion {
                    suggestions(completion)
                        .padding(.top, 8)
                }
                if writesNote {
                    TextField("Note", text: $note, prompt: Text("Note").foregroundStyle(OL.muted), axis: .vertical)
                        .font(OLFont.meta)
                        .foregroundStyle(OL.ink)
                        .lineLimit(1...4)
                        .focused($noteFocused)
                        .padding(.top, 8)
                        .accessibilityIdentifier("capture.note")
                }
                let chips = chips(parse, snapshot: snapshot)
                let details = [dateLabel(snapshot)].compactMap { $0 } + chips.map(\.chip.label)
                OLFlowLayout {
                    dueDateControl(snapshot, parse: parse)
                    ForEach(chips, id: \.chip.label) { chip in
                        if let raw = chip.raw {
                            // A token read wrongly goes back to being words.
                            Menu {
                                Button("Keep “\(raw)” as text", systemImage: "textformat") { keepAsText(raw) }
                            } label: {
                                chip.chip.frame(minHeight: 44).contentShape(.rect)
                            }
                            .buttonStyle(OLPressStyle(scale: 0.96))
                            .accessibilityHint("Keeps “\(raw)” as text in the title")
                        } else {
                            chip.chip
                        }
                    }
                }
                .padding(.top, 10)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(details.isEmpty ? "Task details" : "Saves as \(details.joined(separator: ", "))")
                if let added {
                    HStack(spacing: 8) {
                        Label(added, systemImage: "checkmark.circle.fill")
                            .font(OLFont.meta)
                            .foregroundStyle(OL.successText)
                            .lineLimit(1)
                            .accessibilityIdentifier("capture.added")
                        Spacer(minLength: 4)
                        Button("Undo") {
                            env.actions.undoLatest()
                            self.added = nil
                        }
                        .buttonStyle(.olLink(small: true))
                        .accessibilityLabel("Undo, take back what was added")
                        .accessibilityIdentifier("capture.undoAdded")
                    }
                    .padding(.top, 10)
                }
            }
            if case let .failed(failure) = voice.phase {
                CaptureVoiceFailure(failure: failure)
                    .padding(.top, 12)
            }
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.circle")
                    .font(OLFont.meta)
                    .foregroundStyle(OL.danger)
                    .padding(.top, 12)
                    .accessibilityIdentifier("capture.saveError")
            }
            destinations
                .padding(.top, 16)
        }
        .padding(.horizontal, OLMetrics.gutter)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func closeDuePicker() {
        showsDuePicker = false
        isFocused = resumesTyping
    }

    // MARK: Voice

    /// The mic: starts listening, or stops and reads what was said.
    private func toggleVoice() {
        switch voice.phase {
        case .listening:
            voice.stop()
        case .preparing:
            voice.cancel()
        case .understanding:
            voice.skipReading()
        case .idle, .failed:
            startVoice()
        }
    }

    private func startVoice() {
        guard !voice.isActive else { return }
        isFocused = false
        saveError = nil
        voice.onHeard = { heard in take(heard) }
        voice.start(vocabulary: SpokenCapture.Vocabulary(lists: library.lists, labels: library.labels),
                    afterCapture: env.settings.afterVoiceCapture, hasDraft: hasDraft, now: { env.now })
        env.haptics.play(.impact)
    }

    /// One task heard goes in the field as its capture line, aimed at the list
    /// it named, to edit as though typed; several, or one the field wouldn't
    /// read back the same, wait as rows.
    private func take(_ heard: [SpokenTask]) {
        guard !heard.isEmpty else { return }
        saveError = nil
        env.haptics.play(.selection)
        if hasDraft {
            spoken += heard
            return
        }
        if voice.completionMode == .saveAutomatically {
            spoken = heard
            addSpoken()
            return
        }
        dueDate = .automatic
        if heard.count == 1, let task = heard.first,
           task.fitsField(parsesDates: env.settings.parsesNaturalLanguageDates, reference: env.now) {
            text = task.line
            if let id = task.listID { listID = id }
            isFocused = true
        } else {
            text = ""
            spoken = heard
        }
    }

    /// The tasks heard, each with what it saves and its list when that isn't
    /// the one picked below, and a way to leave one out.
    private var heard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !text.isEmpty {
                Text("Your typed draft is kept. Add these tasks, then continue typing.")
                    .font(OLFont.meta)
                    .foregroundStyle(OL.muted)
            }
            ForEach(spoken) { task in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.snapshot.title)
                            .font(OLFont.captureInput)
                            .foregroundStyle(OL.ink)
                        let chips = spokenChips(task)
                        if !chips.isEmpty {
                            OLFlowLayout {
                                ForEach(chips, id: \.label) { chip in chip }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    OLIconButton("xmark", label: "Leave out “\(task.snapshot.title)”", kind: .bare, iconSize: 15) {
                        spoken.removeAll { $0.id == task.id }
                        saveError = nil
                    }
                }
            }
            if voice.usedIntelligence {
                Label("Read by Apple Intelligence", systemImage: "apple.intelligence")
                    .font(OLFont.meta)
                    .foregroundStyle(OL.muted)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tasks heard")
        .accessibilityIdentifier("capture.heard")
    }

    private func spokenChips(_ task: SpokenTask) -> [OLChip] {
        var chips: [OLChip] = []
        if let list = task.listID.flatMap({ id in library.lists.first { $0.id == id } }), list.id != destination?.id {
            chips.append(OLChip(list.displayTitle, glyph: list.isSystemInbox ? "📥" : list.icon, small: true))
        }
        let snapshot = task.snapshot
        if let date = snapshot.date {
            chips.append(OLChip(CompactText.captureWhen(date, includesTime: snapshot.includesTime, now: env.now,
                                                        calendar: env.settings.calendar),
                                small: true, tint: OL.accentText))
        }
        if let rule = snapshot.recurrence { chips.append(OLChip(rule.displayText, symbol: "repeat", small: true, tint: OL.accentText)) }
        if snapshot.estimateMinutes > 0 { chips.append(OLChip(CompactText.estimate(snapshot.estimateMinutes), small: true)) }
        if snapshot.priority != .none {
            chips.append(OLChip(snapshot.priority.title, symbol: "exclamationmark", small: true, tint: OL.danger))
        }
        chips += snapshot.labels.map { OLChip("#" + $0, small: true, tint: OL.teal) }
        return chips
    }

    /// Adds the tasks heard, each to the list it named or the one picked, due
    /// today when an undated one would be; any it couldn't add stay.
    private func addSpoken() {
        guard !spoken.isEmpty else { return }
        let result = env.store.saveSpokenTasks(spoken, destinationID: destination?.id,
                                               undatedDay: request.dueToday ? env.now : nil)
        spoken = result.unsaved
        if !result.saved.isEmpty { env.actions.reportCapture(result.saved) }
        guard let error = result.error else {
            if text.isEmpty { finish() } else { isFocused = true }
            return
        }
        failed("“\(result.unsaved[0].snapshot.title)” wasn’t added. \(error.localizedDescription)")
    }

    private var hasDraft: Bool {
        !text.isEmpty || !spoken.isEmpty || !note.isEmpty
    }

    /// What's typed, as the navigator keeps it while Capture is away.
    private var draft: CaptureDraft? {
        text.isEmpty && note.isEmpty ? nil
            : CaptureDraft(text: text, listID: listID, dueDate: dueDate, note: note.isEmpty ? nil : note)
    }

    /// Cancel: closes at once with nothing to lose, else asks first.
    private func cancel() {
        if hasDraft { confirmsDiscard = true } else { discard() }
    }

    /// Throws away what's typed or heard, and closes.
    private func discard() {
        voice.cancel()
        finish()
    }

    /// Closes with nothing kept: all added, or discarded.
    private func finish() {
        isFinished = true
        env.navigator.captureDraft = nil
        env.navigator.capturedSpoken = []
        env.navigator.dismissSheet()
    }

    /// Closes, keeping whatever is typed or heard for the next Capture.
    private func close() {
        voice.cancel()
        env.navigator.dismissSheet()
    }

    /// Closed with a draft by anything but Add or Discard: says it's kept,
    /// with the way back to it.
    private func keptDraft() {
        guard hasDraft, !isFinished else { return }
        let navigator = env.navigator
        let listID = listID
        env.tray.show("Kept what you were writing", icon: "square.and.pencil", tone: .neutral, seconds: 6,
                      actionTitle: "Open") {
            navigator.open(.capture(CaptureRequest(listID: listID)))
        }
    }

    private func failed(_ message: String) {
        saveError = message
        AccessibilityNotification.Announcement(message).post()
        env.haptics.play(.error)
    }

    // MARK: Field

    /// The typed text drawn tinted under a clear field that takes the typing,
    /// as the Mac's capture card does, so the tokens show where they are.
    private func field(_ parse: CaptureParse) -> some View {
        ZStack(alignment: .topLeading) {
            tinted(parse)
                .accessibilityHidden(true)
            TextField("New task", text: Binding(get: { text }, set: { typed in
                var typed = typed
                // Lines pasted at once are a task each, waiting as rows, and the
                // field stays as it was; one line pasted with its break is words.
                if let paste = Self.insertion(from: text, to: typed), paste.text.count > 1,
                   paste.text.contains(where: \.isNewline) {
                    if let lines = CaptureLines.tasks(in: paste.text) {
                        if let taken = takenPaste, taken.text == typed, Date.now.timeIntervalSince(taken.at) < 1 { return }
                        takenPaste = (typed, .now)
                        takePasted(lines)
                        return
                    }
                    let words = paste.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                    typed = paste.before + words.filter { !$0.isEmpty }.joined(separator: " ") + paste.after
                }
                let next = self.parse(typed)
                dueDate = dueDate.afterEditing(from: parse, to: next)
                // Typing clears a failed Add's reason; the field's own tidying
                // of Return, which runs the Add, doesn't.
                saveError = nil
                text = typed
            }), prompt: Text("New task").foregroundStyle(OL.muted), axis: .vertical)
                .font(OLFont.captureInput)
                .foregroundStyle(text.isEmpty ? OL.ink : .clear)
                .tint(OL.accent)
                .focused($isFocused)
                .submitLabel(.next)
                .onSubmit { add(parse, keepsOpen: true) }
                // A field that wraps takes Return as a new line; here it adds,
                // and clears the field for the next task.
                .onChange(of: text) { _, typed in
                    guard typed.contains("\n") else { return }
                    text = typed.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                    add(self.parse(text), keepsOpen: true)
                }
                .accessibilityIdentifier("capture.field")
        }
    }

    private func tinted(_ parse: CaptureParse) -> Text {
        var text = AttributedString()
        for segment in parse.segments {
            var run = AttributedString(segment.text)
            if let kind = segment.kind {
                if dueDate != .automatic, kind == .date || kind == .time {
                    // Keep the editable words and cursor in place; the chip
                    // now sets the date instead of these superseded tokens.
                    run.foregroundColor = OL.muted
                    run.strikethroughStyle = Text.LineStyle(pattern: .solid, color: OL.muted)
                } else {
                    let tone = Self.tone(kind)
                    run.foregroundColor = tone
                    run.underlineStyle = Text.LineStyle(pattern: .solid, color: tone)
                }
            } else {
                run.foregroundColor = OL.ink
            }
            text += run
        }
        return Text(text).font(OLFont.captureInput)
    }

    static func tone(_ kind: CaptureParse.Kind) -> Color {
        switch kind {
        case .date, .time, .repeatRule, .list: OL.accentText
        case .estimate: OL.muted
        case .label: OL.teal
        case .priority: OL.danger
        }
    }

    // MARK: What Add saves

    /// Add and Return save the same date the calendar chip previews, and the note.
    private func snapshot(_ parse: CaptureParse) -> CaptureSnapshot {
        var snapshot = dueDate.snapshot(parse, dueToday: request.dueToday, now: env.now, calendar: env.settings.calendar)
        snapshot.note = note
        return snapshot
    }

    /// The text read as the field tints it and Add saves it: its dates while
    /// Settings reads them, an `@` naming a list, and the words kept as text.
    private func parse(_ text: String) -> CaptureParse {
        CaptureParse(text, parsesDates: env.settings.parsesNaturalLanguageDates, reference: env.now,
                     lists: library.lists.map { ($0.id, $0.displayTitle) }, literals: literals)
    }

    /// "Keep as text" in a token's menu.
    private func keepAsText(_ raw: String) {
        literals.insert(CaptureParse.literal(raw))
        env.haptics.play(.selection)
    }

    /// What was inserted between `old` and `new`, with the text before and
    /// after it: the change between their common start and end, or nil when
    /// text only went.
    static func insertion(from old: String, to new: String) -> (before: String, text: String, after: String)? {
        guard new.count > old.count else { return nil }
        let start = zip(old, new).prefix { $0 == $1 }.count
        let end = zip(old.reversed(), new.reversed()).prefix { $0 == $1 }.count
        let tail = min(end, old.count - start)
        let inserted = new.dropFirst(start).dropLast(tail)
        guard !inserted.isEmpty else { return nil }
        return (String(new.prefix(start)), String(inserted), String(new.suffix(tail)))
    }

    /// Lines pasted as rows, each read for its own tokens, `@` list included.
    private func takePasted(_ lines: [String]) {
        let lists = library.lists.map { ($0.id, $0.displayTitle) }
        spoken += lines.map { line in
            let parse = CaptureParse(line, parsesDates: env.settings.parsesNaturalLanguageDates, reference: env.now, lists: lists)
            return SpokenTask(snapshot: parse.snapshot(), listID: parse.listID)
        }.filter { !$0.snapshot.title.isEmpty }
        saveError = nil
        env.haptics.play(.selection)
    }

    // MARK: Suggestions

    /// The `@list` or `#label` being typed, with what it could be.
    private var completion: CaptureCompletion? {
        CaptureCompletion.typing(text, lists: library.lists.map { ($0.id, $0.displayTitle) },
                                 labels: library.labels.map(\.name))
    }

    /// The lists or labels the token could be, under the field: a tap
    /// spells it out, ready for the next word.
    private func suggestions(_ completion: CaptureCompletion) -> some View {
        OLChipScroller {
            ForEach(completion.options) { option in
                let list = library.list(option.listID)
                OLChipButton(OLChip(option.name, glyph: list.map { $0.isSystemInbox ? "📥" : $0.icon },
                                    small: true, tint: list == nil ? OL.teal : nil)) {
                    text = completion.completing(text, with: option)
                    env.haptics.play(.selection)
                }
                .accessibilityLabel((completion.kind == .list ? "List " : "Label ") + option.name)
                .accessibilityHint("Completes what you're typing")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions")
        .accessibilityIdentifier("capture.suggestions")
    }

    private func dateLabel(_ snapshot: CaptureSnapshot) -> String? {
        snapshot.date.map {
            CompactText.captureWhen($0, includesTime: snapshot.includesTime, now: env.now, calendar: env.settings.calendar)
        }
    }

    /// The date stays a single editable chip, with quick days and the same
    /// calendar/time picker as Task detail. Its touch target is 44 points.
    private func dueDateControl(_ snapshot: CaptureSnapshot, parse: CaptureParse) -> some View {
        // The words a typed date was read from, which can go back to being words.
        let typed = dueDate == .automatic ? parse.marks.filter { [.date, .time, .repeatRule].contains($0.kind) } : []
        return Menu {
            Section {
                ForEach(PhoneDay.allCases) { day in
                    Button(day.title) {
                        let calendar = env.settings.calendar
                        var date = day.date(now: env.now, calendar: calendar)
                        if snapshot.includesTime, let previous = snapshot.date {
                            let time = calendar.dateComponents([.hour, .minute], from: previous)
                            date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: date) ?? date
                        }
                        setDueDate(date, includesTime: snapshot.includesTime)
                    }
                }
            }
            Button("Choose date & time…", systemImage: "calendar") {
                resumesTyping = isFocused
                isFocused = false
                showsDuePicker = true
            }
            if snapshot.date != nil {
                Button("Clear date", systemImage: "xmark") { setDueDate(nil, includesTime: false) }
            }
            if !typed.isEmpty {
                Section {
                    ForEach(typed, id: \.raw) { mark in
                        Button("Keep “\(mark.raw)” as text", systemImage: "textformat") { keepAsText(mark.raw) }
                    }
                }
            }
        } label: {
            OLChip(dateLabel(snapshot) ?? "Due date", icon: .calendar, small: true,
                   tint: snapshot.date == nil ? OL.muted : OL.accentText)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(OLPressStyle(scale: 0.96))
        .accessibilityLabel("Due date")
        .accessibilityValue(dateLabel(snapshot) ?? "None")
        .accessibilityHint("Choose a quick day, a date and time, or clear the date.")
        .accessibilityIdentifier("capture.dueDate")
    }

    private func setDueDate(_ date: Date?, includesTime: Bool) {
        dueDate = date.map { .chosen($0, includesTime: includesTime) } ?? .cleared
        env.haptics.play(.selection)
    }

    /// The other saved metadata, in typed order, alongside the calendar chip,
    /// each with the words typed for it, which its menu keeps as text. A
    /// label nobody has yet says Add makes it.
    private func chips(_ parse: CaptureParse, snapshot: CaptureSnapshot) -> [(chip: OLChip, raw: String?)] {
        var chips: [(chip: OLChip, raw: String?)] = []
        func has(_ label: String) -> Bool { chips.contains { $0.chip.label == label } }
        for mark in parse.marks {
            switch mark.kind {
            case .date, .time: break
            case .repeatRule:
                if let rule = snapshot.recurrence {
                    chips.append((OLChip(rule.displayText, symbol: "repeat", small: true, tint: OL.accentText), mark.raw))
                }
            case .estimate:
                if snapshot.estimateMinutes > 0, !chips.contains(where: { $0.chip.label.hasSuffix(" min") }) {
                    chips.append((OLChip(CompactText.estimate(snapshot.estimateMinutes), small: true), mark.raw))
                }
            case .priority:
                if snapshot.priority != .none, !has(snapshot.priority.title) {
                    chips.append((OLChip(snapshot.priority.title, symbol: "exclamationmark", small: true, tint: OL.danger), mark.raw))
                }
            case .label:
                let name = String(mark.raw.dropFirst())
                let known = library.labels.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                let label = known ? "#" + name.lowercased() : "New #" + name.lowercased()
                if !has(label) {
                    chips.append((OLChip(label, symbol: known ? nil : "plus", small: true, tint: known ? OL.teal : OL.muted),
                                  mark.raw))
                }
            case .list:
                if let list = library.list(parse.listID) {
                    chips.append((OLChip(list.displayTitle, glyph: list.isSystemInbox ? "📥" : list.icon, small: true), mark.raw))
                }
            }
        }
        return chips
    }

    // MARK: Destinations

    private var destinations: some View {
        let chosen = spoken.isEmpty ? destination(parse(text))?.id : destination?.id
        return OLChipScroller {
            ForEach(library.lists) { list in
                OLChipButton(OLChip(list.displayTitle, glyph: list.isSystemInbox ? "📥" : list.icon,
                                    style: list.id == chosen ? .on : .plain)) {
                    choose(list)
                }
                .accessibilityAddTraits(list.id == chosen ? .isSelected : [])
            }
        }
    }

    /// The list Add saves into: the one picked, else the Inbox, which also
    /// takes what's captured on an archived list's page.
    private var destination: TaskList? {
        library.lists.first { $0.id == listID } ?? library.inbox
    }

    /// Where the typed task goes: the list its `@` token names, else the picked one.
    private func destination(_ parse: CaptureParse) -> TaskList? {
        library.list(parse.listID) ?? destination
    }

    /// A list's chip: the task goes there, and an `@` token naming another
    /// gives way, its words leaving the text. While rows wait, the typed
    /// text is out of sight and kept as it is.
    private func choose(_ list: TaskList) {
        if spoken.isEmpty, let token = parse(text).first(.list) {
            var typed = text
            typed.removeSubrange(token.range)
            text = typed.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        listID = list.id
    }

    /// Adds the typed task. Add closes the sheet; Return clears it for the
    /// next task, aimed at the same list, and says what it added there.
    private func add(_ parse: CaptureParse, keepsOpen: Bool = false) {
        let snapshot = snapshot(parse)
        guard !snapshot.title.isEmpty else { return }
        let target = destination(parse)
        do {
            let block = try env.store.saveCapture(snapshot, destinationID: target?.id)
            env.actions.reportCapture(block)
            guard keepsOpen else { return finish() }
            added = "Added “\(block.displayTitle)” to \(target?.displayTitle ?? "Inbox")"
            AccessibilityNotification.Announcement(added ?? "").post()
            listID = target?.id ?? listID
            text = ""
            note = ""
            writesNote = false
            literals = []
            dueDate = .automatic
            env.navigator.captureDraft = nil
            noteFocused = false
            isFocused = true
        } catch {
            failed("Task wasn’t added. \(error.localizedDescription)")
        }
    }
}

/// Voice capture at work in the Capture sheet: the words heard so far, those
/// still being made out paler, a mic that swells with the voice, what it's
/// doing, and Done.
private struct CaptureVoicePanel: View {
    let voice: VoiceCapture
    let stop: () -> Void
    @Environment(\.olStyle) private var style

    var body: some View {
        let listener = voice.listener
        // Under Reduce Motion the mic holds still; the status says it listens.
        let swell = style.reduceMotion ? 0.5 : listener.level
        VStack(alignment: .leading, spacing: 16) {
            words(listener)
                .font(OLFont.captureInput)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                .accessibilityIdentifier("capture.transcript")
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(OL.accentSoft)
                        .frame(width: 30 + 16 * swell, height: 30 + 16 * swell)
                    if voice.phase == .understanding {
                        // Reading can take a while; the mic gives way to
                        // something visibly at work.
                        ProgressView().tint(OL.accent)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(OL.accent)
                    }
                }
                .frame(width: 46, height: 46)
                .animation(style.animation(.linear(duration: 0.08)), value: swell)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    status
                        .font(OLFont.meta)
                        .foregroundStyle(OL.muted)
                    if let note = voice.intelligence.note {
                        Text(note).font(OLFont.meta).foregroundStyle(OL.muted)
                    }
                }
                Spacer(minLength: 0)
                // While Apple Intelligence reads, Skip takes the words as they
                // were said rather than waiting up to 15 seconds.
                Button(voice.phase == .listening ? "Done" : voice.phase == .understanding ? "Skip" : "Stop", action: stop)
                    .buttonStyle(.ol(.primary, size: .small))
                    .accessibilityHint(voice.phase == .understanding ? "Adds what you said without Apple Intelligence." : "")
                    .accessibilityIdentifier("capture.voiceDone")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice capture")
    }

    private func words(_ listener: VoiceListener) -> Text {
        guard !listener.transcript.isEmpty else {
            return Text(voice.phase == .listening ? "Say a task, or several…" : "").foregroundStyle(OL.muted)
        }
        let settled = Text(verbatim: listener.confirmed).foregroundStyle(voice.phase == .understanding ? OL.muted : OL.ink)
        let guess = Text(verbatim: listener.tentative).foregroundStyle(OL.muted)
        return Text("\(settled)\(guess)")
    }

    @ViewBuilder private var status: some View {
        switch voice.phase {
        case .preparing(nil):
            Text("Getting ready…")
        case let .preparing(progress?):
            Text("Downloading speech recognition · \(Int(progress * 100))%")
        case .understanding:
            if voice.intelligence == .available {
                Label("Reading with Apple Intelligence…", systemImage: "apple.intelligence")
            } else {
                Text("Reading…")
            }
        default:
            Text("Listening · pause when you’re done")
        }
    }
}

/// Why voice capture didn't listen, with Settings when it's the microphone.
private struct CaptureVoiceFailure: View {
    let failure: VoiceCaptureFailure

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "mic.slash")
            VStack(alignment: .leading, spacing: 4) {
                Text(failure == .microphoneDenied ? "Openlist can’t use the microphone." : failure.message)
                if failure == .microphoneDenied, let settings = URL(string: UIApplication.openSettingsURLString) {
                    Button("Allow in Settings") { UIApplication.shared.open(settings) }
                        .buttonStyle(.olLink(small: true))
                }
            }
        }
        .font(OLFont.meta)
        .foregroundStyle(failure == .nothingHeard ? OL.muted : OL.danger)
        .accessibilityElement(children: .combine)
    }
}
