import Testing
@testable import Pium

@Suite("Action menu")
@MainActor
struct ActionMenuTests {
    private func stateWithResult(actions: [ResultAction]) -> LauncherState {
        let state = LauncherState()
        state.setResults([
            SearchResult(
                id: "app:Safari",
                kind: .application,
                title: "Safari",
                subtitle: nil,
                iconSource: .systemSymbol("app"),
                searchableTerms: ["Safari"],
                textScore: 1,
                actions: actions
            )
        ])
        return state
    }

    @Test func theMenuStartsClosed() {
        #expect(stateWithResult(actions: []).isActionMenuPresented == false)
    }

    /// There is nothing to show for a result with no actions, so the menu must
    /// not open on an empty list either.
    @Test func theMenuDoesNotOpenWithoutASelectedResult() {
        let state = LauncherState()
        state.presentActionMenu()
        #expect(state.isActionMenuPresented == false)
    }

    @Test func theMenuOpensForASelectedResult() {
        let state = stateWithResult(actions: [ResultAction(id: "open", title: "Open") {}])
        state.presentActionMenu()
        #expect(state.isActionMenuPresented)
    }

    @Test func dismissingClosesTheMenu() {
        let state = stateWithResult(actions: [ResultAction(id: "open", title: "Open") {}])
        state.presentActionMenu()
        state.dismissActionMenu()
        #expect(state.isActionMenuPresented == false)
    }

    /// A new search must not leave a menu hanging over stale results.
    @Test func newResultsCloseTheMenu() {
        let state = stateWithResult(actions: [ResultAction(id: "open", title: "Open") {}])
        state.presentActionMenu()
        state.setResults([])
        #expect(state.isActionMenuPresented == false)
    }

    @Test func preparingForPresentationClosesTheMenu() {
        let state = stateWithResult(actions: [ResultAction(id: "open", title: "Open") {}])
        state.presentActionMenu()
        state.prepareForPresentation()
        #expect(state.isActionMenuPresented == false)
    }
}
