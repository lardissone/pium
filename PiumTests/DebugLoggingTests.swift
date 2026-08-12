import Testing
import Foundation
@testable import Pium

@Suite("Debug logging deadline")
@MainActor
struct DebugLoggingTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    /// Reproducing a bug takes minutes. A mode that records everything the
    /// user types and has been on since March is a leak waiting for an
    /// occasion, so enabling it sets an end.
    @Test func asessionLastsADay() {
        let day: TimeInterval = 24 * 60 * 60
        #expect(DebugLogging.sessionLength == day)
        #expect(DebugLogging.deadline(from: now) == now.addingTimeInterval(day))
    }

    @Test func nodeadlineMeansOff() {
        #expect(DebugLogging.isActive(expiry: nil, now: now) == false)
    }

    @Test func adeadlineInTheFutureIsLive() {
        #expect(DebugLogging.isActive(expiry: now.addingTimeInterval(60), now: now))
    }

    /// The moment it passes, not some moment after it.
    @Test func adeadlineInThePastIsOver() {
        #expect(DebugLogging.isActive(expiry: now.addingTimeInterval(-1), now: now) == false)
        #expect(DebugLogging.isActive(expiry: now, now: now) == false)
    }

    @Test func thedeadlineRoundTripsThroughPreferences() {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(preferences.debugLoggingExpiry == nil)
        preferences.debugLoggingExpiry = now
        #expect(preferences.debugLoggingExpiry == now)
        preferences.debugLoggingExpiry = nil
        #expect(preferences.debugLoggingExpiry == nil)
    }
}
