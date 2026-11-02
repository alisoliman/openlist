# Capture

New tasks start in a capture: the Mac's card (N, ⌘N, or the toolbar's **New
task**), Quick Add floating over any app (⇧⌥Space, the menu bar, a widget),
the iPhone's Capture sheet (the dock's **+**), or by voice
([Voice capture](VOICE_CAPTURE.md)). Each saves into the list it's aimed at,
the Inbox unless a list's page opened it.

## What the words say

What's typed is read as it's typed, each token tinted, and the chips under the
field show what Add saves:

| Typed | Saves |
|---|---|
| `friday 6pm`, `in 2 weeks`, `every monday` | The day, time and repeat, while Settings reads dates from text |
| `#errands` | A label; one nobody has yet shows as **New #errands** before Add makes it |
| `@Groceries`, `@Japan trip` | The list it goes to, in place of the one picked |
| `!high`, `!med`, `!low` (`!3`–`!1`) | Priority |
| `~15m`, `~2h` | The estimate |

An `@` names a list by its whole name, spaces and all, the longest name it can
be; a name nobody has, or an address like `bob@home.com`, stays text. "Buy milk
to @Groceries" saves "Buy milk". Picking another list, by its chip or Tab, takes
the token out of the text.

While an `@` or `#` is being typed, the lists or labels it could become show
under the field, those whose names start so first. On the Mac ↑ and ↓ move
through them and Tab or Return takes one; Escape puts them away until the text
changes. On the iPhone a tap takes one. A name typed in full suggests nothing,
so Return adds the task as typed.

## Words read wrongly

A word read as a date, a label or a list by mistake goes back to being words:
"Buy sun cream" reads *sun* as Sunday. On the Mac a click on its chip keeps it
as text; on the iPhone, its chip's menu, or the date chip's, has **Keep “sun”
as text**. It stays in the title, wherever it's typed in this capture, and
the rest is still read: "Buy sun cream fri" is then due Friday.

## A note

⌥↩ on the Mac, or the note button beside the field on either device, opens a
note line under the title; on the Mac ⌥↩ goes back to the title. The note is
saved with the task, without trailing space, and a capture put aside keeps it.

## Several at once

- **Paste a list.** Lines pasted at once wait as rows, a task each, read for
  their own tokens, `@list` included; bullets, numbers and boxes go, and items
  ticked done (`[x]`, ✓) are left out. Add (Return on the Mac) adds them all,
  with one Undo, and what was typed stays in the field. A single line pastes as
  words; on the Mac ⇧⌘V pastes lines as one.
- **Add another.** On the Mac ⇧↩ adds and keeps the card. On the iPhone Return
  adds and clears the field for the next task, aimed at the same list, saying in
  the sheet what it added, with Undo; **Add** adds and closes, and **Done**
  closes once the field is empty.

## From other apps

- **Mac:** select words or right-click a link in any app, then Services ▸
  **Add to Openlist**. Quick Add opens with them as the title and a link as the
  note, to edit, aim and add; nothing is saved until Return.
- **iPhone:** the Share sheet's **Add to Openlist** takes a page, a link or
  text, with the words to edit and the link as the note. It's left in the App
  Group, and the app files it into the Inbox, or the list an `@` names, the
  next time it comes forward, with one tray and Undo for everything shared
  meanwhile. The extension never opens the library. Unsigned builds have no
  App Group and say so.

## Checks

`./Tools/run-capture-checks.sh` covers the grammar (lists, words kept as text,
notes, the triage edit line); `./Tools/run-shared-logic-checks.sh` the draft's
suggestions, pasting, destinations and Snooze. `./Tools/run-ios-checks.sh`
includes `CaptureTriageUITests`, and verifies the embedded share extension.
