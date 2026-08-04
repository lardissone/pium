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
4. Filter to subsystem `app.pium.Pium`, category `Launcher`, interval `show`.
5. Read the p95 of the interval durations.
6. Record the number, the machine, and the macOS version in the phase's
   completion notes. A miss is investigated with a time profile before any
   optimisation is written.

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
