import Testing
@testable import Pium

@Suite("Launcher confirmation")
@MainActor
struct LauncherConfirmationTests {
    private func state(confirmation: String?) -> LauncherState {
        let state = LauncherState()
        // `SearchResult`'s initializer defaults `argument` and, after this
        // task, `confirmation` — so every existing construction site keeps
        // compiling. Check its real parameter list before writing this: it is
        // `id, kind, title, subtitle, iconSource, searchableTerms, textScore,
        // actions, argument`, in that order.
        state.setResults([
            SearchResult(
                id: "demo.deploy",
                kind: .plugin,
                title: "Deploy",
                subtitle: nil,
                iconSource: .systemSymbol("terminal"),
                searchableTerms: ["deploy"],
                textScore: 1,
                actions: [],
                confirmation: confirmation
            ),
        ])
        return state
    }

    @Test func aplainPluginNeedsNoConfirmation() {
        #expect(state(confirmation: nil).beginConfirmation() == false)
    }

    @Test func adeclaredMessagePutsTheLauncherInConfirmingState() {
        let state = state(confirmation: "This deploys to production.")
        #expect(state.beginConfirmation() == true)
        #expect(state.confirmingResult?.id == "demo.deploy")
    }

    @Test func escapeLeavesConfirmationWithoutRunning() {
        let state = state(confirmation: "This deploys to production.")
        _ = state.beginConfirmation()
        state.cancelConfirmation()
        #expect(state.confirmingResult == nil)
    }

    /// Every time, per PRD §10.4 — confirming once does not remember.
    @Test func confirmingIsAskedAgainOnTheNextRun() {
        let state = state(confirmation: "This deploys to production.")
        _ = state.beginConfirmation()
        state.cancelConfirmation()
        #expect(state.beginConfirmation() == true)
    }

    /// PRD §10.3 (argument mode) and §10.4 (confirmation) are independent: a
    /// plugin that takes an argument can also declare `confirmBeforeRun`, and
    /// `selectedResult` is `nil` in argument mode — `enterArgumentMode` empties
    /// `results` — so confirmation there has to come from `argumentTarget`.
    private func argumentModeState(confirmation: String?, isRequired: Bool = true) -> LauncherState {
        let state = LauncherState()
        state.setResults([
            SearchResult(
                id: "demo.deploy",
                kind: .plugin,
                title: "Deploy",
                subtitle: nil,
                iconSource: .systemSymbol("terminal"),
                searchableTerms: ["deploy"],
                textScore: 1,
                actions: [],
                argument: ArgumentRequest(placeholder: nil, isRequired: isRequired),
                confirmation: confirmation
            ),
        ])
        state.enterArgumentMode()
        return state
    }

    @Test func argumentModeAlsoAsksBeforeRunning() {
        let state = argumentModeState(confirmation: "This deploys to production.")
        state.setArgumentText("v2")
        #expect(state.beginConfirmation() == true)
        #expect(state.confirmingResult?.id == "demo.deploy")
    }

    @Test func argumentModeWithNoDeclaredMessageNeedsNoConfirmation() {
        let state = argumentModeState(confirmation: nil)
        state.setArgumentText("v2")
        #expect(state.beginConfirmation() == false)
    }

    /// Cancelling answers "are you sure", not "abandon what you typed" — the
    /// argument survives, and the plugin is still in argument mode.
    @Test func cancellingAnArgumentModeConfirmationKeepsTheTypedTextAndTheMode() {
        let state = argumentModeState(confirmation: "This deploys to production.")
        state.setArgumentText("v2")
        _ = state.beginConfirmation()
        state.cancelConfirmation()
        #expect(state.confirmingResult == nil)
        #expect(state.isInArgumentMode == true)
        #expect(state.argumentText == "v2")
    }

    /// Editing the argument after the message is showing must not be able to
    /// change what a `Return` then runs out from under it.
    @Test func theArgumentCannotBeEditedWhileItsConfirmationIsShowing() {
        let state = argumentModeState(confirmation: "This deploys to production.")
        state.setArgumentText("v2")
        _ = state.beginConfirmation()
        state.setArgumentText("v2-tampered")
        #expect(state.argumentText == "v2")
    }

    // MARK: - attemptToRun: the gate every path that can start a run shares

    /// The two-action shape `PluginProvider` actually builds for a plugin: a
    /// `Return`-shortcut "execute" (the run PRD §10.4 is about) and a
    /// `⌘ Return`-shortcut "reveal" (not gated). Lets the tests below pick
    /// which one a keypress or a menu click resolved to, the same way
    /// `LauncherView` does before ever calling `attemptToRun`.
    private func pluginResult(id: String, confirmation: String?) -> SearchResult {
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
            confirmation: confirmation
        )
    }

    /// Finding 1: the run action asks before it runs, whichever path reached
    /// it — including the action menu's Execute row, which is the run PRD
    /// §10.4 is about and previously called `perform` directly with no gate
    /// at all.
    @Test func theRunActionAsksBeforeRunningThroughAttemptToRun() {
        let state = LauncherState()
        let target = pluginResult(id: "demo.deploy", confirmation: "This deploys to production.")
        let execute = target.actions[0]
        #expect(state.attemptToRun(execute, on: target) == false)
        #expect(state.confirmingResult?.id == "demo.deploy")
    }

    /// Finding 2: a confirmation showing for one result must not be spent
    /// answering a run attempt on a different one — it is replaced by a
    /// fresh confirmation for the new one instead.
    @Test func aConfirmationForOneResultDoesNotAuthorizeARunOnAnother() {
        let state = LauncherState()
        let resultA = pluginResult(id: "demo.a", confirmation: "This deploys A.")
        let resultB = pluginResult(id: "demo.b", confirmation: "This deploys B.")
        let executeA = resultA.actions[0]
        let executeB = resultB.actions[0]

        #expect(state.attemptToRun(executeA, on: resultA) == false)
        #expect(state.confirmingResult?.id == "demo.a")

        // A's confirmation is still showing when B's run is attempted.
        #expect(state.attemptToRun(executeB, on: resultB) == false)
        #expect(state.confirmingResult?.id == "demo.b")
    }

    /// `select(id:)` on its own must not let a confirmation survive a
    /// changed selection — the mechanism that keeps a double click on a
    /// different row from inheriting an answer given about the first one.
    @Test func selectingADifferentResultClearsAPendingConfirmation() {
        let state = LauncherState()
        state.setResults([
            pluginResult(id: "demo.a", confirmation: "This deploys A."),
            pluginResult(id: "demo.b", confirmation: "This deploys B."),
        ])
        #expect(state.beginConfirmation() == true)
        #expect(state.confirmingResult?.id == "demo.a")

        state.select(id: "demo.b")
        #expect(state.confirmingResult == nil)
    }

    /// Finding 3: resolving which action a keypress names comes first —
    /// `⌘ Return` on a plugin means Reveal JSON, and must never put the
    /// message on screen for an action that was never going to run it.
    @Test func theRevealActionIsNeverGated() {
        let state = LauncherState()
        let target = pluginResult(id: "demo.deploy", confirmation: "This deploys to production.")
        let reveal = target.actions[1]
        #expect(state.attemptToRun(reveal, on: target) == true)
        #expect(state.confirmingResult == nil)
    }
}
