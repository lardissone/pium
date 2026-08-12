# Measuring warm shortcut-to-visible latency

Budget: p95 ≤ 100 ms. Debug builds are not representative — measure Release.

1. Build and launch Release:

   ```bash
   xcodegen generate
   xcodebuild -project Pium.xcodeproj -scheme Pium -configuration Release build
   ```

   Then open the built `Pium.app` from `Build/Products/Release`.

2. Open Instruments and choose the **os_signpost** template. Attach to `Pium`.
3. Record, then press the shortcut 20 times with roughly a second between
   presses. Discard the first press: it is cold, and the budget is for warm.
4. Filter to subsystem `com.lardissone.pium`, category `Launcher`, interval `show`.
5. Read the p95 of the interval durations.
6. Record the number, the machine, and the macOS version in the phase's
   completion notes. A miss is investigated with a time profile before any
   optimisation is written.

# Measuring search latency

Budget: p95 ≤ 50 ms, from query to merged results. `SearchCoordinator.search`
brackets its work with the `query` interval of subsystem `com.lardissone.pium`,
category `Search`, so the Instruments procedure above applies unchanged — swap
the category and interval, and type one- and two-character queries instead of
pressing the shortcut.

The same interval can be measured without a GUI session by driving
`SearchCoordinator` directly in an optimised build against the real index. That
is reproducible and needs nobody at the keyboard, at the cost of excluding the
SwiftUI update that Instruments would also miss.

## Recorded results

Applications, budget p95 ≤ 50 ms:

| Date | Phase | p95 | Median | Samples | Machine | macOS |
|---|---|---:|---:|---:|---|---|
| 2026-08-04 | 2 | 3.8 ms | 2.4 ms | 32 | Apple M2 Max, 32 GB | 26.5.1 |
| 2026-08-04 | 2.1 | 2.7 ms | 2.4 ms | 32 | Apple M2 Max, 32 GB | 26.5.1 |
| 2026-08-04 | 3a | 2.7 ms | 2.4 ms | 32 | Apple M2 Max, 32 GB | 26.5.1 |
| 2026-08-11 | 3b, 4a, 5, 6a | 0.55 ms | 0.46 ms | 32 | Apple M2 Max, 32 GB | 26.5.1 |

Plugins, sharing the applications budget of p95 ≤ 50 ms:

| Date | Phase | p95 | Median | Samples | Machine | macOS |
|---|---|---:|---:|---:|---|---|
| 2026-08-11 | 4a, 6a | 0.69 ms | 0.58 ms | 32 | Apple M2 Max, 32 GB | 26.5.1 |

Files, target p95 ≤ 300 ms, measured to the **first** batch:

| Date | Phase | p95 | Median | Samples | Machine | macOS |
|---|---|---:|---:|---:|---|---|
| 2026-08-04 | 3a | 137.6 ms | 43.2 ms | 20 | Apple M2 Max, 32 GB | 26.5.1 |

Two caveats specific to the file figure. It is measured with the debounce set to
zero, so what a user perceives is this plus `SpotlightFileProvider.defaultDebounce`
— 150 ms at the time of writing. And it depends on what this machine has
indexed and how busy Spotlight is, so it is not a property of Pium alone; treat
a regression as a prompt to investigate rather than as proof of one.

Measured over one- and two-character queries against 284 installed
applications, optimised build, first pass discarded as cold.

## Reproducing the 2026-08-11 figures

`SearchLatencyMeasurementTests` is the headless route this document describes,
written down so the numbers can be taken again the same way. It is skipped
unless asked for:

```bash
PIUM_MEASURE=1 xcodebuild -project Pium.xcodeproj -scheme Pium \
  -destination 'platform=macOS' -configuration Release ENABLE_TESTABILITY=YES \
  test -only-testing:PiumTests/SearchLatencyMeasurementTests
```

`ENABLE_TESTABILITY=YES` is needed because `@testable import` cannot reach a
Release module without it; optimisation is what the measurement is for, and
testability does not change it. The suite asserts nothing about the numbers —
a budget enforced there would fail on whatever else the machine was doing.
Read them and write them into the tables above.

Two caveats on the 2026-08-11 row. It was taken against **76** applications
rather than the 284 of the earlier rows — the same budget, a smaller index, so
it is not evidence of a speed-up. And the plugin figure is measured against a
folder of 50 manifests, which is larger than anyone's real one, so it is an
upper bound rather than a description of a particular machine.

**The shortcut-to-visible p95 is still unrecorded.** It cannot be taken this
way: it needs Instruments attached to a Release build with a person pressing
the shortcut twenty times, per the procedure at the top of this document. That
is what PIUM-51 is still open for.

The same caveat as the launcher figure applies: the interval measures Pium's
own code path, not keystroke-to-pixels.

# Running the tests

Everything, including the UI smoke suite:

```bash
xcodegen generate
xcodebuild test -project Pium.xcodeproj -scheme Pium -destination 'platform=macOS'
```

Unit tests only, which is what CI runs:

```bash
xcodebuild test -project Pium.xcodeproj -scheme Pium \
  -destination 'platform=macOS' -skip-testing:PiumUITests CODE_SIGNING_ALLOWED=NO
```

## Why the UI tests need signing

`PiumUITests` is excluded from CI because XCUITest needs a real GUI session.
Locally it needs consistent code signing, and two failure modes look alarming
but are ordinary configuration problems:

- **`"PiumUITests-Runner.app" is damaged and can't be opened`** — the runner is
  unsigned. Nothing is damaged. Do not pass `CODE_SIGNING_ALLOWED=NO` when
  running the UI tests; that flag is only safe for the unit tests.
- **`mapping process and mapped file (non-platform) have different Team IDs`**,
  surfacing as `Failed to load the test bundle` — the runner and the `.xctest`
  bundle inside it were signed by different teams. This is why `project.yml`
  sets `DEVELOPMENT_TEAM` for every target rather than leaving it unset.

`DEVELOPMENT_TEAM` in `project.yml` is the *development* team, used so local
builds and the test runner agree. Release signing uses the Developer ID team
and is configured separately in Phase 7.

## A note on the unit tests

Running the unit tests briefly registers Pium's real global shortcut, because
the test host is the application itself. That is also why the hotkey tests use
`⌃⌥⇧⌘ F13`/`F14` rather than `⌥ Space` — registering the app's own shortcut a
second time correctly fails with `eventHotKeyExistsErr`, which one test asserts
on purpose.

Pium itself never requires Accessibility permission, and the Phase 0–1
checklist verifies it does not appear in that privacy list.
