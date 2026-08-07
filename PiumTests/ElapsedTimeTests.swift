import Testing
@testable import Pium

@Suite("Elapsed time")
struct ElapsedTimeTests {
    @Test func secondsUnderAMinuteReadAsSeconds() {
        #expect(ElapsedTime.format(0) == "0s")
        #expect(ElapsedTime.format(9) == "9s")
        #expect(ElapsedTime.format(59) == "59s")
    }

    @Test func aminuteAndOverReadsAsMinutesAndSeconds() {
        #expect(ElapsedTime.format(60) == "1:00")
        #expect(ElapsedTime.format(61) == "1:01")
        #expect(ElapsedTime.format(599) == "9:59")
    }

    /// Past an hour it keeps counting in minutes rather than growing a third
    /// field: a command running that long is already the exceptional case, and
    /// a stopwatch that changes shape mid-run is harder to read, not easier.
    @Test func anhourKeepsCounting() {
        #expect(ElapsedTime.format(3600) == "60:00")
    }
}
