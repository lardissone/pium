import Testing
import Foundation
@testable import Pium

@Suite("Onboarding")
@MainActor
struct OnboardingTests {
    /// First launch asks about every protected folder at once, not one at a
    /// time: the person is being asked one question — may Pium search my
    /// files — and three buttons would read as three unrelated demands.
    @Test func theFirstLaunchAsksAboutAllThreeFolders() async {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let access = ProtectedFolderAccess(preferences: preferences) { _ in }
        let view = OnboardingView(
            shortcut: .init(keyCode: 49, modifiers: [.option], keyLabel: "Space"),
            access: access,
            onFinish: {}
        )

        await view.requestFolderAccess()

        #expect(preferences.requestedFolderAccess == ["documents", "desktop", "downloads"])
    }

    /// A greyed-out button says nothing about what the answers were, so the
    /// screen says it in words — and says something different when one of the
    /// folders was refused, which is the case somebody has to act on.
    @Test func theOutcomeLineTellsAllowedApartFromRefused() {
        let allowed = OnboardingView.folderOutcome(of: [.documents: .granted, .desktop: .granted])
        let refused = OnboardingView.folderOutcome(of: [.documents: .granted, .desktop: .blocked])

        #expect(allowed != refused)
        // A key with no catalog entry comes back as the key itself, which would
        // otherwise pass as a message.
        #expect(!allowed.hasPrefix("onboarding."))
        #expect(!refused.hasPrefix("onboarding."))
    }
}
