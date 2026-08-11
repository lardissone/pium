import Testing
import Foundation
@testable import Pium

/// PRD §10.3: `Return` on a plugin whose input is required must not run it
/// empty. Exercises the actual view code that decides this — `activateSelected`
/// and `handleReturn` are not `private` for exactly this reason — by
/// constructing `LauncherView` directly and calling them, the same way
/// `PluginsSettingsTests` exercises `PluginsSettingsView.setEnabled` without a
/// window.
@Suite("Launcher activation")
@MainActor
struct LauncherActivationTests {
    /// The two-action shape `PluginProvider` builds: `Return` runs, `⌘ Return`
    /// reveals. See `LauncherConfirmationTests.pluginResult` for the same
    /// shape used against the confirmation gate.
    private func pluginResult(
        id: String = "demo.deploy",
        argument: ArgumentRequest?,
        confirmation: String? = nil
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

    /// Cheap enough to build fresh per test: no plugin ever actually runs a
    /// process in this suite, so what backs it does not matter.
    private func executionManager() -> ExecutionManager {
        ExecutionManager(
            configuration: PluginConfigurationStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            secrets: InMemorySecretStore()
        )
    }

    /// Records what `onDismiss` and `onPerform` were told, so a test can tell
    /// "ran" from "did not" without a real command executing.
    @MainActor
    private final class ActivationSpy {
        private(set) var didDismiss = false
        private(set) var performed: (result: SearchResult, action: ResultAction)?

        func onDismiss() { didDismiss = true }
        func onPerform(_ result: SearchResult, _ action: ResultAction) {
            performed = (result, action)
        }
    }

    private func view(state: LauncherState, spy: ActivationSpy) -> LauncherView {
        LauncherView(
            state: state,
            executionManager: executionManager(),
            onDismiss: { spy.onDismiss() },
            onQueryChanged: { _ in },
            onPerform: { result, action in spy.onPerform(result, action) }
        )
    }

    @Test func returnOnARequiredInputPluginEntersArgumentModeInsteadOfRunning() {
        let target = pluginResult(argument: ArgumentRequest(placeholder: nil, isRequired: true))
        let state = LauncherState()
        state.setResults([target])
        let spy = ActivationSpy()

        view(state: state, spy: spy).activateSelected()

        #expect(state.isInArgumentMode)
        #expect(state.argumentTarget?.id == "demo.deploy")
        #expect(spy.performed == nil)
        #expect(!spy.didDismiss)
    }

    @Test func returnOnAnOptionalInputPluginStillRunsWithNoArgument() {
        let target = pluginResult(argument: ArgumentRequest(placeholder: nil, isRequired: false))
        let state = LauncherState()
        state.setResults([target])
        let spy = ActivationSpy()

        view(state: state, spy: spy).activateSelected()

        #expect(!state.isInArgumentMode)
        let expectedID = "demo.deploy"
        #expect(spy.performed?.result.id == expectedID)
        #expect(spy.performed?.action.id == "execute")
        #expect(spy.didDismiss)
    }

    /// A double click shares `activateSelected` with `Return`, so the same
    /// gate has to hold for it without a copy of its own.
    @Test func doubleClickOnARequiredInputPluginAlsoEntersArgumentModeInsteadOfRunning() {
        let target = pluginResult(argument: ArgumentRequest(placeholder: nil, isRequired: true))
        let state = LauncherState()
        state.setResults([target])
        let spy = ActivationSpy()

        // What `ResultListView`'s double click does: select, then activate.
        state.select(id: target.id)
        view(state: state, spy: spy).activateSelected()

        #expect(state.isInArgumentMode)
        #expect(spy.performed == nil)
    }

    /// A plugin with no argument at all is unaffected: `Return` runs it the
    /// way it always has.
    @Test func returnOnAPluginWithNoArgumentRunsAsBefore() {
        let target = pluginResult(argument: nil)
        let state = LauncherState()
        state.setResults([target])
        let spy = ActivationSpy()

        view(state: state, spy: spy).activateSelected()

        #expect(!state.isInArgumentMode)
        #expect(spy.performed?.action.id == "execute")
    }

    /// Once in argument mode, existing behaviour stands: empty still blocks,
    /// typed runs. Unchanged by PIUM-107, but exercised through the same
    /// decision path (`handleReturn`) for regression coverage.
    @Test func argumentModeReturnRunsOnceTypedButNotWhileItIsStillEmpty() {
        let target = pluginResult(argument: ArgumentRequest(placeholder: nil, isRequired: true))
        let state = LauncherState()
        state.setResults([target])
        state.enterArgumentMode()
        let spy = ActivationSpy()
        let launcherView = view(state: state, spy: spy)

        _ = launcherView.handleReturn(modifiers: [])
        #expect(spy.performed == nil, "An empty required argument must not run")

        state.setArgumentText("v2")
        _ = launcherView.handleReturn(modifiers: [])
        #expect(spy.performed?.action.id == "execute")
        #expect(spy.didDismiss)
    }

    /// The required-argument gate is about running, and only about running.
    /// `⌘ Return` reveals a plugin's JSON, which is not a run — and an empty
    /// field is exactly when somebody is most likely to want to read what
    /// they are about to run. Gating every `Return`-family action on the
    /// argument left that keystroke doing nothing at all.
    @Test func revealWorksInArgumentModeWhileTheRequiredFieldIsStillEmpty() {
        let target = pluginResult(argument: ArgumentRequest(placeholder: nil, isRequired: true))
        let state = LauncherState()
        state.setResults([target])
        state.enterArgumentMode()
        let spy = ActivationSpy()
        let launcherView = view(state: state, spy: spy)

        _ = launcherView.handleReturn(modifiers: [.command])
        #expect(spy.performed?.action.id == "reveal", "⌘ Return must reveal, empty field or not")

        // And the gate it is not subject to still holds for the run itself.
        // A second spy rather than resetting the first: `performed` is
        // `private(set)`, and a fresh one also proves this call recorded
        // nothing rather than merely leaving an earlier value in place.
        let runSpy = ActivationSpy()
        _ = view(state: state, spy: runSpy).handleReturn(modifiers: [])
        #expect(runSpy.performed == nil, "An empty required argument must still block the run")
    }

    /// A plugin that both requires input and confirms must ask for the
    /// argument first — you cannot confirm a command whose argument does not
    /// exist yet — and only then ask to confirm.
    @Test func requiredInputWithConfirmationAsksForTheArgumentFirstThenConfirms() {
        let target = pluginResult(
            argument: ArgumentRequest(placeholder: nil, isRequired: true),
            confirmation: "This deploys to production."
        )
        let state = LauncherState()
        state.setResults([target])
        let spy = ActivationSpy()
        let launcherView = view(state: state, spy: spy)

        // Return on the row asks for the argument, not the confirmation.
        launcherView.activateSelected()
        #expect(state.isInArgumentMode)
        #expect(state.confirmingResult == nil)
        #expect(spy.performed == nil)

        // Typed and returned: only now does it ask to confirm.
        state.setArgumentText("v2")
        _ = launcherView.handleReturn(modifiers: [])
        #expect(state.confirmingResult?.id == "demo.deploy")
        #expect(spy.performed == nil, "Must not run before the confirmation is answered")

        // Confirming — a second Return — runs it.
        _ = launcherView.handleReturn(modifiers: [])
        #expect(spy.performed?.action.id == "execute")
        #expect(spy.didDismiss)
    }

    /// `⌘ Return` means Reveal JSON, never the run this gate protects, so a
    /// required argument must not stop it either.
    @Test func commandReturnRevealsARequiredInputPluginWithoutEnteringArgumentMode() {
        let target = pluginResult(argument: ArgumentRequest(placeholder: nil, isRequired: true))
        let state = LauncherState()
        state.setResults([target])
        let spy = ActivationSpy()

        view(state: state, spy: spy).activateSelected(modifiers: [.command])

        #expect(!state.isInArgumentMode)
        #expect(spy.performed?.action.id == "reveal")
    }

    // MARK: - The action menu, which shares `attemptToPerform` rather than `activateSelected`

    /// `⌘ K` then `Return` on a required-input plugin's highlighted Execute
    /// row must ask for the argument, the same as `Return` on the bare row.
    /// Before the fix moved the gate into `attemptToPerform`, the menu path
    /// never went through `activateSelected` and so ran the plugin empty.
    @Test func menuExecuteOnARequiredInputPluginEntersArgumentModeInsteadOfRunning() {
        let target = pluginResult(argument: ArgumentRequest(placeholder: nil, isRequired: true))
        let state = LauncherState()
        state.setResults([target])
        state.presentActionMenu()
        let spy = ActivationSpy()
        let launcherView = view(state: state, spy: spy)

        _ = launcherView.handleReturn(modifiers: [])

        #expect(state.isInArgumentMode)
        #expect(spy.performed == nil)
    }

    /// Through the menu, a plugin that both requires input and confirms must
    /// still ask for the argument first — not confirm a command whose
    /// argument does not exist yet and then run it empty.
    @Test func menuExecuteOnARequiredInputPluginWithConfirmationAsksForTheArgumentFirst() {
        let target = pluginResult(
            argument: ArgumentRequest(placeholder: nil, isRequired: true),
            confirmation: "This deploys to production."
        )
        let state = LauncherState()
        state.setResults([target])
        state.presentActionMenu()
        let spy = ActivationSpy()
        let launcherView = view(state: state, spy: spy)

        _ = launcherView.handleReturn(modifiers: [])

        #expect(state.isInArgumentMode)
        #expect(state.confirmingResult == nil, "Must ask for the argument before asking to confirm")
        #expect(spy.performed == nil)
    }

    /// Clicking "Run" in the menu goes through `attemptToPerform` directly —
    /// what `ActionMenuView`'s `onPerform` calls — rather than through
    /// `handleReturn`, so it needs its own proof the gate reaches it too.
    @Test func clickingMenuExecuteOnARequiredInputPluginEntersArgumentModeInsteadOfRunning() {
        let target = pluginResult(argument: ArgumentRequest(placeholder: nil, isRequired: true))
        let state = LauncherState()
        state.setResults([target])
        let spy = ActivationSpy()
        let launcherView = view(state: state, spy: spy)

        launcherView.attemptToPerform(target.actions[0], on: target)

        #expect(state.isInArgumentMode)
        #expect(spy.performed == nil)
    }
}
