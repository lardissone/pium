import Testing
import Foundation
@testable import Pium

@Suite("Updates settings")
@MainActor
struct UpdatesSettingsTests {
    /// Before the first check there is no date to show, and the field still
    /// has to say something a person can read. An empty value there looks like
    /// a bug, and a placeholder date would be a lie about a check that never
    /// happened.
    @Test func anupdaterThatHasNeverCheckedSaysSoInWords() {
        let never = UpdatesSettingsView.lastCheck(nil)
        let readsAsADate = never.rangeOfCharacter(from: .decimalDigits) != nil
        #expect(!never.isEmpty)
        #expect(!readsAsADate, "\"\(never)\" reads as a date; nothing has been checked yet")
    }

    @Test func acheckIsShownAsTheDateItHappened() {
        // Early February 2026, far enough from a year boundary that the
        // formatter's time zone cannot move it into another year.
        let date = Date(timeIntervalSince1970: 1_770_000_000)
        let rendered = UpdatesSettingsView.lastCheck(date)

        #expect(rendered.contains("2026"))
        #expect(rendered != UpdatesSettingsView.lastCheck(nil))
    }
}
