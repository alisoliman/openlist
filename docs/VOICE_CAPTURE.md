# Voice capture

Say tasks instead of typing them. Capture listens with the system's on-device
speech model, and Apple Intelligence reads what was said into separate tasks,
each filed into the list it names with its day, time, repeat, labels, priority
and estimate. Nothing said leaves the device.

## Where to start it

| | Mac | iPhone |
|---|---|---|
| Capture | the mic at the end of the capture field, or ⌥⌘V | the mic beside the Capture field |
| Straight into listening | File ▸ **New Tasks by Voice…** (⌥⌘V) | long-press the dock's **+** ▸ **Say Tasks** |
| Quick Add | ⌥⌘V in the floating card | — |
| Control | **Say Tasks** in Control Center or the menu bar | **Say Tasks** in Control Center, on the Lock Screen or the Action button |
| Siri and Shortcuts | "Add tasks in Openlist", "Say tasks in Openlist" | the same |

Listening shows the words as they're heard: settled words in ink, the ones
still being made out paler. It stops when you pause (1.3 seconds once every
word has settled), when you press Return or Done, or after 90 seconds; Escape
cancels. The first use of a language fetches its speech model, with progress
on the card.

## What it does with what you say

**One task** goes in the capture field as the line you'd have typed, aimed at
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
- `VoiceCapture` runs the two for the capture card and the Capture sheet;
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
model's split grounded in what was said, and tasks filed into their lists.

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
