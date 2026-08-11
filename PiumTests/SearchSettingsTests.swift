import Testing
import Foundation
@testable import Pium

@Suite("Search settings")
@MainActor
struct SearchSettingsTests {
    private func view(alreadyRequested: Set<String> = []) -> SearchSettingsView {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.requestedFolderAccess = alreadyRequested
        return SearchSettingsView(
            frecency: FrecencyStore(
                fileURL: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
            ),
            access: ProtectedFolderAccess(preferences: preferences) { _ in }
        )
    }

    /// The three states map to three different things to do. A folder already
    /// refused is the one that matters: macOS will not ask again, so offering
    /// "Allow" there would be a button that does nothing.
    @Test func eachStatusOffersTheOnlyActionThatWorksForIt() {
        let view = view()
        #expect(view.action(for: .notRequested) == .allow)
        #expect(view.action(for: .granted) == .alreadyAllowed)
        #expect(view.action(for: .blocked) == .openSystemSettings)
    }

    /// A refresh must not race the request it was triggered by. Answering the
    /// system's prompt reactivates Pium, and reactivating is what a refresh
    /// listens for — so a refresh that ran then could read what Pium remembers
    /// asking about before the request recorded the folder it just asked for,
    /// and replace a folder the user has this second granted with an Allow
    /// button.
    @Test func arefreshStandsAsideWhileArequestIsInFlight() {
        #expect(
            SearchSettingsView.shouldRefresh(
                onActivation: false, sentToSystemSettings: false, isRequesting: true
            ) == false
        )
        #expect(
            SearchSettingsView.shouldRefresh(
                onActivation: true, sentToSystemSettings: true, isRequesting: true
            ) == false
        )
    }

    /// Refreshing reads the folders, and reading is what makes macOS ask —
    /// whenever *its* record says undetermined, which is not always what Pium
    /// remembers. Refreshing on every activation therefore asked on every
    /// activation, one prompt per folder, with no way out but answering them.
    ///
    /// So an activation only earns a refresh when the user was sent to System
    /// Settings and has come back. Opening the pane always does, because that
    /// is the user arriving to look at exactly this.
    @Test func onlyAreturnFromSystemSettingsEarnsArefreshOnActivation() {
        #expect(
            SearchSettingsView.shouldRefresh(
                onActivation: true, sentToSystemSettings: false, isRequesting: false
            ) == false,
            "Activating Pium for any other reason must not read the folders"
        )
        #expect(
            SearchSettingsView.shouldRefresh(
                onActivation: true, sentToSystemSettings: true, isRequesting: false
            )
        )
        #expect(
            SearchSettingsView.shouldRefresh(
                onActivation: false, sentToSystemSettings: false, isRequesting: false
            ),
            "Opening the pane is the user arriving to look at this"
        )
    }
}
