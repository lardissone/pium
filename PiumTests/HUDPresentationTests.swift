import Testing
import Foundation
@testable import Pium

@Suite("HUD presentation")
struct HUDPresentationTests {
    private func record(
        _ state: ExecutionRecord.State,
        out: String = "",
        err: String = ""
    ) -> ExecutionRecord {
        ExecutionRecord(
            id: UUID(),
            pluginID: "demo.probe",
            pluginName: "Probe",
            state: state,
            standardOutput: out,
            standardError: err,
            wasTruncated: false
        )
    }

    @Test func asilentSuccessShowsNothing() {
        #expect(HUDPresentation.forOutcome(record(.finished(exitCode: 0)), mode: .silent) == nil)
    }

    @Test func atoastSuccessShowsWhatTheCommandPrinted() throws {
        let hud = try #require(
            HUDPresentation.forOutcome(record(.finished(exitCode: 0), out: "done\n"), mode: .toast)
        )
        #expect(hud.kind == .success)
        #expect(hud.body == "done")
    }

    /// PRD §10.7: a failure is surfaced whatever the mode. `silent` means
    /// silent about success.
    @Test func afailureIsShownEvenWhenSilent() throws {
        let hud = try #require(
            HUDPresentation.forOutcome(
                record(.finished(exitCode: 2), err: "boom"), mode: .silent
            )
        )
        #expect(hud.kind == .failure)
        #expect(hud.body.contains("boom"))
    }

    /// PRD §11: the user pressed Cancel; telling them it was cancelled tells
    /// them what they just did.
    @Test func acancelledRunShowsNothing() {
        #expect(HUDPresentation.forOutcome(record(.cancelled), mode: .toast) == nil)
        #expect(HUDPresentation.forOutcome(record(.cancelled), mode: .silent) == nil)
    }

    @Test func atimeoutSaysItRanTooLong() throws {
        let hud = try #require(HUDPresentation.forOutcome(record(.timedOut), mode: .silent))
        #expect(hud.kind == .failure)
    }

    @Test func acommandThatNeverStartedShowsWhy() throws {
        let hud = try #require(
            HUDPresentation.forOutcome(
                record(.failed(.quarantined(path: "/tmp/run.sh"))), mode: .silent
            )
        )
        #expect(hud.kind == .failure)
        #expect(hud.body == ExecutionFailure.quarantined(path: "/tmp/run.sh").message)
    }

    /// PRD §11: an error stays up longer than a success.
    @Test func afailureLastsLongerThanASuccess() throws {
        let success = try #require(
            HUDPresentation.forOutcome(record(.finished(exitCode: 0), out: "ok"), mode: .toast)
        )
        let failure = try #require(
            HUDPresentation.forOutcome(record(.finished(exitCode: 1)), mode: .toast)
        )
        #expect(failure.duration > success.duration)
    }

    /// A toast whose command printed nothing has nothing to show.
    @Test func atoastWithNoOutputShowsNothing() {
        #expect(HUDPresentation.forOutcome(record(.finished(exitCode: 0)), mode: .toast) == nil)
    }

    @Test func truncatedOutputSaysSo() throws {
        var truncated = record(.finished(exitCode: 0), out: "lots")
        truncated.wasTruncated = true
        let hud = try #require(HUDPresentation.forOutcome(truncated, mode: .toast))
        #expect(hud.body != "lots")
        #expect(hud.body.contains("lots"))
    }
}
