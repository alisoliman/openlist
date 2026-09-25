# Openlist Next v2 — native implementation notes

Source of truth: `body.html` (markup) and `design.jsx` (logic) in this folder.

## Architecture

- `openlist/Next/` holds the UI. `openlist/Editor/` is the list document's engine and its
  AppKit-backed line text; `openlist/Views/` keeps the sheets, pickers and notices the Next
  screens host where the design has none of its own (list move and delete, template copy,
  the shortcuts sheet, due, repeat and reminder pickers).
- `NextTheme` — tokens (paper #FCFBFA, sidebar #F1EEEA, inspector #F7F5F2, ink #17161A,
  semantic colours), Instrument Serif (bundled, `Shared/Fonts`, so the widget has it too), density, motion.
  `NXEditor` (`NextEditorTypography.swift`) holds the document text's metrics and ink as
  NSFonts and NSColors, apart from `NX` so the rich-text codec needs no SwiftUI tokens.
- `Workbench` (@Observable, on AppEnvironment) — design interaction state: keyboard focus,
  visible order, completion dwell (`closing`), fresh/restored/flying rows, sidebar pulse,
  tray, session change log, inbox triage (kept/reviewed), G-prefix.
- `Workbench+Actions` — every design action (done, today, tomorrow, star, plan, priority,
  labels, move, trash, restore, keep, schedule, fit) goes through here: mutation via Store,
  undo registered on the window UndoManager (snapshot-based where Store has none, putting
  back only the fields the step changed), change-log entry, tray. So do the native extras
  that edit the same things: the inspector's Schedule, Repeat, Reminder and label popovers,
  its Defer work and the Clear on its deferral (a deferral's Undo puts back the calendar
  slots it took), the files attached and removed in its Files, and the Work panel's Move
  planned time… (a placement like Plan's, with Show off the Calendar), all with tray; and
  the inspector's title and note and a list's title and description (edits: logged, no
  tray). Move leaves a task already in the list where it is, as the design's move only sets
  the list (natively a move lands at the end of the list's top level); deviation: moved
  nowhere, its tray shows with no Undo and no log, and partly moved, its tray names every
  task, as the design's does, but only the tasks that moved log it.
- Completion dwell defers the real `store.toggleCompletion` until dwell+300ms; Undo during
  dwell cancels. Pending closings flush on termination.
- `NextKeyMonitor` — NSEvent local monitor implementing the global key model when not typing.
- Shell replaces NavigationSplitView: custom sidebar (236), 52pt toolbar with drag gesture,
  inspector overlay (360), tray, selection bar, capture/search/palette overlays, work notch.
- Modal flags reuse `navigator.isSearchOpen` and `navigator.isCommandPaletteOpen`; ⌘N goes
  through `env.presentTaskCapture()`, which opens the workbench capture
  (`workbench.openCapture`), so menu commands keep working. Over an open capture ⌘N, ⌘F
  and ⌘, stand down and its draft stays, as the design's keys do, and so do the menus'
  other window items (New List, New Section, Export, the View screens, Back, Forward, Hide
  Sidebar, Expand and Collapse All, the Work menu's, Keyboard Shortcuts); only ⌘K's palette
  replaces it. Capture aims at the list on show only while it takes tasks: on an archived
  list's page, a native one, it aims at Inbox, as Quick Add does. A save that fails says so
  on the card, as Quick Add's does, not in the tray under the backdrop.
- The macOS menus are native extras. Task ▸ names its items as the palette and row menu do
  and runs the Workbench's actions on the tasks its commands reach (in a list document the
  line being written, else the workbench targets in that list); its titles read every
  target, as the row menu's do, so both say Reopen or Unstar when every target is done or
  starred (the palette and bulk bar keep the design's Star). Its key equivalents all carry
  ⌘, since a bare letter would fire while typing and a ⌃ letter would take the text
  system's own (⌃T transposes, ⌃D deletes forward, ⌃L centres the line): ⌘D Mark as Done
  or Reopen (kept as the one key that completes a task while its line is being written),
  ⇧⌘T/⇧⌘M due today/tomorrow, ⇧⌘D and ⇧⌘L the due and label pickers (⌥⇧⌘ clears them),
  ⇧⌘S Star. Help ▸ Keyboard Shortcuts (⌘/) lists the design's single keys with the keys
  the list document and menus handle. Work ▸ Start Selected Task, Stop, Pause or Resume and
  Complete run `workbench.startWork`, `stopWork`, `toggleWorkPause` and `finishWork`, as
  Task ▸ Start Working and the notch's buttons do. Items that show something in the main
  window (Show Work, New Task…, New List, New Section, Search, Actions…, the View screens,
  Back, Forward, Hide Sidebar, Keyboard Shortcuts, Settings…) open it first when it was
  closed; Export List as Markdown…, Format ▸ Indent, Outdent, Move Up and Move Down, and
  View ▸ Expand All and Collapse All are on only while it is key. Format ▸'s inline styles
  are on only while a line in the main window has text selected, and Task ▸ Open Details
  (⌘↩) is off while a note is being written, where ⌘↩ finishes the note as the design's
  does. View ▸ Collapse All folds only what the
  design's carets fold (tasks with lines under them, headings with a section); Expand All
  opens every fold, one an older list left on a list item too. A line that becomes a
  heading, or stops being one, opens, so such a fold never hides a new heading's section
  (the design keeps a block's flag, which folds a heading turned into a block and back
  again).
- Too narrow for the whole toolbar, the crumb truncates first, down to its first 80 pt,
  then the Undo label, which at last leaves only its icon; Actions and New task keep their
  labels. The work notch, with no room for a few words of its title, drops the title, then
  its chip, keeping Pause or Resume, Done and Stop, and goes altogether rather than cover
  the crumb or the buttons, where the design's clips.
- A screen header's progress and controls wrap under its title when they don't fit beside
  it, as the design's; a title too long for its line wraps beside the tile, where the
  design's would drop under it. Deviation: a title or subtitle that wraps keeps SwiftUI's
  own line pitch, as SwiftUI takes no negative line spacing, so only a one-line box is the
  design's: a two-line title is 80.7 pt against the design's 71.4 in serif and 61.7 against
  59.4 in sans, and each further subtitle line 15 pt against 14.4.
- Deviation: in a window under 956 pt, opening details folds the sidebar away while they
  stay open, where the design's inspector only covers the page. The page keeps its width
  under the inspector either way; folding widens the strip left uncovered beside the
  sidebar and the 360 pt inspector (804 pt in the design's 1400 pt window), and it folds
  only where that strip would be narrower than the inspector, rows past the page's 40 pt
  margin showing under 320 pt (4 pt at the 640 pt minimum). The sidebar comes back when
  details close or the window reaches 1076 pt; View ▸ Hide Sidebar is separate, so this
  never shows a sidebar the user hid.
- Typing is on the window's undo stack natively, where the design keeps it out of Undo
  until a line commits. While a list document line holds typing, the toolbar's Undo names
  the step the line commits as ("Edited “…”", "Added “…”", "Removed an empty line"), which
  it takes back after finishing the line (the design drops the typing and undoes the step
  before), or, when finishing registers none, as for a new line left empty, the step under
  its typing; the tray's and Changes' Undo step aside until then. In other fields it reads "Typing", as Edit ▸
  Undo does, since that is what it takes back.
- Reduce Motion (the setting or the system's) fades the inspector, the notch, the bottom
  bars, the overlay cards and the Turn into card in rather than sliding them, and Trash's
  restored row out, the list document's new and converted lines (its rowIn and morphIn)
  rather than sliding them into place, and chips, the selection check and the cards and rows
  that lift in (Today is clear, the Inbox's done card, Planned now, Not planned yet, the
  inspector's Activity) rather than raising them, and eases the tick and switch knobs
  without their overshoot, as its hint says, where the design shortens the inspector's slide
  and plays the others unchanged. Each fade takes as long as that slide or rise. Task rows
  and calendar blocks keep the design's rowIn slide there, as the design plays it (a task
  row's shortened, a calendar block's at its fixed 380ms).
- New route `.settings` for the in-window Settings page: the design's groups, then every
  other preference. ⌘, and Openlist ▸ Settings… open it; there is no Settings window.
  Library › Back up library keeps the design's "Keeps 14 daily snapshots" (or why the last
  snapshot failed); a backup or restore made by hand, and what it reports, are Data's.
  In a row only the row tints under the pointer, as the design's; the value pills and
  buttons of the native extras outside one (the hours and iCloud panels, the Due, Repeat
  and Reminder popovers) darken instead, since nothing else shows their hover.
- Quick Add from anywhere is ⇧⌥Space, not the design's ⌥Space: ⌥Space types a non-breaking
  space in every text field, so a global hot key on it would take that from every app. The
  Settings hint, menu bar, shortcuts sheet and README all name ⇧⌥Space; held by another
  app, Settings' hint says so in red, and the menu bar drops its key cap and File ▸ Quick
  Add… its key equivalent. A task it adds goes
  on the window's undo stack and in Changes as the window's capture does ("Added to …"),
  but raises no tray: its own card says what it added, usually over another app.
- With Settings' "Read dates from what you type" off, a native switch, capture's ghost,
  its VoiceOver hint and the shortcuts sheet drop the date and repeat examples they give.
- Capture's chips follow the typed tokens in order, a typed day as "Fri 25 · in 2 days",
  as the design's. A bare time already past, or a repeat whose first day isn't today, shows
  the day it saves (tomorrow, the repeat's first day), where the design saves both today
  and shows no day.
- Capture opened on a label screen (N or its "Add a task" row), a native extra, also gives
  the task that label: the card shows it as a chip after the typed ones, and the task lands,
  fresh, on the label screen, so the tray has no Show. The design's saves it with no label,
  off the screen, and its tray offers Show.
- Trash keeps one entry per trashed task or list, not a row per subtask: the subtasks
  restore and erase with their task, whose row ends "· with N subtasks", and the sidebar
  counts entries. A list's Restore names where it goes back, as a task's names its list
  (under its parent, or at the top level once the parent is gone), and Undo takes it back
  to Trash as a task's does. A task whose list, or the task it was under, is gone goes back
  to a pinned Recovered items list, a native extra, the one there is or, with none, a new one;
  one renamed or given another description is the user's own, and the next such restore makes
  a new one. Its tray and log entry, Earlier's too, add where it came from ("… to Recovered
  items — from Work › Launch"). Its Undo puts it back in Trash as it was, from its old place,
  and takes a Recovered items list it made, left empty, with it, a window on that list going
  to Today; Redo makes it again. When Trash can't be read, the page says so under the notice,
  never "Trash is empty.".
- The Lists gallery's subtitle is the design's "N lists in 2 sections", counting the sections
  that hold lists; lists in no section (the "Other lists" shelf, a native extra) and archived
  ones follow it ("· 1 in Other lists · 2 archived").
- Lists are the design's document (`NextDocument.swift`): `NXDocumentOutline` draws the
  `OutlineEditor` engine, which keeps the design's rules (`OutlinePolicy`), tasks on `NXTaskRowChrome` (the
  Next row's chrome with the live text as its title) and the other kinds in the same
  language. Done top-level tasks leave for the Completed group below. Each line's edit is
  one undo step with the design's label and a change-log entry. The Tasks presentation is
  the same document showing only its tasks, where a line turns into no kind it wouldn't
  draw (a native extra): the design's prefixes stay as typed or pasted, "/" opens no Turn
  into card, a heading pasted or dropped into an empty task goes in after it as a step of
  its own (a new task left empty going once a pasted task takes the caret, as one left
  empty does), and the hints, add row and task placeholder offer only ⇥ Subtask, ⇧↩ Note
  and Space Show note ("Add to …").
  Return there opens a first subtask only under a task whose tasks show, as the design's
  does under a subtree that shows; ⇥ goes by the depth a task has in the document, not the
  one drawn, and ⇧⇥ steps a task out past the headings, list items and text lines holding
  it, to beside the task it's drawn under, so the step always shows. Format ▸ Move Up and
  Move Down (native extras) take a line past the nearest line beside it that shows,
  passing those between with nothing drawn (a done task in Completed, the lines a folded
  heading holds or, showing only tasks, a heading, list item or text line with no task
  under it). A folded heading whose section the move puts lines in opens, while a heading
  at a folded one's level or above, moving down, goes past it and its section, which stays
  folded, so each press moves it on screen and one with nothing there records nothing.
  Rows selected together (⌘/⇧-click, X, ⌘A) move together, as Indent and Outdent and
  their drag take them all, as one step named and logged for the rows that went ("Moved
  3 lines down"): each past the nearest line beside it that shows, unless that line is
  moving too or holds a row that is, so they keep their order. One that can't go (at the
  top or bottom) holds back only the rows that would pass it; the rest still go, closing
  up to it.
  `Navigator.documentListID` (any list, and the Inbox shown as a document) and
  `documentOwnsEditorCommands` replace `hasDocumentEditor`.
- The inspector's "Subtask of" crumb and Subtasks section follow the design; Add subtask
  writes the new line in the list document (`Workbench.addSubtask`,
  `OutlineEditor.appendSubtask`), after the task's last line and at its depth, as the
  design's does, but never past two levels and only under a task or list item, which
  older outlines can break. ⇥ keeps to them too, counting the lines under the line: one
  whose subtree would go past two levels stays, where the design's indent moves the
  subtree along unclamped. MCP's create, move and append tools place lines by the same
  rules (`OutlinePolicy`), refusing a heading or text under a line, or a third level.
  Markdown pasted or dropped as several lines, and Openlist content pasted after a line
  (native extras), keep to them too: a line its indent can't put under the one above goes
  beside it, as far out as it must, and copied content steps out beside the lines it was
  pasted under until what it holds fits, anything an older outline holds deeper coming up
  to the second level. Text dropped from another app on a line's row, beside its text,
  goes in before, after or inside that line as the drop's indicator shows it (before the
  line holding it when the first can't go that deep, inside only where its lines can nest
  there, otherwise after it, as a line dragged there does), or,
  on the line being written while it's still empty, fills it in that line's step. Openlist
  content pasted after a line, and text dropped on a row, are each a step of their own,
  after the line being written, named for the lines they put in at their top level
  ("Added “…”", "Added 3 lines") and logged, as a line's edit is.
  The Inbox's document mode is the same list document under
  the Inbox header, so unlike the design (whose Inbox has no document) an Inbox task lists
  Subtasks while the Inbox shows as its document, or once it has some; its Add subtask shows
  the Inbox as its document. Native inspector extras: the title and note are edited in place
  (in the design's line boxes, a done title struck through even while written; the note
  with the document note's keys, Return breaking its line, Esc, Tab or ⌘↩ finishing it and
  ⇧Tab going back to the title, and the title kept to one line, as a document line is:
  Return or Esc finishes it, Tab goes on to the note when one shows, else finishes it, and
  a paste's breaks become spaces;
  the note saved as the document saves one: trailing space goes, and an emptied note closes
  under its task; a click off the field, on a row, subtask, crumb or pill, ends the edit as
  a browser blurs an input, and the caret never follows to another task, so the keys act on
  the row, while one in the note's box puts the caret at the nearest place in it, as a
  textarea's padding does, a click on a capture, search or palette card over the panel
  staying the card's, and a box left empty closes once the click is over, so what was
  clicked below it doesn't move away) and files kept with the task. As the design, the note shows only when there
  is one; until then a quiet "Add a note" row stands in, with "Attach a file" beside it until
  the task has files, when Files shows. Files dropped anywhere on the panel are attached;
  attaching snaps with Undo, which takes the files off again, and removing one does too, its
  Undo bringing the file back. The plan card ends with a quiet "More options" disclosure
  (estimate hints, how sessions run, the list's hours, Defer…, time recorded and Work
  history), and Activity with "Full history", the task's saved activity; both start closed.
  The footer is the design's Trash and Start working. Deviation: a completed task's Plan for
  today switch fades and Start working is off, as Plan and work skip completed tasks, where
  the design's still toggle and start; the row menu's and Task ▸'s Plan for Today, Find a
  Slot and Start Working are off for it too. Copy Link is in the task's row menu and in Task ▸,
  which reaches the inspected task from the keyboard too, each saying "Link copied" in the
  tray. The Schedule popover's tabs are the rows' Due, Repeat and Reminder, in their order;
  it fits its section, up to 510pt, and its date and time controls are Next pills. It writes
  days and times as the app does: its Reminder header as the Reminder pill, in the Due row's
  words ("Fri 25 09:00"), and a typed phrase as capture's chips. Its day pills and a
  repeat's Next occurrences add the year to a day in another year past the week, as saved
  history does (`MomentText`, below), where the Due and Reminder rows keep the design's
  dueLabel. Its Due tab clears a date with the Due row's grey None, and its Reminder tab's
  Remove reminder is grey too, red being for deletions; that tab says in plain words
  whether and when the task reminds you ("Reminds you at the due time, today 18:00",
  "Off while the task is done"). A timed task with no reminder of its own, which reminds
  you at its due time, says so: the pill reads "At the due time", the header adds the
  time beside a grey bell, and the tab's At the due time is lit. Done first sets a due
  time still being typed as Custom…, and Set reminder a reminder time. "Remind me at" is a draft only Set reminder
  sets: Done keeps the reminder there was, over a day or time picked there, or still being
  typed. The label picker (⇧⌘L) lists the name typed first, then labels starting with it,
  and Create last, only for a name no label has; Return picks the highlighted row, the best
  match, which ↑/↓ and the pointer move. Move List…'s parent search does the same: typing
  chooses the first match and ↑/↓ step through the rows, so Return moves under one on show.
  A list's menus (the sidebar's, a Lists card's, a nested list row's and the page's "…")
  share one set of commands in one order (`NXListMenu`), native extras all: Open, Show
  Tasks Only and Hours, Rename (the sidebar's, in place), Move and New Child List, Copy
  Link, Copy as Markdown and Export, Duplicate and Use as Template…, Pin and Archive, then
  Delete; the "…" menu adds the page's Sort, Completed Tasks, Icon & Colour…, description
  and cover after Hours, and has no Open. Copy as Markdown, beside Export as Markdown…, puts
  the Markdown Export writes on the clipboard (`MarkdownExporter.copyToPasteboard`) and says
  "Copied “List” as Markdown" in the tray, as Export says "Exported “List” as Markdown" once
  written. A list menu's Hours picks the Work or Personal hours Plan and Start working use
  for the list, which the design takes from its section; the list page's subtitle stays the
  design's "N open · Section".
  Native extras on the list page: the "…" options menu, the title renamed in place, the
  description, cover and nested lists, a drag grip on every line (drops go through
  `BlockDragAndDrop` under the design's nesting rules, and onto sidebar lists and the
  Inbox, which drag on a private type of their own that no line takes, and move any line
  there, a heading or text too, with the move's tray and Undo; a screen row, like a grip,
  drags the rows selected with it, and rows all in that list already are refused, as is any
  line but a task on the Inbox while it shows as triage, which draws only tasks), and search
  reveal scrolling in `NXPage`. Open notes are remembered per task on this Mac.
- Today's, a list's and a label's Completed groups fold as one, as the design's
  `completedOpen`: the last fold shows on every screen (`NXCompletedFold`). Until the user
  folds one, each opens as its setting says: a list's own Completed Tasks (a native extra),
  else Show completed tasks. Deviation: they fold with Show completed tasks on too, where the
  design keeps them open, and changing that setting drops the fold, so every group opens as
  the setting now says (the design keeps an opened fold open when it goes off). A list's new
  Completed Tasks shows on that list at once; Today, labels and other lists keep the fold
  until the next one.
- Today's open groups, a label's open tasks and Tasks keep the order the lists show their
  tasks in (lists in sidebar order, each in its document's order under the page's Sort, a
  native extra), the native counterpart of the design's task order, and none sorts them by
  date itself; a new task sits where its list put it, where the design's goes after every
  other. Deviation: a list's and a label's Completed group lists the most recently finished
  first, as Today's Completed today does, where the design's keeps its tasks' order.
- A repeat reads in macOS sentence case ("Every day", "Every weekday"; a day's name keeps
  its capital, "Every Wednesday"), where the design title-cases a captured one ("Every
  Day"). The same words show in the inspector, the tray, Markdown export and MCP.
- Back and Forward, a native extra, return a page to where it was scrolled when it was left:
  each visit in the navigator's history keeps its own offset, which `NXPage` takes on
  appearing. Any other arrival (the sidebar, a link, a new visit from the history) opens the
  page at the top, or on what a search hit or link reveals.
- Where the list document departs from the design, to keep native data safe: a done
  top-level task stays in the document while a task under it is open; a line left empty
  goes only when it was new or emptied in its edit and holds nothing but text (Backspace
  also takes one that was already empty); a line's undo step leaves alone what anything
  else changed in its task meanwhile (`EditorEditSession`); a new line opens whatever
  heading or task folds it away, and so does a task captured into the list from anywhere,
  the folded headings it goes in at the end of (Undo folds them again). Headings and text
  take no key focus after Escape, as in the design; Return writes them again and J/K step
  to the tasks beside them.
- A line turned into a heading or text keeps the lines under it, as the design's convert
  leaves their depth alone: they still draw a level in under it, Tab on the task or list
  item after them takes it in as the last of them, as the design's indent goes by the line
  right above, and turned back into a task or list item it holds them again. In the Tasks
  presentation a task under one, with no task above it, is a top-level task, so done it goes
  to Completed. Deviation, of the tree the document is stored as: a nested line so turned
  takes the lines under it out a level with it, so one two levels in ends one level in,
  where the design keeps it two; and Return on such a heading opens its new line after them,
  where the design's opens it right under the heading.
- Inbox triage skips a subtask while an open task above it waits, as that task's card
  carries it; one under done tasks only is triaged as its own card. The triage card's File
  into names wrap at words, as the design's; in a column too narrow for a name's longest
  word, in the narrowest windows, the name truncates to one line, where the design's row
  would run past its column.
- Widgets (`OpenlistWidget/`) depart from `widgets/` where WidgetKit sets the terms. Only a
  row's circle is its toggle, so a tap elsewhere can't tick a task the widget can't undo;
  while the tick's intent runs the system dims the rows beside their circles
  (`invalidatableContent`) in place of the design's faded, struck-through row. A tick made
  while Openlist is quit shows done straight away, from the rows the app last published: a
  list's first 12 open tasks, Today's first 10 overdue and 15 a day, and Inbox's newest 8,
  spares past the rows a widget draws, so once queued ticks outnumber the spares the rows
  thin out, the counts still right, until the app opens again, where the design always
  moves the next open tasks up. A tick and its untick made while it's quit cancel out, so
  the task keeps its place, its slot and any paused work (the design's tick ends the work);
  a task the app published done, reopened in the widget, leaves the Agenda, as a reopened
  task leaves the calendar, and goes after the list's open rows until the app opens again,
  where the design's goes back to its place. In medium and
  large a row's title and list line open the task; a small widget takes only its own link,
  so small Today's titles open Today. Quick Add's Triage link shows the Inbox as triage for
  that visit even where this Mac shows it as a document; its Inbox link follows this Mac's
  choice. macOS may make Openlist active as it opens a widget's link, bringing its window
  forward behind Quick Add's card; the card then gives focus back to the app you were in,
  and hides Openlist again if it was hidden, when it closes. Large Today's New task opens
  Quick Add as Today's own add row does, an undated task due today, so it shows in the
  widget; the design's footer is plain Quick Add. A List widget whose chosen list is gone
  shows the first list, as an unconfigured one does; with no list besides Inbox it reads
  "No lists" and opens Lists, where the design always has a list. Large List's add chip
  names the whole list ("Add to Weekend in Kyoto"), as the app's add row does, where the
  design's names a short form lists don't have ("Add to Kyoto"); a name too long to fit
  whole reads "New task", as Today's chip does. Quick Add counts an Inbox task's first hour
  in minutes ("12m"), a native extra: the design's ages start at "2h". The
  gallery's sample week is the one today falls in: today has the design's Wednesday and
  every other day its own weekday's meetings (on a weekday today's own move to Wednesday; a
  weekend's give way), and planned slots stay on their tasks' due days, after any meeting
  there; on a Wednesday it is the design's own week.
- Calendar: running work past its slot follows the design's overrun (the slot grows to the
  next quarter plus 15 min, later placements that day move out of its way, saved and
  undoable, stopping only at meetings and breaks; Undo still moves them back after Pause,
  Stop or Done). Where it departs, to keep the list's hours: the block also stops growing
  at their end, and a moved task stays inside its own list's hours that day (the design
  allows up to 21:00), or where it is when none are left. Work with no slot, which the
  design never grows, is drawn from when it started up to its estimate or the next placed
  task, then grows and moves later placements as a slot does. Time away from the Mac, for
  work that tracks away, stops counting at the next pinned task instead of moving it.
  Resumed work reads "working" until it grows again. Busy holds of 20 h or more (Out of
  office) aren't drawn as meetings but still keep Plan and the planner away, so the day's
  header names them. Breaks are set in Settings, where the design has only its lunch: one
  that takes in any of 12:00–13:00 is named Lunch, as the design's; any other reads as a
  break. A block's title keeps its lines and its time and state wrap under it, cut off at
  the block's edge, as the design's; the last whole line of a cut state ends in an ellipsis.
  Lanes follow the items' times, as the design's (a meeting before a block with the same
  times), done blocks in their slot included, except for recorded work the design never draws
  (time tracked outside any slot, work running or paused with no slot): it takes lanes by its
  drawn box, so a few minutes of it isn't hidden under the block after it.
  The grid's hours, the design's fixed 8–21, stretch to fit anything scheduled outside
  them in the days shown; a new span re-lays the grid at once, as the design's range
  re-renders.
  A task reopened from its row, or a widget's, leaves the calendar: its done block goes, and
  its slot with it, where the design's reopen leaves the block in its slot, tinted again; a
  done block's own check reopens it there.
  The Work panel's "N tasks rescheduled" and Start notifications come only from blocks the
  calendar draws, not from the planner's own sessions, and no Start comes while work is
  running or paused, as the design's "Planned now" hides then. A long Planned now title
  wraps and the banner grows, as the design's, never inside a word; its label and time keep
  to one line until the title is down to its longest word, where the design's flex row
  squeezes all three at once. Where not even that word fits beside them, in the narrowest
  windows, the title truncates to one line, where the design's row would run past the banner.
- Calendar week: the design's week always has today on a Wednesday. Natively, Plan keeps to
  the week around today while it has hours long enough for the task (the design's "No free
  slot this week"), then goes on into the next week, as a deferral past it gets its own. A
  block landing past the days shown moves the Calendar's range there, and the header's
  ‹ Today › steps the range a day, three days or a week at a time. A range stepped or moved
  to holds only that day: from the next, the Calendar shows the range around today, as the
  design's always does. What opens the Calendar on something brings the range back to it,
  as the design's Show always lands there: a calendar nudge's click and the Work panel's
  View plan to the slot's day, Plan's Show to its block's, the Show of the work trays
  (running into, extended, paused), the Work panel's Review plan and Open calendar and a
  tap on the Up Next or Agenda widget to today's. On the Calendar, the work trays keep
  Show while its range doesn't show today, and a tray that has Show offers it there too
  while the range is off the day it points at. Today's Look at tomorrow moves it to
  tomorrow, where the design's Day view stays on today.
  "Not planned yet" takes tasks due from a week back to the end of the week around today
  (the settings week, as Plan searches it), or four days out when that is later: the
  design's −7…+4, whose +4 is its Sunday.
- The Work panel, Work history, the inspector's Full history, Changes' details, Merge
  labels, Settings › Data and Notifications, native extras, write a moment as the pills and
  the Calendar do: "Today 10:00", "Fri 25 10:00", with the year only when it isn't this
  one, and the Schedule popover's day pills a day so; one helper writes them all
  (`MomentText`, through `NXFormat.moment` and `dayLabel`). A planned slot reads "Today
  10:00–11:30 · 90 min", and the hours editor names an override's day as the pills do.
  Work history words a session's pause as the Work panel does, and the panel's completion
  reads "Done", a repeat's "Rolls to Wed 30", as the tray does.
- The tray is the one passing feedback, as in the design, and VoiceOver hears each message
  (with "Undo with Command-Z" when it offers Undo). Redo, a native extra, says "Redid — …"
  with Undo, as Undo says "Undid — …"; one of a task's Trash that moves nothing, either way,
  says "Could not …", keeps the log as it was and leaves the stack. Completions made outside Next's rows
  (menu bar, calendar, notifications, MCP) report there too, their Undo the Store's
  completion entry, and so does Settings' Export… ("Exported N lists as Markdown"). One-off
  refusals (`Store.refuse`: a drop the document's rules don't allow, rearranging a sorted
  list, a line command on the lines a paste left selected) pass there; what needs dealing
  with (saving, sync, links, label maintenance, Trash failures, failed undos) stays a
  notice card, all of them in one place under the toolbar. So does an export, Copy as
  Markdown, cover change or image that fails, and a file that can't be attached or opened,
  where system alerts were: a red card (`Store.actionError`), one for files that fail
  together; and a Duplicate, a move that couldn't be saved (from the menu, the sidebar or a
  drag), Copy Content and Subtasks or its paste that fails. A move refused, which changed
  nothing (another editor operation running, a destination gone), passes in the tray.
  VoiceOver hears each card as it appears (`NextNotices`), but sync's warnings, which no
  action set off.
- Native extras that snap like the design's actions, with Undo and a log entry: Delete List
  (`Workbench.trashList`, "Moved “…” to Trash" with Open Trash), a list's Duplicate, Use as
  Template… (the copy opens; Undo takes it to Trash) and Move List…, a list dragged in the
  sidebar, New and Delete Section (New Section also opens its name field; a rename is logged
  as an edit), the "…" menu's Sort, Completed Tasks and Cover, Delete Label (sidebar and
  Settings; Undo puts it back where it sat on each task), Settings' Add, rename and colour
  of a label (a name another label has says so in the tray), Merge labels, a list's Icon &
  Colour…, and the task menu's Duplicate and Use as Template…. The menu's Copy Text and
  Copy Content and Subtasks (for Paste in a document line), every Copy Link and AI
  Agents' Copy configuration and Copy token only copy, saying so in the tray. An Undo or
  Redo of a label or list change, or of a Restore, that fails says so in the tray, keeps
  the log as it was and leaves the stack.
  An edit logged while the tray still shows an earlier change, like a new section's name,
  takes that tray's Undo away. Deviation: a merge undoes in turn on the window's stack, by
  ⌘Z or the tray, where the old "Undo merge" card took back the latest merge out of order,
  keeping later changes. Deviation: "Confirm before deleting a list" stays a preference
  (on by default), asked in a Next sheet; the design asks nothing, as Undo covers it.
  Settings' own confirmations, for what no Undo takes back (Clear all activity history,
  Delete everything, Return to original library, Reset access token), are Next sheets too,
  where Return presses neither button. Delete everything also clears the window's undo stack
  and Changes' This session; the tray then says "Deleted everything for good", with no
  Undo. Clear all activity history empties Changes but keeps the undo stack; its tray says
  "Cleared all activity history", with no Undo. Their buttons, and the inline hours
  editor's, are `NXPanelButtonStyle`. Format ▸ Add Link… (⌘L) asks for its URL in a Next
  sheet too (`NXLinkSheet`; Return applies, Esc cancels), and Trash's hold-to-erase asks
  VoiceOver, which can't hold, in the confirmation sheet. Deviation: the only system alerts
  left are the window's shown when the library can't open, which has no shell, tray or
  notices; their buttons keep the system's Title Case, where that window's own buttons are
  in sentence case.
- Activity › Changes › This session is the log, with the saved history it didn't write
  merged in (MCP, another Mac). What a list document line saves to its task while it's
  written (the new task at Return, its title as typed, the line itself when it goes)
  reaches saved history as one entry once the line ends, as the design logs it: "Added
  “…”", "Edited “…”" or "Removed an empty line", or none for a new line left empty. So a
  task's line reads the same in Earlier after a relaunch, as do a label added, a note, a
  restore and a date, which Earlier names as of when it was set. The history one change
  saves, a task each, shares a batch, so Earlier (and This session's saved history) shows it
  as the log's one row: "Moved 3 tasks to Trash", "3 tasks → Tomorrow", "Moved “Trip” to Work"
  for a task moved with its subtasks, "3 tasks done" for one done with two open subtasks (but
  those a repeat resets as it rolls on), a list trashed, restored (where to, as its tray said),
  duplicated or copied as a template as its own row, and its 40 rows are changes, not events;
  a completion's Undo and its Redo are a change each. A date names its time only
  when the change set it, so a timed task moved by a date pill reads "→ Fri 25", as the
  design's pills do. Deviations: tasks pasted into a line keep an "Added" each there, and a
  heading or text line, which has no saved history, shows in This session only (one MCP
  adds reads "Added “…”" in both); a note shows in Earlier only when it was first written,
  the one change to it saved history keeps; a repeat set with a date shows in This session
  only, and Earlier's "archived list" is of the list as it is now. History saved before
  this shows as it was recorded. The day panel lists saved completions, so a task trashed
  since still shows there with its list, as the design's does, and one erased since with
  the list it was done in; only one still in the library opens. Its counts are of what is
  still done, as the design's: a completion taken back by Undo or Reopen leaves the day,
  total and streak, and one done again counts on that day. A Changes row whose list is
  gone since shows it with the icon it had, as the day panel does.
- A route to a list or label deleted since (Back to a list now in Trash) shows the dashed
  empty box with Open Trash, Open Lists or Open Tasks. A search hit in the note of a heading
  or text line (only native data gives those notes) shows that note under the line as the
  design's note block, the match in the accent. Deviation: that "Matched note" card stays
  where the reveal notices went, as the only place such a note reads.
- Reminders, item links (Copy Link, widget rows) and search hits land as the design's
  search does, with no notice: on the task's list or the Inbox, its row focused and the
  inspector open. A hit on a line past the design's (heading, text, a note, a list
  description) opens that list's document for the visit, the Inbox's too, puts the caret at
  the match and takes the tint of the design's fresh rows (`A+1C`, held 1.2 s, fading as their
  700 ms background transition), a native extra: the design's search lands only on tasks,
  and its line with the caret would drop the tint. Such a reveal keeps folded and done lines
  on its path shown until the page is left, a revealed parent is folded, or Esc, with no
  details, selection or focus left to close, ends it in place; the document lasts the visit.
  Only a target that can't open says so, in a notice: one grey untitled card, for a reminder
  as for an item link or widget row, whether the target is gone or the link isn't this app's
  or library's or can't be read. A library whose link identity can't be read says so in red,
  as a Copy Link that fails does, with the app's other failed actions. A hit reads as the
  design's two lines, a task's whose note alone matched ending "· matched in note"; a
  heading or text line's also quotes the passage under its title when the line is long or
  its note matched, and a list's its description when only that matched.
- The editor's kinds past the design's five (Heading 3, Numbered, Quote, Code, Divider,
  Image) are a native extra: their lines draw and edit in the document (an image's
  caption, 12pt under it, is written in place: a click on it, or on the "Add a caption…"
  a hover fades in over the row an image keeps for it (so no line below moves), edits
  it, and Return or a click away commits it as a step of its own, "Edited caption on
  “Image”", logged as a line's edit is, a line that click opens (the add row's, Add
  subtask's) staying open with the caret; by pointer or VoiceOver only,
  as in the old editor, since the keys pass over an image line), the Turn into
  card brings them up for their names after "/" (with no query it shows the design's
  five under its one header, and a single letter filters the five by label as the
  design's does), and a line's Turn Into menu lists them all. From the second letter
  the editor's search words bring kinds up too, so `/h1`, `/todo` or `/hr` find Heading,
  Task or Divider, and a query can list a kind whose label doesn't hold it. Only the
  design's prefixes (`# `, `## `, `- `, `* `, `[ ] `, `[] `, `> `) convert a line, as it's
  typed or as a paste or drop at its start leaves it starting with one (so a pasted
  `- [ ] Buy yen` makes a list item, as only `- ` matches at its start in the design's
  anchored pattern; text dragged within the line itself stays as dropped, where AppKit
  moves it), and only the design's five show one in the card; the editor's inline
  `**bold**`, `_italic_`, `~~strike~~` and `` `code` `` rules still style it, as the
  Format menu does. A right-click in the line being written
  offers the Format menu's styles in place of AppKit's Font and Layout Orientation menus,
  whose fonts, underline, colours and sizes the document doesn't keep.
  ⇧↩ types a soft break only in a code line, and a code line keeps its indent where the
  others are stored trimmed, as the design's commit does, once the caret leaves them.
  A paste keeps a line to one line, as the design's input does: over a selection, or as a
  drop into the line, each break it brings becomes a space, and Openlist content goes in
  as the text of its lines, a space between them. Native extras, with nothing selected:
  Openlist content goes in whole after the line (or as far out as its levels need), and
  several lines of text become lines of their own after it (filling it while it's empty),
  read as Markdown, so `- [ ] ` there makes a task. Under Paste and Match Style, Openlist
  content does too, even as one line, read from the content itself rather than from its
  Markdown, which is written for other apps: each line's kind, place, plain text,
  completion and note, without its styling, star, labels, dates or files, a quote as text
  and an image left out. Both go in under the document's rules: `> ` makes
  text, or right under a pasted task that task's note; a line nests under the line it was
  pasted under only when both are tasks or list items, two levels deep at most, and
  otherwise goes beside it, stepping out after the lines already under it, so a heading or
  text line pasted under a nested line comes to the top after that line's task and the
  document's lines keep their places. A paste that doesn't read line for line as Markdown (a
  blank line, trailing space, an indent a list wouldn't have or a fence anywhere in it) comes
  in whole as a trimmed text line for each non-blank line, markers and all, a fenced block
  as one code line. A code line takes a paste as it is.
  The card opens above its line when it wouldn't fit under it on the visible page, and a
  row the pointer moves onto takes the highlight.

## Status checklist

- [x] Theme tokens, font, settings props
- [x] Workbench state + actions + undo + tray + change log
- [x] Key monitor
- [x] Shell: sidebar, toolbar, notch, inspector host, tray, selection bar, overlays host
- [x] Row + group components
- [x] Today, List, Label screens
- [x] Tasks screen (query + sentence)
- [x] Inbox triage
- [x] Inspector
- [x] Capture, Search, Palette
- [x] Calendar (grid, not planned yet, plan, planned now, overrun)
- [x] Lists gallery, Activity (+ Changes), Trash (hold), Settings
- [x] Build + native verification screenshots
- [x] List document: lines, carets, notes, Turn into, completed split, keys, undo and log
- [x] Inspector subtasks and "Subtask of", Inbox document mode, list options menu,
      title in place, drag grip, search reveal
