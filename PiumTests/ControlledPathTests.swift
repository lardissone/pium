import Testing
import Foundation
@testable import Pium

@Suite("Controlled path")
@MainActor
struct ControlledPathTests {
    /// An added directory exists to find something that was missing, not to
    /// redefine what already works. Appending is what makes it impossible for
    /// a user's directory to shadow `/usr/bin/git` with another `git`.
    @Test func additionsComeAfterTheDefaults() {
        let effective = ControlledPath.effective(adding: ["/opt/mine"])
        #expect(effective.last == "/opt/mine")
        #expect(effective.starts(with: ControlledPath.default))
    }

    @Test func aduplicateOfAdefaultDoesNotAppearTwice() {
        let effective = ControlledPath.effective(adding: ["/usr/bin", "/opt/mine", "/opt/mine"])
        #expect(effective.filter { $0 == "/usr/bin" }.count == 1)
        #expect(effective.filter { $0 == "/opt/mine" }.count == 1)
    }

    @Test func nothingAddedLeavesTheDefaults() {
        #expect(ControlledPath.effective(adding: []) == ControlledPath.default)
    }

    @Test func thepathsRoundTripThroughPreferences() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(preferences.additionalSearchPaths.isEmpty)
        preferences.additionalSearchPaths = ["/opt/mine"]
        #expect(preferences.additionalSearchPaths == ["/opt/mine"])
    }
}
