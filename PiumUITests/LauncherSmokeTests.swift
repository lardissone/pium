import XCTest

/// Smoke coverage for the native shell.
///
/// These run locally only: XCUITest needs a real GUI session, and Pium
/// additionally needs a registered global hotkey and a floating panel. CI skips
/// this target on purpose.
/// Main-actor isolated because every XCUITest API is. Without this the whole
/// suite compiles with "call to main actor-isolated instance method in a
/// synchronous nonisolated context", and a wall of known-harmless warnings is
/// how a real one gets missed.
@MainActor
final class LauncherSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    // The `async throws` overrides rather than the plain ones: those are
    // nonisolated on `XCTestCase`, so annotating the class does not reach them
    // and every line here would warn about touching main-actor state.
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            // Lands in NSArgumentDomain, so onboarding does not block the tests.
            "-pium.hasCompletedOnboarding", "YES",
            // The menu titles below are English. Without this the suite fails
            // whenever the developer has left Pium set to another language.
            "-AppleLanguages", "(en)",
        ]
        app.launch()
    }

    override func tearDown() async throws {
        app.terminate()
    }

    func testMenubarItemExists() {
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
    }

    func testOpenPiumFromMenubarShowsAFocusedEmptySearchField() {
        openLauncherFromMenubar()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        XCTAssertEqual(searchField.value as? String, "")
        XCTAssertTrue(searchField.hasKeyboardFocus)
    }

    func testEscapeDismissesTheLauncher() {
        openLauncherFromMenubar()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))

        searchField.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(searchField.waitForNonExistence(timeout: 10))
    }

    /// The panel is hidden with `orderOut` rather than destroyed, so the SwiftUI
    /// view stays mounted between openings. Without an explicit per-opening
    /// reset, only the first opening is cleared and focused — and an unfocused
    /// field never receives the Escape key either.
    func testSecondOpeningIsAlsoEmptyAndFocused() {
        openLauncherFromMenubar()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText("leftover")
        XCTAssertEqual(searchField.value as? String, "leftover")

        searchField.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(searchField.waitForNonExistence(timeout: 10))

        openLauncherFromMenubar()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        XCTAssertEqual(
            searchField.value as? String, "",
            "Every opening must start with an empty query"
        )
        XCTAssertTrue(
            searchField.hasKeyboardFocus,
            "Every opening must start with the input focused"
        )
    }

    func testTypingFindsAnApplication() {
        openLauncherFromMenubar()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText("safari")

        // Safari ships with macOS, so it is a safe target on any machine.
        XCTAssertTrue(
            app.staticTexts["Safari"].waitForExistence(timeout: 10),
            "Typing a known application name must show it in the results"
        )
    }

    func testArrowKeysMoveTheSelection() {
        openLauncherFromMenubar()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText("a")

        let before = selectedRowTitle()
        XCTAssertNotNil(before, "A result must be selected before the arrows can move it")
        searchField.typeKey(.downArrow, modifierFlags: [])
        XCTAssertNotEqual(
            before,
            waitForChange(from: before, reading: selectedRowTitle),
            "Down must move the selection"
        )
    }

    func testFooterShowsThePrimaryAction() {
        openLauncherFromMenubar()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText("safari")

        XCTAssertTrue(
            app.staticTexts["Open"].waitForExistence(timeout: 10),
            "The footer must name the primary action of the selected result"
        )
        // The Actions affordance is a button, so it is not among the static texts.
        XCTAssertTrue(app.buttons["Actions"].exists)
    }

    func testCommandKOpensTheActionMenuAndArrowsMoveIt() {
        openLauncherFromMenubar()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText("safari")
        XCTAssertTrue(app.staticTexts["Safari"].waitForExistence(timeout: 10))

        searchField.typeKey("k", modifierFlags: .command)

        let menuRows = app.descendants(matching: .any).matching(identifier: "action.row")
        XCTAssertTrue(menuRows.firstMatch.waitForExistence(timeout: 10), "⌘K must open the menu")

        let before = highlightedActionTitle()
        searchField.typeKey(.downArrow, modifierFlags: [])
        XCTAssertNotEqual(
            before,
            waitForChange(from: before, reading: highlightedActionTitle),
            "Down must move the highlight"
        )

        // The first Esc closes the menu and returns to search.
        searchField.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(menuRows.firstMatch.waitForNonExistence(timeout: 10))
        XCTAssertTrue(searchField.exists, "The launcher must still be open")
    }

    /// Files come from the live Spotlight index, so the test creates one and
    /// waits for it to be indexed rather than assuming any particular file
    /// exists on the machine.
    func testTypingFindsAFile() throws {
        let name = "pium-uitest-\(UUID().uuidString.prefix(8))"
        // Deliberately not `~/Documents`: macOS privacy controls hide that
        // folder's contents from Spotlight results unless the app has been
        // granted access, and an XCUITest-launched app has not. See PIUM-41.
        //
        // `realHome` rather than `NSHomeDirectory()`: this runner is sandboxed,
        // so the latter would write into its container, where Pium — which is
        // not sandboxed — would never see the file. See PIUM-62.
        let folder = realHome.appending(path: "pium-uitest-scratch")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).txt")
        try "pium ui test".write(to: url, atomically: true, encoding: .utf8)
        // Not `defer`: a failed assertion unwinds through an Objective-C
        // exception, which skips it and leaves the scratch folder behind.
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }

        openLauncherFromMenubar()
        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText(name)

        // A file row combines its title and its location into one accessibility
        // element, so it is matched by containment rather than by an exact
        // title.
        let row = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND value CONTAINS %@",
                "result.row", "\(name).txt"
            )
        ).firstMatch

        // Spotlight can take tens of seconds to index a file that was just
        // written, and the launcher only queries when the query changes —
        // waiting alone would never surface it. Nudging the field re-issues the
        // search, which is also what a real user would do.
        let lastCharacter = String(name.suffix(1))
        for _ in 0..<20 where !row.exists {
            searchField.typeKey(.delete, modifierFlags: [])
            searchField.typeText(lastCharacter)
            _ = row.waitForExistence(timeout: 2)
        }

        XCTAssertTrue(
            row.exists,
            "A file in the home folder must appear in the results once indexed"
        )
    }

    /// The phase in one test: a JSON file written to the plugins folder becomes
    /// a searchable row without restarting Pium.
    func testAPluginPresentAtLaunchIsSearchable() throws {
        let name = "pium-uitest-\(UUID().uuidString.prefix(8))".lowercased()
        try writePluginManifest(named: name)

        // Written before the app reads the folder, which it does at launch.
        // Separate from the live-reload test so a failure here is about
        // searching plugins and a failure only there is about the watcher.
        app.terminate()
        app.launch()

        openLauncherFromMenubar()
        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText(name)

        XCTAssertTrue(
            pluginRow(named: name).waitForExistence(timeout: 10),
            "A plugin on disk at launch must be searchable. \(resultListDiagnostics())"
        )
    }

    func testAPluginAppearsWithoutRestarting() throws {
        let name = "pium-uitest-\(UUID().uuidString.prefix(8))".lowercased()
        // Written while Pium is already running: the folder watcher's job,
        // not the launch-time load the test above covers.
        try writePluginManifest(named: name)

        openLauncherFromMenubar()
        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText(name)

        XCTAssertTrue(
            pluginRow(named: name).waitForExistence(timeout: 10),
            "A plugin written to the folder must appear without restarting. "
                + resultListDiagnostics()
        )
    }

    /// This task is where the app first builds a provider that knows about
    /// state, so this is where a disabled plugin can first be proven to leave
    /// the result list. The switch lives in Settings, which XCUITest cannot
    /// reach here, so the preference is written through the argument domain —
    /// what is under test is that search honours it.
    func testAdisabledPluginIsNotOffered() throws {
        let name = "pium-uitest-\(UUID().uuidString.prefix(8))".lowercased()
        try writePluginManifest(named: name)

        app.terminate()
        app.launchArguments += [
            "-pium.disabledPluginIDs", "(uitest.\(name))",
        ]
        app.launch()

        openLauncherFromMenubar()
        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText(name)

        XCTAssertFalse(
            pluginRow(named: name).waitForExistence(timeout: 5),
            "A disabled plugin must not appear in the results. \(resultListDiagnostics())"
        )
    }

    /// The real home, not the container the test runner reports.
    ///
    /// `PiumUITests-Runner` is sandboxed, so `NSHomeDirectory()` here is
    /// `~/Library/Containers/app.pium.PiumUITests.xctrunner/Data`. Pium is not
    /// sandboxed and reads the real home, so anything a test writes to the
    /// runner's home is something the app can never see. `getpwuid` reports the
    /// account's own directory and is not redirected. See PIUM-62.
    private var realHome: URL {
        guard let entry = getpwuid(getuid()) else { return URL(filePath: NSHomeDirectory()) }
        return URL(filePath: String(cString: entry.pointee.pw_dir))
    }

    /// Escapes a string for embedding in a JSON string literal assembled by
    /// hand, as the fixtures below do. A real home path is not guaranteed to
    /// be free of quotes or backslashes, and one that has either would
    /// otherwise write a manifest that fails to parse.
    private func jsonEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Writes a manifest into the user's real plugins folder and removes it
    /// afterwards.
    ///
    /// Cleaned up with `addTeardownBlock` rather than `defer`: a failed
    /// assertion unwinds through an Objective-C exception, which skips Swift's
    /// `defer` and leaves the fixture behind. A leaked manifest is a plugin in
    /// the user's own launcher that then outranks everything in later tests.
    /// Argument mode end to end, which the state tests cannot reach: entering
    /// swaps the search field for a focusable view of its own, and leaving has
    /// to hand the focus back or every keystroke afterwards is a beep.
    func testArgumentModeTakesTypingAndGivesTheFieldBack() throws {
        let name = "pium-uitest-\(UUID().uuidString.prefix(8))".lowercased()
        try writePluginManifest(named: name, inputMode: "required")

        openLauncherFromMenubar()
        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText(name)
        XCTAssertTrue(pluginRow(named: name).waitForExistence(timeout: 10))

        // Space on a plugin that takes input enters argument mode.
        searchField.typeText(" ")
        let pill = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", name)
        ).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "A pill must name the plugin")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "result.row").count, 0,
            "Applications and files must disappear while an argument is typed"
        )

        // Backspace to empty, then once more to leave.
        app.typeText("swift")
        for _ in 0..<"swift".count { app.typeKey(.delete, modifierFlags: []) }
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(pill.waitForNonExistence(timeout: 10), "Backspace on empty must leave")

        // The field has to be usable again, which is what the beep meant it
        // was not.
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText("z")
        XCTAssertEqual(
            searchField.value as? String, "\(name)z",
            "Typing must reach the search field again after leaving argument mode"
        )
    }

    /// Return runs the command. The plugin writes a file, because a UI test
    /// cannot see a process but can see what it left behind.
    func testReturnRunsThePlugin() throws {
        let name = "pium-uitest-\(UUID().uuidString.prefix(8))".lowercased()
        let marker = realHome.appending(path: ".config/pium/plugins/\(name).ran")
        addTeardownBlock { try? FileManager.default.removeItem(at: marker) }

        let folder = realHome.appending(path: ".config/pium/plugins")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).pium.json")
        try """
        { "schemaVersion": 1, "id": "uitest.\(name)", "name": "\(name)",
          "input": { "mode": "none" },
          "command": { "executable": "touch", "arguments": ["\(jsonEscaped(marker.path))"] } }
        """.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        app.terminate()
        app.launch()

        openLauncherFromMenubar()
        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText(name)
        XCTAssertTrue(pluginRow(named: name).waitForExistence(timeout: 10))
        searchField.typeKey(.return, modifierFlags: [])

        var ran = false
        for _ in 0..<50 where !ran {
            usleep(200_000)
            ran = FileManager.default.fileExists(atPath: marker.path)
        }
        XCTAssertTrue(ran, "Return on a plugin row must run its command")
    }

    /// What the user typed in argument mode must reach the command as exactly
    /// one `argv` element. The plugin creates a directory named after it,
    /// because a UI test cannot see a process but can see the filesystem — and
    /// a directory whose name holds a space can only come from a command that
    /// received that name whole.
    ///
    /// `mkdir` from the controlled search path rather than a script of the
    /// plugin's own: files this runner creates carry `com.apple.quarantine`
    /// because it is sandboxed, and the kernel refuses to execute a quarantined
    /// script with `EPERM`. That refusal is about who wrote the fixture, not
    /// about the launcher, so a fixture that cannot hit it says more.
    ///
    /// The command runs in the scratch folder, so an argument that ever does
    /// split leaves its second half there — cleaned up with everything else —
    /// rather than in the user's own plugins folder.
    func testArgumentModeRunsThePluginWithWhatWasTyped() throws {
        let name = "pium-uitest-\(UUID().uuidString.prefix(8))".lowercased()
        let scratch = realHome.appending(path: "pium-uitest-scratch-\(name)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }

        let folder = realHome.appending(path: ".config/pium/plugins")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).pium.json")
        try """
        { "schemaVersion": 1, "id": "uitest.\(name)", "name": "\(name)",
          "input": { "mode": "required", "placeholder": "Text" },
          "command": { "executable": "mkdir",
                       "arguments": ["-p", "\(jsonEscaped(scratch.path))/{{input}}"],
                       "workingDirectory": "\(jsonEscaped(scratch.path))" } }
        """.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        app.terminate()
        app.launch()

        openLauncherFromMenubar()
        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText(name)
        XCTAssertTrue(pluginRow(named: name).waitForExistence(timeout: 10))

        // Space enters argument mode on a plugin that takes input.
        searchField.typeText(" ")
        app.typeText("hola mundo")
        app.typeKey(.return, modifierFlags: [])

        let typed = scratch.appending(path: "hola mundo")
        var created = false
        for _ in 0..<50 where !created {
            usleep(200_000)
            created = FileManager.default.fileExists(atPath: typed.path)
        }
        XCTAssertTrue(
            created,
            "The typed argument must reach the command as one argument"
        )
        // Two arguments would have made `hola` here and `mundo` beside it, so
        // the absence of the first is what tells one element from two.
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: scratch.appending(path: "hola").path),
            "The typed argument must not be split on its space"
        )
    }

    /// PRD §10.3: a required argument that is empty must not execute. The
    /// plugin would leave a marker file if it ran, so the test can tell "did
    /// not run" from "ran, but the marker has not landed yet."
    func testEmptyRequiredArgumentDoesNotRunThePlugin() throws {
        let name = "pium-uitest-\(UUID().uuidString.prefix(8))".lowercased()
        let marker = realHome.appending(path: ".config/pium/plugins/\(name).ran")
        addTeardownBlock { try? FileManager.default.removeItem(at: marker) }

        let folder = realHome.appending(path: ".config/pium/plugins")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).pium.json")
        try """
        { "schemaVersion": 1, "id": "uitest.\(name)", "name": "\(name)",
          "input": { "mode": "required", "placeholder": "Text" },
          "command": { "executable": "touch", "arguments": ["\(jsonEscaped(marker.path))"] } }
        """.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        app.terminate()
        app.launch()

        openLauncherFromMenubar()
        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText(name)
        XCTAssertTrue(pluginRow(named: name).waitForExistence(timeout: 10))

        // Space enters argument mode; Return follows with nothing typed.
        searchField.typeText(" ")
        let pill = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", name)
        ).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "A pill must name the plugin")
        app.typeKey(.return, modifierFlags: [])

        // A short, bounded wait rather than the 10 seconds the other plugin
        // tests use: this test expects nothing to happen, so it should fail
        // fast rather than sit out a timeout that was sized for the opposite
        // case.
        var ran = false
        for _ in 0..<10 where !ran {
            usleep(200_000)
            ran = FileManager.default.fileExists(atPath: marker.path)
        }
        XCTAssertFalse(ran, "An empty required argument must not run the plugin, but it did")
    }

    /// A HUD outlives the launcher that started it.
    func testAToastHudSurvivesDismissingTheLauncher() throws {
        let name = "pium-uitest-\(UUID().uuidString.prefix(8))".lowercased()
        let folder = realHome.appending(path: ".config/pium/plugins")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).pium.json")
        try """
        { "schemaVersion": 1, "id": "uitest.\(name)", "name": "\(name)",
          "input": { "mode": "none" },
          "command": { "executable": "echo", "arguments": ["hola desde el plugin"] },
          "output": { "mode": "toast" } }
        """.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        app.terminate()
        app.launch()

        openLauncherFromMenubar()
        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText(name)
        XCTAssertTrue(pluginRow(named: name).waitForExistence(timeout: 10))
        searchField.typeKey(.return, modifierFlags: [])

        let hud = app.staticTexts["hola desde el plugin"]
        XCTAssertTrue(hud.waitForExistence(timeout: 10), "A toast plugin must show a HUD")
        // Running an action already dismissed the launcher; the HUD must remain.
        XCTAssertTrue(hud.exists, "The HUD must outlive the launcher that started it")
    }

    @discardableResult
    private func writePluginManifest(named name: String, inputMode: String = "none") throws -> URL {
        let folder = realHome.appending(path: ".config/pium/plugins")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(name).pium.json")
        try """
        { "schemaVersion": 1, "id": "uitest.\(name)", "name": "\(name)",
          "input": { "mode": "\(inputMode)" },
          "command": { "executable": "true" } }
        """.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A plugin row with no description combines into a single accessibility
    /// element whose text can land in either `label` or `value`, so both are
    /// accepted rather than guessed at.
    private func pluginRow(named name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND (value CONTAINS %@ OR label CONTAINS %@)",
                "result.row", name, name
            )
        ).firstMatch
    }

    /// What the list actually held, so one failing run says why rather than
    /// only that it failed.
    private func resultListDiagnostics() -> String {
        let rows = app.descendants(matching: .any).matching(identifier: "result.row")
        let described = (0..<rows.count).map { index in
            let row = rows.element(boundBy: index)
            return "[label: \(row.label), value: \(String(describing: row.value))]"
        }
        return "Rows present: \(rows.count) \(described.joined(separator: " "))"
    }

    /// Typing and backspace inside the menu must never reach the search query
    /// behind it. Both bugs shipped once: typing appended to the query, and
    /// later `Delete` fell through to the field and ate it a character at a
    /// time.
    func testTypingAndBackspaceInTheMenuLeaveTheSearchAlone() {
        openLauncherFromMenubar()

        let searchField = app.textFields["Search"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.typeText("safari")
        XCTAssertTrue(app.staticTexts["Safari"].waitForExistence(timeout: 10))

        searchField.typeKey("k", modifierFlags: .command)
        let menuRows = app.descendants(matching: .any).matching(identifier: "action.row")
        XCTAssertTrue(menuRows.firstMatch.waitForExistence(timeout: 10), "⌘K must open the menu")
        XCTAssertEqual(
            waitUntil({ menuRows.count }, satisfies: { $0 == 2 }), 2,
            "Safari has an Open and a Reveal in Finder action"
        )

        searchField.typeText("reveal")
        XCTAssertEqual(
            waitUntil({ menuRows.count }, satisfies: { $0 == 1 }), 1,
            "Typing must narrow the menu to the matching action"
        )
        XCTAssertEqual(
            searchField.value as? String, "safari",
            "Typing into the menu must not reach the search query"
        )

        for _ in 0..<"reveal".count {
            searchField.typeKey(.delete, modifierFlags: [])
        }
        XCTAssertEqual(
            waitUntil({ menuRows.count }, satisfies: { $0 == 2 }), 2,
            "Backspace must restore the filtered-out actions"
        )
        XCTAssertEqual(
            searchField.value as? String, "safari",
            "Backspace in the menu must not delete from the search query"
        )
    }

    private func highlightedActionTitle() -> String? {
        selectedTitle(ofRowsIdentified: "action.row")
    }

    private func selectedRowTitle() -> String? {
        selectedTitle(ofRowsIdentified: "result.row")
    }

    /// The title of the selected row, once one exists.
    ///
    /// Waits rather than reading straight away: results arrive from an async
    /// search, and reading `value` off a query with no matches raises "failed
    /// to get matching snapshot" instead of returning nil. A combined row
    /// exposes its title as the element's value, not its label.
    private func selectedTitle(ofRowsIdentified identifier: String) -> String? {
        let selectedRow = app.descendants(matching: .any)
            .matching(identifier: identifier)
            .matching(NSPredicate(format: "selected == true"))
            .firstMatch
        guard selectedRow.waitForExistence(timeout: 10) else { return nil }
        return selectedRow.value as? String
    }

    private func waitForChange(
        from previous: String?,
        reading read: () -> String?
    ) -> String? {
        waitUntil(read, satisfies: { $0 != previous })
    }

    /// Polls until the reading satisfies the condition, so a keystroke that has
    /// not been rendered yet does not read as a keystroke that did nothing.
    private func waitUntil<T>(
        _ read: () -> T,
        satisfies isSatisfied: (T) -> Bool,
        timeout: TimeInterval = 5
    ) -> T {
        let deadline = Date().addingTimeInterval(timeout)
        var current = read()
        while !isSatisfied(current), Date() < deadline {
            usleep(100_000)
            current = read()
        }
        return current
    }

    private var statusItem: XCUIElement {
        app.menuBars.statusItems.firstMatch
    }

    private func openLauncherFromMenubar() {
        XCTAssertTrue(statusItem.waitForExistence(timeout: 10))
        statusItem.click()
        let openItem = app.menuItems["Open Pium"]
        XCTAssertTrue(openItem.waitForExistence(timeout: 10))
        openItem.click()
    }
}

private extension XCUIElement {
    var hasKeyboardFocus: Bool {
        (value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }
}
