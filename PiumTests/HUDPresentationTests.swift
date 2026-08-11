import Testing
import Foundation
@testable import Pium

@Suite("HUD presentation")
struct HUDPresentationTests {
    private func record(
        _ ending: ExecutionEnding,
        mode: PluginOutputMode = .silent,
        out: String = "",
        err: String = ""
    ) -> ExecutionRecord {
        ExecutionRecord(
            id: UUID(),
            pluginID: "demo.probe",
            pluginName: "Probe",
            outputMode: mode,
            startedAt: Date(),
            state: .ended(ending),
            standardOutput: out,
            standardError: err,
            wasTruncated: false
        )
    }

    @Test func asilentSuccessShowsNothing() {
        #expect(HUDPresentation.forOutcome(record(.exited(0), mode: .silent)) == nil)
    }

    @Test func atoastSuccessShowsWhatTheCommandPrinted() throws {
        let hud = try #require(
            HUDPresentation.forOutcome(record(.exited(0), mode: .toast, out: "done\n"))
        )
        #expect(hud.kind == .success)
        #expect(hud.body == "done")
    }

    /// PRD §10.7: a failure is surfaced whatever the mode. `silent` means
    /// silent about success.
    @Test func afailureIsShownEvenWhenSilent() throws {
        let hud = try #require(
            HUDPresentation.forOutcome(record(.exited(2), mode: .silent, err: "boom"))
        )
        #expect(hud.kind == .failure)
        #expect(hud.body.contains("boom"))
    }

    /// PRD §11: the user pressed Cancel; telling them it was cancelled tells
    /// them what they just did.
    @Test func acancelledRunShowsNothing() {
        #expect(HUDPresentation.forOutcome(record(.cancelled, mode: .toast)) == nil)
        #expect(HUDPresentation.forOutcome(record(.cancelled, mode: .silent)) == nil)
    }

    @Test func atimeoutSaysItRanTooLong() throws {
        let hud = try #require(HUDPresentation.forOutcome(record(.timedOut, mode: .silent)))
        #expect(hud.kind == .failure)
        #expect(!hud.body.hasPrefix("hud."), "the HUD shows its lookup key: \(hud.body)")
    }

    /// The code is the whole message when the command said nothing, so a key
    /// the catalog has no entry for is not a cosmetic slip: `String(localized:)`
    /// hands back the key, and `hud.exited 2` is then all the user is told.
    @Test func anexitCodeWithNothingOnStandardErrorIsExplainedInWords() throws {
        let hud = try #require(HUDPresentation.forOutcome(record(.exited(2), mode: .silent)))
        #expect(hud.kind == .failure)
        #expect(!hud.body.hasPrefix("hud."), "the HUD shows its lookup key: \(hud.body)")
        #expect(hud.body.contains("2"))
    }

    @Test func asignalledRunNamesTheSignalInWords() throws {
        let hud = try #require(HUDPresentation.forOutcome(record(.signalled(9), mode: .silent)))
        #expect(hud.kind == .failure)
        #expect(!hud.body.hasPrefix("hud."), "the HUD shows its lookup key: \(hud.body)")
        #expect(hud.body.contains("9"))
    }

    @Test func acommandThatNeverStartedShowsWhy() throws {
        let hud = try #require(
            HUDPresentation.forOutcome(
                record(.failed(.quarantined(path: "/tmp/run.sh")), mode: .silent)
            )
        )
        #expect(hud.kind == .failure)
        #expect(hud.body == ExecutionFailure.quarantined(path: "/tmp/run.sh").message)
    }

    /// PRD §11: an error stays up longer than a success.
    @Test func afailureLastsLongerThanASuccess() throws {
        let success = try #require(
            HUDPresentation.forOutcome(record(.exited(0), mode: .toast, out: "ok"))
        )
        let failure = try #require(HUDPresentation.forOutcome(record(.exited(1), mode: .toast)))
        #expect(failure.duration > success.duration)
    }

    /// A toast whose command printed nothing has nothing to show.
    @Test func atoastWithNoOutputShowsNothing() {
        #expect(HUDPresentation.forOutcome(record(.exited(0), mode: .toast)) == nil)
    }

    @Test func truncatedOutputSaysSo() throws {
        var truncated = record(.exited(0), mode: .toast, out: "lots")
        truncated.wasTruncated = true
        let hud = try #require(HUDPresentation.forOutcome(truncated))
        #expect(hud.body != "lots")
        #expect(hud.body.contains("lots"))
    }

    /// A run that has not ended yet is not something the outcome HUD has
    /// anything to say about — `RunningPresentation` is what covers it.
    @Test func arunStillGoingShowsNoOutcome() {
        let running = ExecutionRecord(
            id: UUID(),
            pluginID: "demo.probe",
            pluginName: "Probe",
            outputMode: .toast,
            startedAt: Date(),
            state: .running,
            standardOutput: "partial",
            standardError: "",
            wasTruncated: false
        )
        #expect(HUDPresentation.forOutcome(running) == nil)
    }
}
