# tt

tt is a local-first, macOS-only time tracker with a brutalist, text-first ui.

co-evolved using ai.

* * *

## build + run

- open `tt.xcodeproj` in Xcode
- select the `tt` scheme and run on macOS 13+
- tt lives in the menu bar, with no Dock icon or main window at launch

## tracking

click the menu bar `tt` to open the popover. select a project, start or stop the
timer, check today's and the last seven days' totals, or open the main window.
use the popover's `quit` button to exit; closing the main window keeps tt running.

the main window shows the timer, entries, projects, reports and csv export.
stopping a timer there asks for confirmation. when stopped, the header's idle
indicator shows time since the most recently ended entry.

## entries + projects

- browse entries with `←` and `→`, or click the day heading to return to today
- click `edit` on an entry, or press `e` for the running entry
- edit start, end, duration, project or note, then save; save applies typed fields
  even without pressing Enter
- start and end accept `HH:MM`; duration accepts `HH:MM` or `HH:MM:SS`
- an end before the start falls on the next calendar day; durations are elapsed
  time, including daylight-saving changes
- changing start keeps duration; changing end or duration keeps start
- editing a running entry keeps it running
- delete an entry from inside its editor; deletion is immediate
- add projects through a picker or the projects section; names are trimmed and
  stored in lowercase
- archiving hides a project from pickers while retaining its entries and name;
  there is no restore action

errors appear above the timer in the main window. failed reads retain the last
loaded entries and totals.

## keyboard

shortcuts apply in the main window. while typing in a text field, only `esc` is
handled by tt.

| key | action |
| --- | --- |
| `space` | start the timer, or ask to stop it |
| `n` | pick a project and start a timer, when stopped |
| `p` | open the project picker |
| `e` | edit the running entry |
| `t` | return to today |
| `←` / `→` | previous / next day, never beyond today |
| `esc` | cancel the active editor, picker or confirmation |

## reports + export

day totals count only the part of an entry within that calendar day, including
entries that span midnight. `last 7d` means today and the previous six calendar
days. the chart shows those daily totals and highlights today in orange.
project totals in pickers and the projects section are all-time totals.

choose inclusive `from` and `to` dates, then `export`. csv includes entries that
overlap the selected days, with their full timestamps and durations rather than
clipped values. archived projects keep their names in exports.

csv columns are `project,start,end,duration_seconds,note`. timestamps use ISO 8601
in UTC. a running entry has an empty end and its duration is measured at export.

## data

the SQLite database is stored at
`~/Library/Application Support/tt/tt.sqlite`. tracking data stays on this Mac;
there is no account or sync service.

## ui

- dark background, gray text and dividers, orange accents and red destructive actions
- bundled JetBrains Mono, compact spacing and text controls
- square editor surfaces and hard dividers; the menu bar popover has rounded corners

## architecture

- domain: models, elapsed-time math, calendar boundaries, reports, csv and entry editing
- persistence: GRDB repositories and migrations over one SQLite database
- state: `TimeTracker` owns observable tracking state and repositories;
  `AppState` observes it and handles timers and error presentation
- ui: SwiftUI views, with tested keyboard mapping and week-chart calculations
- shell: AppKit status item, popover panel, main window and app lifecycle

## checks

with Xcode selected for command-line builds:

```sh
xcodebuild -scheme tt -destination 'platform=macOS' \
  -enableCodeCoverage YES -resultBundlePath TestResults.xcresult test
python3 -m unittest discover -s scripts -p 'test_*.py'
xcrun xccov view --report --json TestResults.xcresult > coverage.json
python3 scripts/check_coverage.py coverage.json
```

use a fresh result bundle path for each run. tests use isolated databases and the
production migrations. coverage must reach 80% in each named application-logic
file, including the state layer, keyboard mapping and chart calculations.
