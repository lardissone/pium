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
}
