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

    private func safariActions() -> [ResultAction] {
        [
            ResultAction(id: "open", title: "Open", shortcut: .returnKey) {},
            ResultAction(id: "reveal", title: "Reveal in Finder", shortcut: .commandReturn) {},
        ]
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

    /// Every keystroke runs a search, so a batch arriving just after `⌘ K` must
    /// not close the menu the user opened. It only closes when the result it
    /// describes is actually gone.
    @Test func aRefreshThatKeepsTheSelectedResultLeavesTheMenuOpen() {
        let state = stateWithResult(actions: safariActions())
        state.presentActionMenu()

        state.setResults([
            SearchResult(
                id: "app:Safari",
                kind: .application,
                title: "Safari",
                subtitle: nil,
                iconSource: .systemSymbol("app"),
                searchableTerms: ["Safari"],
                textScore: 1,
                actions: safariActions()
            ),
            SearchResult(
                id: "app:1Password for Safari",
                kind: .application,
                title: "1Password for Safari",
                subtitle: nil,
                iconSource: .systemSymbol("app"),
                searchableTerms: ["1Password for Safari"],
                textScore: 0.7,
                actions: safariActions()
            ),
        ])

        #expect(state.isActionMenuPresented)
        #expect(state.highlightedAction?.id == "open")
    }

    @Test func preparingForPresentationClosesTheMenu() {
        let state = stateWithResult(actions: [ResultAction(id: "open", title: "Open") {}])
        state.presentActionMenu()
        state.prepareForPresentation()
        #expect(state.isActionMenuPresented == false)
    }

    /// Opening the menu puts the highlight on the primary action, so `Return`
    /// does the same thing whether or not the menu is open.
    @Test func openingTheMenuHighlightsTheFirstAction() {
        let state = stateWithResult(actions: safariActions())
        state.presentActionMenu()
        #expect(state.highlightedAction?.id == "open")
    }

    @Test func theHighlightWalksTheActionsAndClampsAtBothEnds() {
        let state = stateWithResult(actions: safariActions())
        state.presentActionMenu()

        state.moveActionHighlight(by: 1)
        #expect(state.highlightedAction?.id == "reveal")
        state.moveActionHighlight(by: 5)
        #expect(state.highlightedAction?.id == "reveal")
        state.moveActionHighlight(by: -9)
        #expect(state.highlightedAction?.id == "open")
    }

    @Test func closingTheMenuClearsTheHighlight() {
        let state = stateWithResult(actions: safariActions())
        state.presentActionMenu()
        state.dismissActionMenu()
        #expect(state.highlightedAction == nil)
    }

    /// The whole point of data-driven routing: the view asks which action a
    /// combination runs instead of branching on the key itself.
    @Test func aCombinationFindsItsAction() {
        let state = stateWithResult(actions: safariActions())
        #expect(state.action(matching: .return, modifiers: [])?.id == "open")
        #expect(state.action(matching: .return, modifiers: [.command])?.id == "reveal")
    }

    @Test func anUnboundCombinationFindsNothing() {
        let state = stateWithResult(actions: safariActions())
        #expect(state.action(matching: .character("j"), modifiers: [.command]) == nil)
    }

    /// With no selection there is nothing to run, and a stray `Return` must not
    /// reach into a stale result.
    @Test func noSelectionMeansNoActionForAnyCombination() {
        let state = LauncherState()
        #expect(state.action(matching: .return, modifiers: []) == nil)
    }
}
