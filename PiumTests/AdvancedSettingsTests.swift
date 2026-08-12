import Testing
import Foundation
@testable import Pium

@Suite("Advanced settings")
@MainActor
struct AdvancedSettingsTests {
    /// Not private, so the decision is testable without a window — the same
    /// reason `SearchSettingsView.shouldRefresh` is not.
    @Test func remainingTimeCountsDownToTheDeadline() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let hour: TimeInterval = 60 * 60
        let none: TimeInterval = 0
        #expect(
            AdvancedSettingsView.remaining(until: now.addingTimeInterval(hour), now: now) == hour
        )
        #expect(AdvancedSettingsView.remaining(until: now, now: now) == none)
        #expect(
            AdvancedSettingsView.remaining(until: now.addingTimeInterval(-hour), now: now) == none,
            "a passed deadline has no time left rather than negative time"
        )
    }

    /// A path pasted from a terminal arrives with a trailing slash or a stray
    /// space as often as not, and `/opt/mine/` and `/opt/mine` are the same
    /// directory being stored twice.
    @Test func apathIsTidiedBeforeItIsStored() {
        #expect(AdvancedSettingsView.normalisedPath("  /opt/mine  ") == "/opt/mine")
        #expect(AdvancedSettingsView.normalisedPath("/opt/mine/") == "/opt/mine")
        #expect(AdvancedSettingsView.normalisedPath("~/bin") == NSHomeDirectory() + "/bin")
        #expect(AdvancedSettingsView.normalisedPath("   ") == nil)
        #expect(
            AdvancedSettingsView.normalisedPath("relative/bin") == nil,
            "a search path is absolute"
        )
    }
}
