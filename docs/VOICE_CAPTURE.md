# Voice capture

Say tasks instead of typing them. Capture listens with the system's on-device
speech model, and Apple Intelligence reads what was said into separate tasks,
each filed into the list it names with its day, time, repeat, labels, priority
and estimate. Nothing said leaves the device.

## Where to start it

| | Mac | iPhone |
|---|---|---|
| Capture | the mic at the end of the capture field, or ⌥⌘V | the mic beside the Capture field |
| Straight into listening | the toolbar mic immediately beside **New task**, or File ▸ **New Tasks by Voice…** (⌥⌘V) | touch and hold the dock's **+**; no menu |
| Quick Add | ⌥⌘V in the floating card; an optional global voice shortcut, initially **⌃⇧⌥Space** | — |
| Control | **Say Tasks** in Control Center or the menu bar | **Say Tasks** in Control Center, on the Lock Screen or the Action button |
| Siri and Shortcuts | "Add tasks in Openlist", "Say tasks in Openlist" | the same |

Listening shows the words as they're heard: settled words in ink, the ones
still being made out paler. It stops when you pause (1.3 seconds once every
word has settled), when you press Return or Done, or after 90 seconds; Escape
cancels. The first use of a language fetches its speech model, with progress
on the card.

On iPhone, a tap on **+** still opens an empty typed draft with the keyboard;
opening it saves nothing. A hold starts listening without waiting for release.
Lifting your finger neither stops recording nor opens another draft. Press
feedback, haptics (when enabled), and **Listening…** indicate readiness. VoiceOver
can use the **Say tasks** action on **+** without performing a hold.
The dock tabs retain their Large Content Viewer; **+** deliberately uses its
hold for direct listening instead of a competing large-preview gesture.
An explicit **Say Tasks** route also starts listening in an already-open typed
sheet, without replacing its request, list or draft. Repeating it while voice
is active does not stop or restart recording.

## Global Mac voice shortcut

In Settings, turn on **Say tasks from anywhere**. It is **off by default in
every build**. Its initial combination is **Control-Shift-Option-Space (⌃⇧⌥Space)**.
Click **Voice shortcut** to record another combination; Escape or **Cancel
recording** keeps the old one. The choice and enable/disable switch are saved
on this Mac. Recording a combination does not enable the shortcut by itself.
Switching away from the recorder's window cancels recording and restores both
global shortcuts. Existing saved combinations are not replaced by new defaults.

While Openlist is running, the enabled shortcut opens the floating Quick Add
panel already listening over the current app, rather than requesting the main
window. Triggering it again resumes an existing typed or spoken draft without
replacing it, changing its destination, stopping a recording, or starting a
second one. Even a draft older than the normal five-minute retention window is
kept when resumed by the voice shortcut. Finish or clear it before starting a
new global voice capture; the card's mic can still add speech for review.

Use at least two modifiers (Control, Option, Shift or Command) with a letter,
number, punctuation key, Space, or function key. Bare typing keys and single
modifiers are rejected. **Shift-Option-Space (⇧⌥Space)** remains typed Quick Add,
and **Option-Command-V (⌥⌘V)** remains the in-app voice control; both are reserved.
An invalid combination gets feedback without replacing your saved shortcut.
Enabled macOS symbolic hotkeys (read through `CopySymbolicHotKeys`) and
Openlist's menu key equivalents are checked before recording or registration.
The app does not change system shortcuts. The default is checked too; if it
conflicts with this Mac's configuration, choose another combination.
If another app has registered the chosen global combination, Settings reports
the conflict instead of claiming it works. Choose another, or free it in that
app and toggle the switch off and on to retry. Other apps' ordinary, local
shortcuts cannot all be detected, so choose a combination you do not use there.

Both global shortcuts use the existing Carbon hotkey registration, not global
key monitoring; no Accessibility permission is requested. Debug/Dev **review
fixtures never register real global hotkeys**, regardless of saved settings.

## After voice capture

Both apps' Settings offer **After voice capture**:

- **Review before saving** is the default, also used for missing or invalid
  preferences. The field or task rows wait for Add/Return.
- **Save automatically** saves the recognized task or tasks once listening
  finishes, using the same destinations, dates, labels, store transactions,
  feedback and Undo as an explicit Add. A single task uses its recognized
  metadata directly, without re-parsing a generated text line.

This preference is per device, not synced. It covers the iPhone Capture sheet,
the Mac's main capture and floating Quick Add. It does not save ordinary typed
drafts automatically or change Siri's **Add Tasks** direct-save behavior.
The choice is captured when listening starts; changing it or showing a view
again cannot unexpectedly trigger a save.

Floating Quick Add keeps a successful automatic capture visible for three
seconds with **Undo** (also ⌘Z in the card). Its Undo remains available without
a main window. Typing, another capture, a failure or dismissing the card cancels
that success timer; it cannot close a later draft. Ordinary typed Return still
saves and closes immediately.

Speech over an existing draft always stays for review. Existing text and its
destination remain untouched, with spoken tasks as separate rows; add those
tasks, then continue typing the original draft. Previously heard rows are kept
too. A failed or partial save leaves **only the unsaved tasks** and an error for
manual recovery. There is no automatic retry, and successful tasks remain
undoable without appearing again in the retry batch.

Cancel, no speech, and permission failure never save. Cancellation invalidates
late recognition/interpretation callbacks. Switching away while the Mac's main
capture listens stops its microphone and keeps the words for review; an
intentional stop already being finalized or interpreted is not cancelled.
Passively closing the main capture (clicking away or opening another overlay)
while voice is active instead stops listening and forces review, even if the
words are already being interpreted. The capture card stays visible until
interpretation completes; a later passive close stashes the completed draft
normally. Explicit close or Escape still cancels voice immediately and rejects
late results.
Leaving during preparation cancels startup, so permission or model preparation
cannot start an unseen recording later. Floating Quick Add follows its own
keyboard focus, not app activation: putting it aside stops audio and retains
completed or pending words for review. Existing drafts remain subject to the
normal capture retention rules. On iPhone, leaving the active scene while
listening or already interpreting retains the result for review, even with
automatic saving enabled, rather than saving behind the app and starting an
unseen Undo timer. Explicit Done while the app stays active still follows the
save preference. Becoming inactive during preparation (including the first
microphone permission prompt) does not cancel startup; entering the background
does. Explicit Cancel always wins over an unfinished completion.

## What it does with what you say

With **Review before saving**, **one task** goes in the capture field as the line you'd have typed, aimed at
the list it named, so you can edit it before Return adds it:
"Pay the ryokan deposit by Friday on my Japan trip list, it takes 15 minutes"
becomes `Pay the ryokan deposit Friday ~15m` on **Japan trip**.

**Several tasks** wait as rows, each with its own chips and list; Return (or
**Add 3** on the iPhone) adds them all, with one Undo. The × on a row leaves it
out, and Escape puts them all away.
"Remind me to call the bank tomorrow at 9, and buy oat milk on my personal
list. Oh, and book flights for the Japan trip next Tuesday, it's urgent, tag it
travel" is three tasks: the bank tomorrow at 09:00, oat milk on **Personal**,
and flights on **Japan trip**, Tuesday, high priority, labelled travel.

What's read from the words said:

- **List**: "to my Kyoto trip list", "on the work list"; after *add* or *put*,
  a list's name at the end ("add call grandma to Family"); and a list's name of
  more than one word anywhere ("book flights for the Japan trip"). A one-word
  name alone is part of the task ("drive to work"). A task naming no list goes
  where the capture is aimed; one naming a list archived since goes there too.
- **Day, time and repeat**: everything typed capture reads, plus spoken forms:
  "the 3rd of October", "5 o'clock", "at 230". A spoken "at 1" to "at 6" is in
  the afternoon, where a typed "at 5" is 5am.
- **Labels**: "tag it travel", "tagged travel", "hashtag errands", "with the
  errands label". A second label after *and* counts when it's one of yours.
- **Priority**: "high priority", "it's urgent", "important" on its own,
  "ASAP"; "low priority", "not urgent", "no rush".
- **Estimate**: "it takes 15 minutes", "about 2 hours", "an hour and a half".
  "In 15 minutes" is when, not how long.
- **Filler**: "remind me to", "I need to", "um", "please" go.

A capture opened on Today makes undated tasks due today, and one opened on a
label adds that label, as typed capture does.

## How it's built

Four UI-free files, shared by both apps:

- `VoiceListener` runs `SpeechAnalyzer` with `SpeechTranscriber`, or
  `DictationTranscriber` where the device can't run it, fed by the microphone
  through `CaptureInputSequenceProvider`, or a recording through
  `AnalyzerInputConverter`. It biases recognition towards your list and label
  names.
- `VoiceTaskInterpreter` asks the on-device Foundation Models language model
  to split the transcript into to-dos, each with a title and the words said
  about it (`@Generable HeardTasks`).
- `SpokenCapture` reads everything else from the words themselves, so the
  model can't invent a list, a label or a date: a title the speaker never said
  (such as the instructions' own example) is dropped; each task owns the words
  up to the next one, so "…next Tuesday. It's urgent." is Tuesday's; and a part
  that only says how long, how urgent or where is the task before it's, even if
  the model made it a task. Days and times go through typed capture's
  `DateParser`. In a language `DateParser` doesn't read, the model's English
  day and time are used instead.
- `VoiceCapture` runs the two for the capture card and the Capture sheet.
  `VoiceCaptureSession` gates each recording's completion once, snapshots the
  save/review choice, and rejects cancelled or superseded callbacks.
  `NXCaptureDraft.receiveVoice` applies the shared Mac draft/save policy;
  the iPhone sheet applies the same session decision to its capture state.
  `Store.saveSpokenTasks` files the tasks, each as its own capture.

Without Apple Intelligence (off, not ready, or not on this device or
language), everything said is read as one task the same way, and the card says
how to turn it on where it can be.

Siri's **Add Tasks** (`AddTasksIntent`) reads what you say to Siri through the
same interpreter and filing, and says back what it added; **Say Tasks** opens
capture listening. "Add a task to ‹list› in Openlist" knows your lists.

## Privacy

The microphone is on only while the card shows it listening. Transcription and
Apple Intelligence run on device; the Mac app's sandbox adds
`com.apple.security.device.audio-input`, and both apps ask for the microphone
the first time you listen. No audio or transcript is stored.

## Checks

`./Tools/run-voice-checks.sh` (part of `check.sh`) checks reading and filing
with no microphone or model: transcripts as the speech model writes them, a
model's split grounded in what was said, and tasks filed into their lists. It
also exercises preference persistence/fallback, one-shot completion and late
cancellation, review/automatic saving, partial failures and manual recovery,
scene-departure review during listening and understanding, permission-prompt
preparation versus background cancellation,
tap/hold exclusivity, and shortcut validation/registration/routing through an
injected backend that cannot register real global hotkeys.

`./Tools/run-widget-workbench-checks.sh` checks the actual Mac capture handlers,
Undo, retained drafts, floating-card errors and feedback. `./Tools/run-capture-checks.sh`
retains the store's atomic capture and real read-only save failure checks.
`./Tools/run-ios-checks.sh` includes `VoiceCaptureUITests` for tap/hold/release,
keyboard focus, save/review, cancellation, retained text, Undo and settings
persistence. Native tests still require a configured Xcode and iOS 27 simulator;
direct compiler checks are not a replacement for a native build or UI test run.

`./Tools/run-voice-audio-checks.sh` runs recordings end to end through the
real speech model and Apple Intelligence into a library with lists, and checks
where each task lands and what it carries. It needs macOS 27 and fetches the
speech model on first use, so it isn't part of `check.sh`. Recordings are made
with `say`; set `OPENLIST_VOICE_RECORDINGS` to a folder of your own, named as
the scenarios, to try real voices.

In a Debug or Dev review session, `OpenlistVoiceRecording` names a recording
voice capture listens to in place of the microphone, for the simulator, UI
tests and screenshots. On the Mac the recording must be inside the app's
sandbox container.

For deterministic UI/lifecycle checks, **OpenlistVoiceFixture** instead supplies
newline-separated tasks. It stays listening until Done/Return, then uses the
normal completion and saving paths without microphone access, model downloads,
or Apple Intelligence. This environment override is honored only inside a
Debug/Dev review session. It tests UX and lifecycle, not recognition quality.
