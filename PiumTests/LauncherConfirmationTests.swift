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
}
