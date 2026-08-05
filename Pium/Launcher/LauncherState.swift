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
    var query = ""
    private(set) var results: [SearchResult] = []

    /// Selection is a stable result ID rather than an index, because results
    /// reorder as providers report in and the user's row must not move out
    /// from under them.
    private(set) var selectedID: String?

    /// Changes on every presentation, giving the view something to react to
    /// even when the query was already empty.
    private(set) var presentationToken = UUID()

    private(set) var isActionMenuPresented = false

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

    /// Every opening starts with an empty query, no results, and focused input.
    func prepareForPresentation() {
        query = ""
        exitArgumentMode()
        setResults([])
        presentationToken = UUID()
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
            // just opened.
            dismissActionMenu()
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
        argumentTarget = nil
        argumentText = ""
    }

    func appendToArgument(_ characters: String) {
        guard isInArgumentMode else { return }
        argumentText += characters
    }

    /// Deletes one character, or leaves argument mode when there is nothing left.
    ///
    /// Returns whether anything was deleted, so the caller can tell the two
    /// outcomes apart.
    @discardableResult
    func deleteLastArgumentCharacter() -> Bool {
        guard isInArgumentMode else { return false }
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
    func action(
        matching key: ActionShortcut.Key,
        modifiers: ActionShortcut.Modifiers
    ) -> ResultAction? {
        selectedResult?.actions.first {
            $0.shortcut?.matches(key: key, modifiers: modifiers) == true
        }
    }

    func select(id: String?) {
        guard let id, results.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// Moves the selection, clamping at both ends. Deliberately does not wrap:
    /// holding a key should stop at the last row, not loop.
    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + offset, 0), results.count - 1)
        selectedID = results[next].id
    }
}
