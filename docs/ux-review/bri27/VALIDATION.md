# BRI-27 / OL-007 — complete search and exact reveal

## Automated validation

`Tools/run-search-checks.sh` runs production snapshot, projection, query-session,
selection, target-resolution, Navigator and BlockTree code against saved
SwiftData fixtures. It covers more than 80 matches and every keyboard page
boundary; duplicate titles and stable ties; case/accent/width and extended
graphemes; deep task-note matches; scope/archive/completion combinations;
completed and collapsed ancestors below the fold; preserved stored state;
unavailable identities; live Observation; and background query supersession.

The first passing run completed 272 assertions. Final suite/build results and
native observations will be recorded after the final integration checks.

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

## Native checks to complete

- More than 80 matches: count, Load next, arrow-key crossing, Return, result
  button keyboard focus, VoiceOver labels and activation.
- Close with Escape from query and controls; cancel returns the prior native
  editor/caret, while opening a result retains destination focus.
- Exact paragraph below the fold inside collapsed/completed ancestors;
  non-task note-only match; Finish and leaving/revisiting preserve collapse,
  completion and archived status.
- Task title and a match near the end of a long note: inspector scroll,
  native selection visibility and keyboard focus.
- Long query with the reveal notice at the supported narrow window size.
- Rename, reparent, complete, archive and delete while search is open; rapid
  query changes must not expose clickable results from an older request.

No native app control was performed by the implementation agent. The root
delivery task owns native validation and records its observed results here.
