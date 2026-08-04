import Testing
@testable import Pium

@Suite("Launcher selection")
@MainActor
struct LauncherStateTests {
    private func results(_ titles: [String]) -> [SearchResult] {
        titles.map {
            SearchResult(
                id: "app:\($0)",
                kind: .application,
                title: $0,
                subtitle: nil,
                iconSource: .systemSymbol("app"),
                searchableTerms: [$0],
                textScore: 1,
                actions: []
            )
        }
    }

    @Test func newResultsSelectTheFirstRow() {
        let state = LauncherState()
        state.setResults(results(["A", "B", "C"]))
        #expect(state.selectedResult?.title == "A")
    }

    @Test func movingDownAndUpWalksTheList() {
        let state = LauncherState()
        state.setResults(results(["A", "B", "C"]))
        state.moveSelection(by: 1)
        #expect(state.selectedResult?.title == "B")
        state.moveSelection(by: -1)
        #expect(state.selectedResult?.title == "A")
    }

    /// Selection stops at the ends rather than wrapping, so holding a key
    /// cannot silently jump the user from the bottom back to the top.
    @Test func selectionClampsAtBothEnds() {
        let state = LauncherState()
        state.setResults(results(["A", "B"]))
        state.moveSelection(by: -1)
        #expect(state.selectedResult?.title == "A")
        state.moveSelection(by: 5)
        #expect(state.selectedResult?.title == "B")
    }

    /// The heart of stable selection: results reorder as providers report in,
    /// and the user's chosen row must not move out from under them.
    @Test func selectionSurvivesAReorderThatKeepsTheSelectedResult() {
        let state = LauncherState()
        state.setResults(results(["A", "B", "C"]))
        state.moveSelection(by: 1)
        #expect(state.selectedResult?.title == "B")

        state.setResults(results(["C", "B", "A"]))
        #expect(state.selectedResult?.title == "B")
    }

    /// When the selected result disappears, fall back rather than leaving
    /// nothing selected.
    @Test func selectionFallsBackWhenTheSelectedResultDisappears() {
        let state = LauncherState()
        state.setResults(results(["A", "B", "C"]))
        state.moveSelection(by: 1)

        state.setResults(results(["A", "C"]))
        #expect(state.selectedResult?.title == "A")
    }

    @Test func clearingResultsClearsSelection() {
        let state = LauncherState()
        state.setResults(results(["A"]))
        state.setResults([])
        #expect(state.selectedResult == nil)
    }

    /// Each opening starts clean, including the result list.
    @Test func preparingForPresentationClearsQueryAndResults() {
        let state = LauncherState()
        state.query = "safari"
        state.setResults(results(["Safari"]))

        state.prepareForPresentation()
        #expect(state.query.isEmpty)
        #expect(state.results.isEmpty)
        #expect(state.selectedResult == nil)
    }
}
