# BRI-27 / OL-007 — complete search and exact reveal

## Automated validation

`Tools/run-search-checks.sh` runs production snapshot, projection, query-session,
selection, target-resolution, Navigator and BlockTree code against saved
SwiftData fixtures. It covers more than 80 matches and every keyboard page
boundary; duplicate titles and stable ties; case/accent/width and extended
graphemes; deep task-note matches; scope/archive/completion combinations;
completed and collapsed ancestors below the fold; preserved stored state;
unavailable identities; live Observation; and background query supersession.

The focused suite passed 280 assertions. The integrated `Tools/check.sh` run
passed all 22 suites; the final changes after that run concern native focus
and lazy scroll-target registration. The final Dev build passed, including all
9 storage/identity isolation checks. CI runs the complete regression suite and
release build on the final pull-request revision.

## Measured search cost

Both measurements use optimized Swift 6 on the same machine and 10,000 saved
in-memory SwiftData blocks in one list: 75% tasks, 25% paragraphs, 20% completed,
one third with 400+ character notes, and titles containing accents and a
multi-scalar emoji. Seven runs per query; times below are medians. This measures
retrieval/projection, not native frame rendering or disk-store opening.

| Query | Baseline on main actor at `dc5e9d5` | New background worker | Total available |
| --- | ---: | ---: | ---: |
| `project` | 365.67 ms | 66.99 ms | 10,001 (including list) |
| `needle 9999` | 100.55 ms | 36.50 ms | 1 |
| `absent query` | 94.72 ms | 35.79 ms | 0 |
| `café` | 373.02 ms | 72.74 ms | 10,000 |

The old scan silently returned at most 80 blocks. The new worker returns all
matching IDs/presentation values, with only the visible batches rendered.
Building the immutable observed corpus took 53.18 ms on the main actor. Query
and selection changes do not rebuild that snapshot. A six-query rapid typing
sequence published only its final `needle 9999` result in 40.78 ms. Cancellation
is checked throughout scanning and hit construction; sorting only reads values.
These are synthetic measurements, not a latency guarantee or an external index.

## Native validation

Observed on 2026-09-13 in an isolated Dev review session, using source data
created through the app. Production storage was not used.

- A list with 110 matching tasks reports 110 results, initially renders 80,
  exposes all results through **Load next 30**, and loads the next batch when
  arrow navigation crosses the boundary. Return opens the selected exact task.
- Tab focus, arrow selection, and Return activation agree. Result labels,
  selected state, destination focus, and accessibility focus were inspected.
- A match after 60 paragraphs in a task note scrolls the inspector to the
  ending passage and visibly selects the exact word. Cancelling another search
  restores that native selection. The content includes accents and a
  multi-scalar emoji.
- Excluding completed tasks changes the result count from 110 to 109.
  Activating an included completed result preserves its completion state.
- A paragraph beneath a completed, collapsed task is revealed below the fold
  with its native editor focused. Leaving and revisiting retains the saved
  hidden-completed preference and collapsed branch.
- A retained note on a non-task block opens its matching passage card in the
  owning document. Cold launch, navigation from another page, and repeat
  activation from the bottom of the document all reach the offscreen card at
  a 640-point window width with the sidebar visible. The passage and keyboard
  focus ring are visible; accessibility focus reports “Search result in note”.
- Archived content is included by default and clearly identified. Turning
  inclusion off removes its match; turning it back on restores it. Opening the
  result leaves the list archived, verified in the Lists gallery.
- A hidden list description is exposed and focused even on the same page.
  **Finish** restores its saved hidden state. A 94-character query wraps in the
  reveal notice at 640 points; **Finish** stays visible and clickable.
- Task-title activation opens the correct inspector. Back navigation restores
  the previous reading region. An actual app relaunch retained fixture content
  and saved completion/collapse preferences.

Native review found and resolved mismatched result-button focus/selection,
hidden-summary reveal, and cold lazy note-target scrolling. The latter uses
registered UUID scroll targets before refining the scroll to the mounted note
card; it does not eagerly render the document.

Concurrent native/MCP mutations while the search modal remained open and
spoken VoiceOver traversal were not exercised. Automated saved-store checks
cover live Observation, changed/deleted identities, query supersession, and
scope transitions; these are distinct from the native checks above.
