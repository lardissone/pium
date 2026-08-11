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
}
