//
//  CaptureScreen.swift
//  OpenlistiOS
//

import SwiftUI
import UIKit

/// The Capture sheet (mockup 06): a field that tints the date, time, repeat,
/// estimate, priority and labels as they're typed, chips for what Add saves,
/// and the list it goes to. Add saves it at once, with Undo in the tray.
/// The mic listens for tasks said instead: one lands in the field to edit,
/// several wait as rows, each with the list, day and labels said with it.
struct CaptureScreen: View {
    let request: CaptureRequest
    @Environment(PhoneEnvironment.self) private var env
    @Environment(\.phoneLibrary) private var library
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.olStyle) private var style
    @State private var text = ""
    @State private var listID: UUID?
    @State private var dueDate = CaptureDueDate.automatic
    @State private var showsDuePicker = false
    @State private var resumesTyping = false
    @State private var height: CGFloat = 236
    @State private var voice = VoiceCapture()
    /// Tasks heard, when there were several, which Add saves together.
    @State private var spoken: [SpokenTask] = []
    /// Why the last Add failed, shown in the sheet: the window's tray is
    /// under it, out of sight.
    @State private var saveError: String?
    @FocusState private var isFocused: Bool

    init(request: CaptureRequest) {
        self.request = request
        _listID = State(initialValue: request.listID)
        #if DEBUG
        // A review session's `OpenlistCaptureText`, typed in for a screenshot.
        if ReviewSession.identifier != nil, let typed = ProcessInfo.processInfo.environment["OpenlistCaptureText"] {
            _text = State(initialValue: typed)
        }
        #endif
    }

    var body: some View {
        let parse = CaptureParse(text, parsesDates: env.settings.parsesNaturalLanguageDates, reference: env.now)
        let snapshot = snapshot(parse)
        VStack(alignment: .leading, spacing: 0) {
            OLSheetHeader(confirmTitle: spoken.count > 1 ? "Add \(spoken.count)" : "Add",
                          canConfirm: !voice.isActive && (!spoken.isEmpty || !parse.title.isEmpty),
                          cancel: { env.navigator.dismissSheet() },
                          confirm: { spoken.isEmpty ? add(snapshot) : addSpoken() })
            if voice.isActive {
                CaptureVoicePanel(voice: voice, stop: toggleVoice)
                    .padding(.top, 10)
            } else if !spoken.isEmpty {
                heard
                    .padding(.top, 10)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    field(parse)
                    OLIconButton("mic", label: "Say tasks", action: toggleVoice)
                        .accessibilityHint("Listens for one or more tasks, with their dates, lists and labels.")
                        .accessibilityIdentifier("capture.voice")
                }
                .padding(.top, 10)
                let chips = chips(parse, snapshot: snapshot)
                let details = [dateLabel(snapshot)].compactMap { $0 } + chips.map(\.label)
                OLFlowLayout {
                    dueDateControl(snapshot)
                    ForEach(chips, id: \.label) { chip in chip }
                }
                .padding(.top, 10)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(details.isEmpty ? "Task details" : "Saves as \(details.joined(separator: ", "))")
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
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        .presentationDetents([.height(height)])
        // A swipe down, often meant only to lower the keyboard, would throw
        // away what's typed or heard; Cancel still does, deliberately.
        .interactiveDismissDisabled(hasDraft)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New task")
        .accessibilityIdentifier(PhoneRoute.capture(request).screenIdentifier)
        .onAppear {
            if request.listens { toggleVoice() } else { isFocused = true }
        }
        .onDisappear { voice.cancel() }
        // Leaving the app ends listening with what was said so far.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, voice.phase == .listening { voice.stop() }
        }
        .onChange(of: text) {
            voice.dismissFailure()
            saveError = nil
        }
        .sheet(isPresented: $showsDuePicker, onDismiss: { isFocused = resumesTyping }) {
            DuePickerSheet(date: snapshot.date, includesTime: snapshot.includesTime, now: env.now) { date, timed in
                setDueDate(date, includesTime: timed)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("capture.duePicker")
        }
        .animation(style.animation(.snappy(duration: 0.25)), value: voice.isActive)
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
            break
        case .idle, .failed:
            isFocused = false
            spoken = []
            voice.onHeard = { heard in take(heard) }
            voice.start(vocabulary: SpokenCapture.Vocabulary(lists: library.lists, labels: library.labels), now: { env.now })
            env.haptics.play(.impact)
        }
    }

    /// One task heard goes in the field as its capture line, aimed at the list
    /// it named, to edit as though typed; several, or one the field wouldn't
    /// read back the same, wait as rows.
    private func take(_ heard: [SpokenTask]) {
        env.haptics.play(.selection)
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
        let result = env.store.saveSpokenTasks(spoken, destinationID: destination?.id,
                                               undatedDay: request.dueToday ? env.now : nil)
        if !result.saved.isEmpty { env.actions.reportCapture(result.saved) }
        guard let error = result.error else { return env.navigator.dismissSheet() }
        spoken = result.unsaved
        failed("“\(result.unsaved[0].snapshot.title)” wasn’t added. \(error.localizedDescription)")
    }

    private var hasDraft: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !spoken.isEmpty
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
                let next = CaptureParse(typed, parsesDates: env.settings.parsesNaturalLanguageDates, reference: env.now)
                dueDate = dueDate.afterEditing(from: parse, to: next)
                text = typed
            }), prompt: Text("New task").foregroundStyle(OL.muted), axis: .vertical)
                .font(OLFont.captureInput)
                .foregroundStyle(text.isEmpty ? OL.ink : .clear)
                .tint(OL.accent)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { add(snapshot(parse)) }
                // A field that wraps takes Return as a new line; here it adds.
                .onChange(of: text) { _, typed in
                    guard typed.contains("\n") else { return }
                    text = typed.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                    add(snapshot(CaptureParse(text, parsesDates: env.settings.parsesNaturalLanguageDates, reference: env.now)))
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
        case .date, .time, .repeatRule: OL.accentText
        case .estimate: OL.muted
        case .label: OL.teal
        case .priority: OL.danger
        }
    }

    // MARK: What Add saves

    /// Add and Return save the same date the calendar chip previews.
    private func snapshot(_ parse: CaptureParse) -> CaptureSnapshot {
        dueDate.snapshot(parse, dueToday: request.dueToday, now: env.now, calendar: env.settings.calendar)
    }

    private func dateLabel(_ snapshot: CaptureSnapshot) -> String? {
        snapshot.date.map {
            CompactText.captureWhen($0, includesTime: snapshot.includesTime, now: env.now, calendar: env.settings.calendar)
        }
    }

    /// The date stays a single editable chip, with quick days and the same
    /// calendar/time picker as Task detail. Its touch target is 44 points.
    private func dueDateControl(_ snapshot: CaptureSnapshot) -> some View {
        Menu {
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

    /// The other saved metadata, in typed order, alongside the calendar chip.
    private func chips(_ parse: CaptureParse, snapshot: CaptureSnapshot) -> [OLChip] {
        var chips: [OLChip] = []
        for mark in parse.marks {
            switch mark.kind {
            case .date, .time: break
            case .repeatRule:
                if let rule = snapshot.recurrence { chips.append(OLChip(rule.displayText, symbol: "repeat", small: true, tint: OL.accentText)) }
            case .estimate:
                if snapshot.estimateMinutes > 0, !chips.contains(where: { $0.label.hasSuffix(" min") }) {
                    chips.append(OLChip(CompactText.estimate(snapshot.estimateMinutes), small: true))
                }
            case .priority:
                if snapshot.priority != .none, !chips.contains(where: { $0.label == snapshot.priority.title }) {
                    chips.append(OLChip(snapshot.priority.title, symbol: "exclamationmark", small: true, tint: OL.danger))
                }
            case .label:
                let name = "#" + String(mark.raw.dropFirst()).lowercased()
                if !chips.contains(where: { $0.label == name }) { chips.append(OLChip(name, small: true, tint: OL.teal)) }
            }
        }
        return chips
    }

    // MARK: Destinations

    private var destinations: some View {
        let chosen = destination?.id
        return OLChipScroller {
            ForEach(library.lists) { list in
                OLChipButton(OLChip(list.displayTitle, glyph: list.isSystemInbox ? "📥" : list.icon,
                                    style: list.id == chosen ? .on : .plain)) {
                    listID = list.id
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

    private func add(_ snapshot: CaptureSnapshot) {
        guard !snapshot.title.isEmpty else { return }
        do {
            let block = try env.store.saveCapture(snapshot, destinationID: destination?.id)
            env.actions.reportCapture(block)
            env.navigator.dismissSheet()
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
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OL.accent)
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
                Button(voice.phase == .listening ? "Done" : "Stop", action: stop)
                    .buttonStyle(.ol(.primary, size: .small))
                    .disabled(voice.phase == .understanding)
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
