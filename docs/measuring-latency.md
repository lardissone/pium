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

# Running the UI tests

`PiumUITests` is excluded from CI and runs locally only. It needs more than a
plain `xcodebuild` invocation:

- **The runner must be code signed.** `CODE_SIGNING_ALLOWED=NO` — fine for the
  unit tests — produces a runner macOS refuses to launch, reporting
  `"PiumUITests-Runner.app" is damaged and can't be opened`. Nothing is
  damaged; it is unsigned.
- **The runner needs Accessibility permission.** XCUITest drives the UI through
  the accessibility APIs. macOS prompts for this the first time, and a
  headless `xcodebuild` run cannot show the prompt — the runner is killed
  before it connects, reported as
  `Early unexpected exit, operation never finished bootstrapping`.

  This is a requirement of the *test runner*, not of Pium. Pium itself must
  never require Accessibility permission, and the Phase 0–1 checklist verifies
  that it does not appear in that list.

So: **run the UI tests from Xcode** (⌘U with the `PiumUITests` target), accept
the permission prompt once, and afterwards command-line runs work too:

```bash
xcodebuild test -project Pium.xcodeproj -scheme Pium \
  -destination 'platform=macOS' -only-testing:PiumUITests
```

The unit tests have no such requirement:

```bash
xcodebuild test -project Pium.xcodeproj -scheme Pium \
  -destination 'platform=macOS' -skip-testing:PiumUITests CODE_SIGNING_ALLOWED=NO
```

Note that running the unit tests briefly registers Pium's real global shortcut,
because the test host is the application itself.
