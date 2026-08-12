import Foundation

/// The launcher's presentation state, owned by `LauncherPanelController`.
///
/// The panel is hidden with `orderOut` rather than destroyed, so the SwiftUI
/// view stays mounted between openings and `onAppear` does not fire again.
/// This carries the per-opening reset the view cannot derive on its own.
/// `testSecondOpeningIsAlsoEmptyAndFocused` is the regression test.
@MainActor
@Observable
final class LauncherState {
    /// `nil` for the tests and previews that have nothing to do with
    /// updating — threading a stub through all of them would be noise.
    private let updates: (any UpdateAvailability)?

    init(updates: (any UpdateAvailability)? = nil) {
        self.updates = updates
    }

    /// The update notice PRD §13 asks for: shown when the launcher opens,
    /// never as a window over whatever the user was doing.
    var pendingUpdate: PendingUpdate? { updates?.pendingUpdate }

    func installPendingUpdate() { updates?.installPendingUpdate() }

    func dismissPendingUpdate() { updates?.dismissPendingUpdate() }

    /// Setting this always answers "not now" for any confirmation on screen:
    /// the message is about a specific result, and once the user is typing a
    /// different search that answer no longer applies — left standing, the
    /// list would stay collapsed to one stale row while a new search ran
    /// behind it. Argument mode types into `argumentText` instead, which
    /// freezes rather than cancels while confirming (see `appendToArgument`),
    /// so this does not reach it.
    var query = "" {
        didSet {
            cancelConfirmation()
            // A query being typed is a search that has not answered yet, so
            // whatever the last one concluded stops applying here rather than
            // when the next one starts. Otherwise "No results" stays on screen
            // over the results arriving underneath it.
            searchPhase = query.isEmpty ? .idle : .searching
        }
    }

    /// How far the current query has got.
    ///
    /// A phase rather than reading `results.isEmpty`, because providers
    /// stream: applications and plugins answer in single-digit milliseconds
    /// while Spotlight is still working, and a view driven by "empty right
    /// now" would say there are no results on the way to showing some.
    enum SearchPhase: Sendable, Equatable {
        /// Nothing has been typed. PRD §6.2: no results, no recents, nothing.
        case idle
        /// A query is in flight; some providers may already have answered.
        case searching
        /// Every provider has finished. Only now is an empty list a fact.
        case settled
    }

    private(set) var searchPhase: SearchPhase = .idle

    /// Whether the launcher should say the search found nothing.
    ///
    /// Argument mode is excluded: the list is deliberately empty there (PRD
    /// §10.3), and the plugin pill is what says why.
    var showsNoResults: Bool {
        searchPhase == .settled && results.isEmpty && !isInArgumentMode
    }

    private(set) var results: [SearchResult] = []

    /// Selection is a stable result ID rather than an index, because results
    /// reorder as providers report in and the user's row must not move out
    /// from under them.
    private(set) var selectedID: String?

    /// Changes on every presentation, giving the view something to react to
    /// even when the query was already empty.
    private(set) var presentationToken = UUID()

    private(set) var isActionMenuPresented = false

    /// The result currently asking to confirm before it runs. `nil` outside
    /// that state. Never persisted across a cancellation: PRD §10.4 asks
    /// every time, so this is the only place that fact could leak from and it
    /// is always reset by `cancelConfirmation`.
    private(set) var confirmingResult: SearchResult?

    /// Which action the menu has highlighted. Held as an ID for the same reason
    /// result selection is: the list it indexes into can change underneath.
    private(set) var highlightedActionID: String?

    /// What the user has typed into the open menu. Separate from `query`:
    /// typing behind an open menu filters its actions rather than changing the
    /// search underneath it.
    private(set) var actionQuery = ""

    /// The plugin the next keystrokes belong to. `nil` in ordinary search.
    private(set) var argumentTarget: SearchResult?

    /// What has been typed for that plugin. Separate from `query`: it is the
    /// plugin's input, not a search, and it is never recorded as usage history.
    private(set) var argumentText = ""

    var isInArgumentMode: Bool { argumentTarget != nil }

    /// Whether the target could run with what has been typed. A required
    /// argument that is empty or only whitespace is not an argument.
    var isArgumentSatisfied: Bool {
        guard let request = argumentTarget?.argument else { return false }
        guard request.isRequired else { return true }
        return !argumentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedResult: SearchResult? {
        results.first { $0.id == selectedID }
    }

    /// The rows the list actually shows. Collapsed to just the result asking
    /// for confirmation while one is pending, so its message is read next to
    /// the one plugin it is about rather than buried among unrelated rows.
    /// `results` itself is never touched for this, so cancelling — `Esc` —
    /// restores exactly what was there before with no bookkeeping of its own.
    ///
    /// Argument mode is excluded: `results` is already empty there by design
    /// (PRD §10.3) — the plugin pill is the only thing naming it — and a
    /// confirmation reached from inside it must not put a row back under a
    /// pill that already says the same thing.
    var presentedResults: [SearchResult] {
        if let confirmingResult, argumentTarget == nil { return [confirmingResult] }
        return results
    }

    /// Every opening starts with an empty query, no results, and focused input.
    func prepareForPresentation() {
        query = ""
        exitArgumentMode()
        setResults([])
        searchPhase = .idle
        presentationToken = UUID()
    }

    /// Called when a query's providers are asked, and again when the last of
    /// them has finished. The controller drives both, because it owns the
    /// stream and is the only thing that knows it ended.
    func beginSearch() {
        guard !query.isEmpty else { return }
        searchPhase = .searching
    }

    func endSearch() {
        guard searchPhase == .searching else { return }
        searchPhase = .settled
    }

    func setResults(_ newResults: [SearchResult]) {
        let previousID = selectedID
        results = newResults

        // Keep the user's selection if it survived the update; otherwise fall
        // back to the top rather than leaving nothing selected.
        if let previousID, newResults.contains(where: { $0.id == previousID }) {
            selectedID = previousID
        } else {
            selectedID = newResults.first?.id
            // The menu described a result that is gone. Closing it only in this
            // case matters: every keystroke runs a search, so dismissing on any
            // update would let a batch still in flight close a menu the user
            // just opened. A pending confirmation is cleared for the same
            // reason — it names a result that no longer exists.
            dismissActionMenu()
            cancelConfirmation()
        }
    }

    /// Enters argument mode on the selected result, if it takes one.
    ///
    /// Returns whether it did, so the key handler can fall through and let a
    /// space be an ordinary space when it did not.
    @discardableResult
    func enterArgumentMode() -> Bool {
        guard let selected = selectedResult, selected.argument != nil else { return false }
        dismissActionMenu()
        // PRD §10.3: applications and files disappear, so the plugin is the only
        // thing in front of the user while they type its argument.
        setResults([])
        argumentTarget = selected
        argumentText = ""
        return true
    }

    func exitArgumentMode() {
        // A confirmation showing here is asking about the argument text this
        // is about to erase — answering it after would run whatever is left,
        // which is not what was asked. The same principle `query`'s `didSet`
        // above already applies when a pending confirmation's premise goes
        // stale, for the one other way that can happen.
        if let confirmingResult, confirmingResult.id == argumentTarget?.id {
            cancelConfirmation()
        }
        argumentTarget = nil
        argumentText = ""
    }

    /// Guarded by `confirmingResult` as well as argument mode: with a
    /// confirmation showing, further typing must not change what a `Return`
    /// would run out from under the message the user is looking at.
    func appendToArgument(_ characters: String) {
        guard isInArgumentMode, confirmingResult == nil else { return }
        argumentText += characters
    }

    /// Replaces the argument wholesale, which is what the search field's binding
    /// does while argument mode is on. See `appendToArgument` on why a pending
    /// confirmation blocks this too.
    func setArgumentText(_ text: String) {
        guard isInArgumentMode, confirmingResult == nil else { return }
        argumentText = text
    }

    /// Deletes one character, or leaves argument mode when there is nothing left.
    ///
    /// Returns whether anything was deleted, so the caller can tell the two
    /// outcomes apart. Blocked while a confirmation is showing, same as the
    /// other argument mutators — including the exit on an empty backspace,
    /// which would otherwise abandon argument mode while `confirmingResult`
    /// still pointed at it.
    @discardableResult
    func deleteLastArgumentCharacter() -> Bool {
        guard isInArgumentMode, confirmingResult == nil else { return false }
        guard !argumentText.isEmpty else {
            exitArgumentMode()
            return false
        }
        argumentText.removeLast()
        return true
    }

    /// Opens the contextual menu, but only when there is something to show.
    func presentActionMenu() {
        guard let selected = selectedResult, !selected.actions.isEmpty else { return }
        actionQuery = ""
        highlightedActionID = selected.actions.first?.id
        isActionMenuPresented = true
    }

    func dismissActionMenu() {
        isActionMenuPresented = false
        highlightedActionID = nil
        actionQuery = ""
    }

    /// Leaves confirmation without running anything. Nothing here is
    /// remembered: the very next `Return` on the same result asks again.
    func cancelConfirmation() {
        confirmingResult = nil
    }

    /// Whether `action` on `result` should run right now — the one gate
    /// every path that can start a run goes through, so `confirmBeforeRun`
    /// (PRD §10.4) applies the same way to the keyboard, a double click, and
    /// the action menu, by key or by mouse alike.
    ///
    /// Only the `Return`-shortcut action is the run the PRD means: a menu's
    /// other actions (Reveal JSON, ...) are not gated and always return
    /// `true` unconfirmed. `result` is taken explicitly rather than inferred
    /// from selection, so a caller that already knows exactly which result
    /// an action belongs to — the action menu operates on whichever row it
    /// was opened for, not necessarily whatever is selected the instant this
    /// runs — cannot be second-guessed by a candidate this doesn't match.
    ///
    /// A confirmation already showing counts as an answer only when it names
    /// this exact `result`. Showing for a different one, it is replaced by a
    /// fresh confirmation for this `result` rather than being read as
    /// permission for it — the same principle `select(id:)` applies when the
    /// selection itself changes.
    ///
    /// Returns whether the caller should perform `action` now.
    @discardableResult
    func attemptToRun(_ action: ResultAction, on result: SearchResult) -> Bool {
        guard action.isRunAction, result.confirmation != nil else { return true }
        if confirmingResult?.id == result.id {
            cancelConfirmation()
            return true
        }
        dismissActionMenu()
        confirmingResult = result
        return false
    }

    /// The actions the menu is showing, narrowed by whatever has been typed
    /// into it. Scored with the same matcher the result list uses, so "reveal"
    /// and "finder" both find Reveal in Finder.
    var visibleActions: [ResultAction] {
        guard let actions = selectedResult?.actions else { return [] }
        let query = TextNormalizer.query(actionQuery)
        guard !query.isEmpty else { return actions }
        return actions.filter {
            FuzzyMatcher.bestScore(
                query,
                againstAnyOf: [TextNormalizer.candidate($0.title)]
            ) > FuzzyMatcher.rejectionThreshold
        }
    }

    var highlightedAction: ResultAction? {
        guard isActionMenuPresented else { return nil }
        return visibleActions.first { $0.id == highlightedActionID }
    }

    /// Moves the menu highlight, clamping at both ends for the same reason the
    /// result list does not wrap.
    func moveActionHighlight(by offset: Int) {
        let actions = visibleActions
        guard !actions.isEmpty else { return }
        let current = actions.firstIndex { $0.id == highlightedActionID } ?? 0
        let next = min(max(current + offset, 0), actions.count - 1)
        highlightedActionID = actions[next].id
    }

    func highlightAction(id: String?) {
        guard let id, visibleActions.contains(where: { $0.id == id }) else { return }
        highlightedActionID = id
    }

    func appendToActionQuery(_ characters: String) {
        guard isActionMenuPresented else { return }
        actionQuery += characters
        highlightFirstVisibleAction()
    }

    func deleteLastActionQueryCharacter() {
        guard isActionMenuPresented, !actionQuery.isEmpty else { return }
        actionQuery.removeLast()
        highlightFirstVisibleAction()
    }

    /// After the filter changes the highlight may point at something no longer
    /// shown, which would make `Return` do nothing.
    private func highlightFirstVisibleAction() {
        let actions = visibleActions
        if !actions.contains(where: { $0.id == highlightedActionID }) {
            highlightedActionID = actions.first?.id
        }
    }

    /// The action a pressed combination runs, if any. Key routing asks this
    /// rather than branching per key, so a new action needs no view change.
    /// `result` names what to resolve against, for the callers that have one
    /// in hand: argument mode has a target but no selected row, since
    /// `results` is empty there by PRD §10.3.
    func action(
        matching key: ActionShortcut.Key,
        modifiers: ActionShortcut.Modifiers,
        on result: SearchResult? = nil
    ) -> ResultAction? {
        (result ?? selectedResult)?.actions.first {
            $0.shortcut?.matches(key: key, modifiers: modifiers) == true
        }
    }

    /// Changing the selection answers nothing: a confirmation pending for
    /// the row being left off must not be read as permission for the row
    /// being moved onto, so it is cleared here rather than left to whichever
    /// caller happens to select next.
    func select(id: String?) {
        guard let id, results.contains(where: { $0.id == id }) else { return }
        if id != selectedID {
            cancelConfirmation()
        }
        selectedID = id
    }

    /// Moves the selection, clamping at both ends. Deliberately does not wrap:
    /// holding a key should stop at the last row, not loop.
    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + offset, 0), results.count - 1)
        // Same reason as `select(id:)`: an answer about the row being left
        // must not be read as permission for the row arrived at. Movement is
        // blocked while a confirmation is pending today, and `attemptToRun`
        // re-checks identity besides, so this closes the gap by construction
        // rather than fixing a reachable bug.
        if results[next].id != selectedID {
            cancelConfirmation()
        }
        selectedID = results[next].id
    }
}
