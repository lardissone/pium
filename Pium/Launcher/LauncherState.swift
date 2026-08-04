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

    /// Changes on every presentation, giving the view something to react to
    /// even when the query was already empty.
    private(set) var presentationToken = UUID()

    /// Every opening starts with an empty query and focused input.
    func prepareForPresentation() {
        query = ""
        presentationToken = UUID()
    }
}
