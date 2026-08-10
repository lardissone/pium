import Testing
@testable import Pium

@Suite("Launcher confirmation")
@MainActor
struct LauncherConfirmationTests {
    /// The two-action shape `PluginProvider` actually builds for a plugin: a
    /// `Return`-shortcut "execute" (the run PRD §10.4 is about) and a
    /// `⌘ Return`-shortcut "reveal" (not gated). Lets these tests pick which
    /// one a keypress or a menu click resolved to, the same way `LauncherView`
    /// does before ever calling `attemptToRun`.
    ///
    /// `SearchResult`'s initializer defaults `argument` and `confirmation`, so
    /// every other construction site keeps compiling. Its real parameter list
    /// is `id, kind, title, subtitle, iconSource, searchableTerms, textScore,
    /// actions, argument, confirmation`, in that order.
    private func pluginResult(
        id: String = "demo.deploy",
        confirmation: String?,
        argument: ArgumentRequest? = nil
    ) -> SearchResult {
        SearchResult(
            id: id,
            kind: .plugin,
            title: id,
            subtitle: nil,
            iconSource: .systemSymbol("terminal"),
            searchableTerms: [id],
            textScore: 1,
            actions: [
                ResultAction(id: "execute", title: "Run", shortcut: .returnKey) { _ in },
                ResultAction(id: "reveal", title: "Reveal JSON", shortcut: .commandReturn) { _ in },
            ],
            argument: argument,
            confirmation: confirmation
        )
    }

    /// A launcher showing one plugin, selected — what a search that matched it
    /// leaves behind, and the state every path to a run starts from.
    private func state(confirmation: String?) -> LauncherState {
        let state = LauncherState()
        state.setResults([pluginResult(confirmation: confirmation)])
        return state
    }

    /// The action a plain `Return` resolves to, which is the only one
    /// `attemptToRun` gates.
    private func runAction(of result: SearchResult) -> ResultAction {
        result.actions[0]
    }

    @Test func aplainPluginRunsWithoutAsking() throws {
        let state = state(confirmation: nil)
        let target = try #require(state.selectedResult)
        #expect(state.attemptToRun(runAction(of: target), on: target) == true)
        #expect(state.confirmingResult == nil)
    }

    @Test func adeclaredMessagePutsTheLauncherInConfirmingState() throws {
        let state = state(confirmation: "This deploys to production.")
        let target = try #require(state.selectedResult)
        #expect(state.attemptToRun(runAction(of: target), on: target) == false)
        #expect(state.confirmingResult?.id == "demo.deploy")
    }

    @Test func escapeLeavesConfirmationWithoutRunning() throws {
        let state = state(confirmation: "This deploys to production.")
        let target = try #require(state.selectedResult)
        _ = state.attemptToRun(runAction(of: target), on: target)
        state.cancelConfirmation()
        #expect(state.confirmingResult == nil)
    }

    /// Every time, per PRD §10.4 — neither answering nor dismissing is
    /// remembered, so the run after either one asks again.
    @Test func confirmingIsAskedAgainOnTheNextRun() throws {
        let state = state(confirmation: "This deploys to production.")
        let target = try #require(state.selectedResult)
        let run = runAction(of: target)

        #expect(state.attemptToRun(run, on: target) == false)
        // Answering it runs, and leaves nothing behind that a later run reads.
        #expect(state.attemptToRun(run, on: target) == true)
        #expect(state.confirmingResult == nil)
        #expect(state.attemptToRun(run, on: target) == false)

        state.cancelConfirmation()
        #expect(state.attemptToRun(run, on: target) == false)
    }

    /// PRD §10.3 (argument mode) and §10.4 (confirmation) are independent: a
    /// plugin that takes an argument can also declare `confirmBeforeRun`, and
    /// `selectedResult` is `nil` in argument mode — `enterArgumentMode` empties
    /// `results` — so the run there is attempted on `argumentTarget`, which is
    /// what `LauncherView` hands `attemptToRun` on that path.
    private func argumentModeState(confirmation: String?, isRequired: Bool = true) -> LauncherState {
        let state = LauncherState()
        state.setResults([
            pluginResult(
                confirmation: confirmation,
                argument: ArgumentRequest(placeholder: nil, isRequired: isRequired)
            ),
        ])
        state.enterArgumentMode()
        return state
    }

    @Test func argumentModeAlsoAsksBeforeRunning() throws {
        let state = argumentModeState(confirmation: "This deploys to production.")
        state.setArgumentText("v2")
        let target = try #require(state.argumentTarget)
        #expect(state.attemptToRun(runAction(of: target), on: target) == false)
        #expect(state.confirmingResult?.id == "demo.deploy")
    }

    @Test func argumentModeWithNoDeclaredMessageNeedsNoConfirmation() throws {
        let state = argumentModeState(confirmation: nil)
        state.setArgumentText("v2")
        let target = try #require(state.argumentTarget)
        #expect(state.attemptToRun(runAction(of: target), on: target) == true)
        #expect(state.confirmingResult == nil)
    }

    /// Cancelling answers "are you sure", not "abandon what you typed" — the
    /// argument survives, and the plugin is still in argument mode.
    @Test func cancellingAnArgumentModeConfirmationKeepsTheTypedTextAndTheMode() throws {
        let state = argumentModeState(confirmation: "This deploys to production.")
        state.setArgumentText("v2")
        let target = try #require(state.argumentTarget)
        _ = state.attemptToRun(runAction(of: target), on: target)
        state.cancelConfirmation()
        #expect(state.confirmingResult == nil)
        #expect(state.isInArgumentMode == true)
        #expect(state.argumentText == "v2")
    }

    /// Editing the argument after the message is showing must not be able to
    /// change what a `Return` then runs out from under it.
    @Test func theArgumentCannotBeEditedWhileItsConfirmationIsShowing() throws {
        let state = argumentModeState(confirmation: "This deploys to production.")
        state.setArgumentText("v2")
        let target = try #require(state.argumentTarget)
        _ = state.attemptToRun(runAction(of: target), on: target)
        state.setArgumentText("v2-tampered")
        #expect(state.argumentText == "v2")
    }

    // MARK: - attemptToRun: the gate every path that can start a run shares

    /// A confirmation showing for one result must not be spent answering a run
    /// attempt on a different one — it is replaced by a fresh confirmation for
    /// the new one instead.
    @Test func aConfirmationForOneResultDoesNotAuthorizeARunOnAnother() {
        let state = LauncherState()
        let resultA = pluginResult(id: "demo.a", confirmation: "This deploys A.")
        let resultB = pluginResult(id: "demo.b", confirmation: "This deploys B.")

        #expect(state.attemptToRun(runAction(of: resultA), on: resultA) == false)
        #expect(state.confirmingResult?.id == "demo.a")

        // A's confirmation is still showing when B's run is attempted.
        #expect(state.attemptToRun(runAction(of: resultB), on: resultB) == false)
        #expect(state.confirmingResult?.id == "demo.b")
    }

    /// `select(id:)` on its own must not let a confirmation survive a
    /// changed selection — the mechanism that keeps a double click on a
    /// different row from inheriting an answer given about the first one.
    @Test func selectingADifferentResultClearsAPendingConfirmation() throws {
        let state = LauncherState()
        state.setResults([
            pluginResult(id: "demo.a", confirmation: "This deploys A."),
            pluginResult(id: "demo.b", confirmation: "This deploys B."),
        ])
        let target = try #require(state.selectedResult)
        #expect(state.attemptToRun(runAction(of: target), on: target) == false)
        #expect(state.confirmingResult?.id == "demo.a")

        state.select(id: "demo.b")
        #expect(state.confirmingResult == nil)
    }

    /// Resolving which action a keypress names comes first — `⌘ Return` on a
    /// plugin means Reveal JSON, and must never put the message on screen for
    /// an action that was never going to run it.
    @Test func theRevealActionIsNeverGated() {
        let state = LauncherState()
        let target = pluginResult(confirmation: "This deploys to production.")
        let reveal = target.actions[1]
        #expect(state.attemptToRun(reveal, on: target) == true)
        #expect(state.confirmingResult == nil)
    }

    // MARK: - presentedResults: what the list shows while confirming

    /// While a confirmation is showing, the list must collapse to just the
    /// result it is about — not stay full with the message read alongside
    /// unrelated rows.
    @Test func whileConfirmingOnlyTheConfirmingResultIsPresented() throws {
        let state = LauncherState()
        let resultA = pluginResult(id: "demo.a", confirmation: "This deploys A.")
        let resultB = pluginResult(id: "demo.b", confirmation: nil)
        state.setResults([resultA, resultB])

        #expect(state.attemptToRun(runAction(of: resultA), on: resultA) == false)

        let expectedIDs = ["demo.a"]
        #expect(state.presentedResults.map(\.id) == expectedIDs)
    }

    /// `Esc` — `cancelConfirmation` — restores the list exactly as it was,
    /// because collapsing never touched `results` in the first place.
    @Test func cancellingAConfirmationRestoresThePreviousResults() throws {
        let state = LauncherState()
        let resultA = pluginResult(id: "demo.a", confirmation: "This deploys A.")
        let resultB = pluginResult(id: "demo.b", confirmation: nil)
        state.setResults([resultA, resultB])

        #expect(state.attemptToRun(runAction(of: resultA), on: resultA) == false)
        state.cancelConfirmation()

        let expectedIDs = ["demo.a", "demo.b"]
        #expect(state.presentedResults.map(\.id) == expectedIDs)
    }

    /// A result with nothing to confirm never collapses the list — there is
    /// no confirmation state to enter in the first place.
    @Test func presentedResultsIsTheFullListOutsideConfirmation() {
        let state = LauncherState()
        let resultA = pluginResult(id: "demo.a", confirmation: nil)
        let resultB = pluginResult(id: "demo.b", confirmation: nil)
        state.setResults([resultA, resultB])

        let expectedIDs = ["demo.a", "demo.b"]
        #expect(state.presentedResults.map(\.id) == expectedIDs)
    }
}
