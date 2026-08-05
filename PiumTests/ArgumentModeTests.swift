import Testing
import Foundation
@testable import Pium

@Suite("Argument mode")
@MainActor
struct ArgumentModeTests {
    private func result(
        _ title: String,
        kind: ResultKind = .plugin,
        argument: ArgumentRequest? = ArgumentRequest(placeholder: nil, isRequired: false)
    ) -> SearchResult {
        SearchResult(
            id: "\(kind.rawValue):\(title)",
            kind: kind,
            title: title,
            subtitle: nil,
            iconSource: .systemSymbol("terminal"),
            searchableTerms: [title],
            textScore: 1,
            actions: [],
            argument: argument
        )
    }

    private func state(_ results: [SearchResult]) -> LauncherState {
        let state = LauncherState()
        state.setResults(results)
        return state
    }

    @Test func anewStateIsNotInArgumentMode() {
        #expect(!LauncherState().isInArgumentMode)
    }

    @Test func enteringRequiresAselectedResultThatTakesAnArgument() {
        let state = state([result("YouTube")])
        #expect(state.enterArgumentMode())
        #expect(state.isInArgumentMode)
        #expect(state.argumentTarget?.title == "YouTube")
    }

    @Test func apluginThatTakesNoArgumentDoesNotEnter() {
        let state = state([result("Reload", argument: nil)])
        #expect(!state.enterArgumentMode())
        #expect(!state.isInArgumentMode)
    }

    /// A space after an application is just a space.
    @Test func anApplicationDoesNotEnterArgumentMode() {
        let state = state([result("Safari", kind: .application, argument: nil)])
        #expect(!state.enterArgumentMode())
    }

    @Test func withNothingSelectedNothingHappens() {
        #expect(!LauncherState().enterArgumentMode())
    }

    /// PRD §10.3: apps and files disappear, so nothing but the plugin is in
    /// front of the user while they type its argument.
    @Test func resultsAreClearedOnEntry() {
        let state = state([result("YouTube"), result("Safari", kind: .application, argument: nil)])
        _ = state.enterArgumentMode()
        #expect(state.results.isEmpty)
    }

    @Test func typingAccumulatesIntoTheArgument() {
        let state = state([result("YouTube")])
        _ = state.enterArgumentMode()
        state.appendToArgument("swift")
        state.appendToArgument(" 6")
        #expect(state.argumentText == "swift 6")
    }

    @Test func typingIsIgnoredOutsideArgumentMode() {
        let state = state([result("YouTube")])
        state.appendToArgument("swift")
        #expect(state.argumentText.isEmpty)
    }

    /// Backspace deletes while there is something to delete, and only leaves
    /// argument mode when there is not.
    @Test func backspaceDeletesBeforeItExits() {
        let state = state([result("YouTube")])
        _ = state.enterArgumentMode()
        state.appendToArgument("ab")

        #expect(state.deleteLastArgumentCharacter())
        #expect(state.argumentText == "a")
        #expect(state.isInArgumentMode)

        #expect(state.deleteLastArgumentCharacter())
        #expect(state.argumentText.isEmpty)
        #expect(state.isInArgumentMode)

        // Nothing left: this one leaves argument mode instead.
        #expect(!state.deleteLastArgumentCharacter())
        #expect(!state.isInArgumentMode)
    }

    @Test func exitingClearsTheArgumentAndTheTarget() {
        let state = state([result("YouTube")])
        _ = state.enterArgumentMode()
        state.appendToArgument("swift")
        state.exitArgumentMode()

        #expect(!state.isInArgumentMode)
        #expect(state.argumentText.isEmpty)
        #expect(state.argumentTarget == nil)
    }

    /// PRD §10.3: with required input missing, Return must not run anything.
    @Test func arequiredArgumentIsUnsatisfiedWhileEmpty() {
        let state = state([
            result("YouTube", argument: ArgumentRequest(placeholder: nil, isRequired: true))
        ])
        _ = state.enterArgumentMode()
        #expect(!state.isArgumentSatisfied)

        state.appendToArgument("swift")
        #expect(state.isArgumentSatisfied)
    }

    /// Whitespace is not an argument.
    @Test func whitespaceDoesNotSatisfyArequiredArgument() {
        let state = state([
            result("YouTube", argument: ArgumentRequest(placeholder: nil, isRequired: true))
        ])
        _ = state.enterArgumentMode()
        state.appendToArgument("   ")
        #expect(!state.isArgumentSatisfied)
    }

    @Test func anOptionalArgumentIsSatisfiedWhileEmpty() {
        let state = state([result("YouTube")])
        _ = state.enterArgumentMode()
        #expect(state.isArgumentSatisfied)
    }

    /// Presenting the launcher again must not resume a half-typed argument.
    @Test func presentingAgainLeavesArgumentMode() {
        let state = state([result("YouTube")])
        _ = state.enterArgumentMode()
        state.appendToArgument("swift")

        state.prepareForPresentation()
        #expect(!state.isInArgumentMode)
        #expect(state.argumentText.isEmpty)
    }
}
