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
        #expect(SearchSettingsView.shouldRefresh(whileRequesting: true) == false)
        #expect(SearchSettingsView.shouldRefresh(whileRequesting: false))
    }
}
