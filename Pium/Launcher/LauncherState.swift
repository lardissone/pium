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

    var selectedResult: SearchResult? {
        results.first { $0.id == selectedID }
    }

    /// Every opening starts with an empty query, no results, and focused input.
    func prepareForPresentation() {
        query = ""
        setResults([])
        presentationToken = UUID()
    }

    func setResults(_ newResults: [SearchResult]) {
        let previousID = selectedID
        results = newResults
        // A new search must not leave a menu hanging over stale results.
        dismissActionMenu()

        // Keep the user's selection if it survived the update; otherwise fall
        // back to the top rather than leaving nothing selected.
        if let previousID, newResults.contains(where: { $0.id == previousID }) {
            selectedID = previousID
        } else {
            selectedID = newResults.first?.id
        }
    }

    /// Opens the contextual menu, but only when there is something to show.
    func presentActionMenu() {
        guard let selected = selectedResult, !selected.actions.isEmpty else { return }
        highlightedActionID = selected.actions.first?.id
        isActionMenuPresented = true
    }

    func dismissActionMenu() {
        isActionMenuPresented = false
        highlightedActionID = nil
    }

    var highlightedAction: ResultAction? {
        guard isActionMenuPresented else { return nil }
        return selectedResult?.actions.first { $0.id == highlightedActionID }
    }

    /// Moves the menu highlight, clamping at both ends for the same reason the
    /// result list does not wrap.
    func moveActionHighlight(by offset: Int) {
        guard let actions = selectedResult?.actions, !actions.isEmpty else { return }
        let current = actions.firstIndex { $0.id == highlightedActionID } ?? 0
        let next = min(max(current + offset, 0), actions.count - 1)
        highlightedActionID = actions[next].id
    }

    func highlightAction(id: String?) {
        guard
            let id,
            selectedResult?.actions.contains(where: { $0.id == id }) == true
        else { return }
        highlightedActionID = id
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
