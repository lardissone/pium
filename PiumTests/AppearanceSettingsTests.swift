import Testing
import Foundation
@testable import Pium

@Suite("Appearance settings")
@MainActor
struct AppearanceSettingsTests {
    /// The control's own geometry is the information: the button for the
    /// top-left anchor is the one in the top left. A list of six names is not
    /// the same thing.
    @Test func theanchorsAreLaidOutTheWayTheySitOnScreen() {
        #expect(AppearanceSettingsView.rows == [
            [.topLeft, .topCenter, .topRight],
            [.bottomLeft, .bottomCenter, .bottomRight],
        ])
    }

    @Test func everyAnchorAppearsExactlyOnce() {
        let laidOut = AppearanceSettingsView.rows.flatMap(\.self)
        #expect(Set(laidOut) == Set(HUDAnchor.allCases))
        #expect(laidOut.count == HUDAnchor.allCases.count)
    }

    /// Every anchor needs words, because VoiceOver cannot read a rectangle's
    /// position — and a key the catalog has no entry for would put the key
    /// itself on screen.
    @Test func everyAnchorIsNamedInWords() {
        for anchor in HUDAnchor.allCases {
            #expect(!anchor.title.hasPrefix("settings."), "untranslated: \(anchor.title)")
            #expect(!anchor.title.isEmpty)
        }
    }

    @Test func choosingAnAnchorStoresIt() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.hudAnchor = .bottomLeft
        #expect(preferences.hudAnchor == .bottomLeft)
    }
}
