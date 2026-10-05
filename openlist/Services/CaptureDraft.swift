//
//  CaptureDraft.swift
//  openlist
//

import Foundation
import Observation

/// What a capture card types into: the text, where it goes, and what Return
/// saves. The main window's draft is the workbench's; the Quick Add panel
/// keeps one of its own, so the two never share half-typed text. UI-free, so
/// the phone's Capture sheet keeps a draft of its own too.
@MainActor
protocol NXCaptureDraft: AnyObject, Observable {
    var store: Store { get }
    var settings: AppSettings { get }
    var captureText: String { get set }
    var captureListID: UUID? { get set }
    /// Whether a task with no date of its own is due today.
    var captureForToday: Bool { get }
    /// The label screen capture opened on; the new task gets that label.
    var captureLabelID: UUID? { get }
    /// Tasks heard by voice capture, which Return adds in place of the text.
    var spokenTasks: [SpokenTask] { get set }
}

extension NXCaptureDraft {
    var hasCaptureDraft: Bool {
        !captureText.isEmpty || !spokenTasks.isEmpty
    }

    /// The capture text read as the card tints it and Return saves it, with
    /// dates only while Settings reads them from typed text.
    func captureParse() -> CaptureParse {
        CaptureParse(captureText, parsesDates: settings.parsesNaturalLanguageDates)
    }

    /// What Return saves, which the capture card's chips preview. A task with
    /// no date of its own is due today when the draft is for today; captured
    /// on a label screen it also gets that label.
    func capturePreview(_ parse: CaptureParse) -> CaptureSnapshot {
        let screenLabel = captureLabelID.flatMap { store.label(id: $0) }.map { [$0.name.lowercased()] } ?? []
        return parse.snapshot(dueToday: captureForToday, labels: screenLabel)
    }

    /// Saves the draft into its list, or Inbox: one capture, saved at once,
    /// for the title, date, repeat, labels, priority and estimate its tokens
    /// name. Returns the task and the folded headings the capture opened to
    /// show it, for an Undo that folds them again.
    func saveCapture(_ parse: CaptureParse) throws -> (block: Block, opened: [UUID]) {
        let destinationID = captureListID ?? store.inboxList()?.id
        let folded = (store.list(id: destinationID) ?? store.inboxList()).map { store.foldedSections(atEndOf: $0.id) } ?? []
        let block = try store.saveCapture(capturePreview(parse), destinationID: destinationID)
        return (block, folded.filter { !$0.isCollapsed }.map(\.id))
    }

    /// What Return and ⇧↩ do with the draft, the window's card and Quick
    /// Add's alike: save it, or say on the card why it wasn't saved. Tokens
    /// with no title save nothing and say nothing, as the design's Return.
    /// Tasks heard by voice are added instead of the text, when there are any.
    func addCapture() -> NXCaptureOutcome {
        if !spokenTasks.isEmpty { return addSpokenTasks() }
        let parse = captureParse()
        guard !parse.title.isEmpty else { return .untitled }
        do {
            let saved = try saveCapture(parse)
            return .saved(saved.block, opened: saved.opened)
        } catch {
            return .failed(NXCaptureNotice(text: "Task wasn’t added. \(error.localizedDescription) Your draft is still here; try again.",
                                           failed: true))
        }
    }

    /// Takes what voice capture heard. A single task goes in the field as
    /// its capture line, aimed at the list it named, to edit as though typed;
    /// several, or one the field wouldn't read back the same, wait as rows
    /// for Return to add together. Returns whether it filled the field.
    @discardableResult
    func take(_ heard: [SpokenTask], now: Date = .now) -> Bool {
        guard !heard.isEmpty else { return false }
        if hasCaptureDraft {
            spokenTasks += heard
            return false
        }
        if heard.count == 1, let task = heard.first,
           task.fitsField(parsesDates: settings.parsesNaturalLanguageDates, reference: now) {
            spokenTasks = []
            captureText = task.line
            if let listID = task.listID { captureListID = listID }
            return true
        }
        spokenTasks = heard
        return false
    }

    func receiveVoice(_ heard: [SpokenTask], afterCapture: AppSettings.AfterVoiceCapture, now: Date = .now) -> NXCaptureOutcome? {
        guard !heard.isEmpty else { return nil }
        if afterCapture == .saveAutomatically, !hasCaptureDraft {
            spokenTasks = heard
            return addSpokenTasks()
        }
        take(heard, now: now)
        return nil
    }

    /// Adds the tasks heard, each to the list it named or the draft's, due
    /// today when an undated task would be, with the label screen's label.
    /// Any it couldn't add stay, with the reason on the card.
    func addSpokenTasks() -> NXCaptureOutcome {
        guard !spokenTasks.isEmpty else { return .untitled }
        let screenLabel = captureLabelID.flatMap { store.label(id: $0) }.map { [$0.name.lowercased()] } ?? []
        let result = store.saveSpokenTasks(spokenTasks, destinationID: captureListID ?? store.inboxList()?.id,
                                           undatedDay: captureForToday ? NXFormat.day(offset: 0) : nil,
                                           labels: screenLabel)
        spokenTasks = result.unsaved
        let failure = result.error.map {
            NXCaptureNotice(text: "“\(result.unsaved[0].snapshot.title)” wasn’t added. \($0.localizedDescription) Try again.",
                            failed: true)
        }
        if result.saved.isEmpty, let failure { return .failed(failure) }
        return .savedSeveral(result.saved, opened: result.opened, failure: failure)
    }

    /// Tab and Shift-Tab step the destination through Inbox and every list.
    /// From a list no longer among them, Tab starts at Inbox and Shift-Tab
    /// at the last list.
    func cycleCaptureDestination(by delta: Int, among ids: [UUID]) {
        guard !ids.isEmpty else { return }
        guard let index = ids.firstIndex(where: { $0 == captureListID }) else {
            captureListID = delta > 0 ? ids.first : ids.last
            return
        }
        captureListID = ids[(index + delta + ids.count) % ids.count]
    }
}

struct VoiceCaptureSession {
    private(set) var generation = 0
    private var pending = false
    private var understanding = false
    private var afterCapture = AppSettings.AfterVoiceCapture.reviewBeforeSaving

    mutating func begin(afterCapture: AppSettings.AfterVoiceCapture, hasDraft: Bool) -> Int {
        generation += 1
        pending = true
        understanding = false
        self.afterCapture = hasDraft ? .reviewBeforeSaving : afterCapture
        return generation
    }

    func isCurrent(run: Int) -> Bool { generation == run && pending }

    mutating func beginUnderstanding(run: Int) -> Bool {
        guard isCurrent(run: run), !understanding else { return false }
        understanding = true
        return true
    }

    mutating func complete(run: Int, hasTasks: Bool) -> AppSettings.AfterVoiceCapture? {
        guard isCurrent(run: run), understanding else { return nil }
        pending = false
        return hasTasks ? afterCapture : nil
    }

    mutating func cancel() {
        generation += 1
        pending = false
        understanding = false
    }

    mutating func requireReview() {
        afterCapture = .reviewBeforeSaving
    }
}

/// A line the card shows where there is no tray to say it: what ⇧↩ just
/// added, or why Return couldn't add the task.
struct NXCaptureNotice: Equatable {
    var text: String
    var failed = false
}

/// What `addCapture` made of the draft.
enum NXCaptureOutcome {
    /// Nothing but tokens, or nothing at all, was typed.
    case untitled
    /// The task, and the folded headings the capture opened to show it.
    case saved(Block, opened: [UUID])
    /// Why the task wasn't added, for the card; the draft stays.
    case failed(NXCaptureNotice)
    /// Tasks heard by voice, and the folded headings they opened; with why
    /// the rest weren't, when some weren't.
    case savedSeveral([Block], opened: [UUID], failure: NXCaptureNotice?)
}
