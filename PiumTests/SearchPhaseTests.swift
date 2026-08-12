import Testing
import Foundation
@testable import Pium

@Suite("Search phase")
@MainActor
struct SearchPhaseTests {
    private func state(query: String) -> LauncherState {
        let state = LauncherState()
        state.query = query
        return state
    }

    /// PRD §6.2: an empty query shows nothing at all — not results, not a row
    /// saying there are none.
    @Test func anemptyQueryIsIdleAndSaysNothing() {
        let state = state(query: "")
        #expect(state.searchPhase == .idle)
        #expect(state.showsNoResults == false)
    }

    /// The reason the phase exists rather than reading `results.isEmpty`:
    /// applications answer in single-digit milliseconds while Spotlight is
    /// still working, so a row driven by "empty right now" would flash on the
    /// way to showing results.
    @Test func asearchStillRunningWithNothingYetSaysNothing() {
        let state = state(query: "fire")
        state.beginSearch()
        #expect(state.searchPhase == .searching)
        #expect(state.showsNoResults == false)
    }

    @Test func asettledSearchWithNothingSaysSo() {
        let state = state(query: "zzzz")
        state.beginSearch()
        state.endSearch()
        #expect(state.searchPhase == .settled)
        #expect(state.showsNoResults)
    }

    @Test func asettledSearchWithResultsSaysNothing() {
        let state = state(query: "fire")
        state.beginSearch()
        state.setResults([stubResult("Firefox", kind: .application, score: 0.9)])
        state.endSearch()
        #expect(state.showsNoResults == false)
    }

    /// Typing again after a fruitless search has to take the row down, or it
    /// sits there contradicting the results arriving beneath it.
    @Test func typingAgainTakesTheRowDownUntilTheNextSearchSettles() {
        let state = state(query: "zzzz")
        state.beginSearch()
        state.endSearch()
        #expect(state.showsNoResults)

        state.query = "fire"
        state.beginSearch()
        #expect(state.showsNoResults == false)
    }

    /// Every opening starts clean (PRD §6.2), including this.
    @Test func reopeningReturnsToIdle() {
        let state = state(query: "zzzz")
        state.beginSearch()
        state.endSearch()

        state.prepareForPresentation()

        #expect(state.searchPhase == .idle)
        #expect(state.showsNoResults == false)
    }

    /// Argument mode replaces the global result list with the plugin's own
    /// context (PRD §10.3), so a plugin that takes an argument must not be
    /// told it found nothing while the user is typing that argument.
    @Test func argumentModeNeverSaysThereAreNoResults() {
        let state = state(query: "yt")
        let plugin = SearchResult(
            id: "plugin:youtube",
            kind: .plugin,
            title: "YouTube",
            subtitle: nil,
            iconSource: .systemSymbol("play.rectangle"),
            searchableTerms: ["youtube"],
            textScore: 1,
            actions: [],
            argument: ArgumentRequest(placeholder: nil, isRequired: false)
        )
        state.setResults([plugin])
        state.select(id: plugin.id)
        #expect(state.enterArgumentMode(), "the fixture must actually reach argument mode")

        state.beginSearch()
        state.endSearch()

        #expect(state.showsNoResults == false)
    }
}
