import Testing
import Foundation
@testable import Pium

@Suite("Debug event")
struct DebugEventTests {
    private let at = Date(timeIntervalSince1970: 1_000_000)

    private func line(_ event: DebugEvent) -> String {
        event.line(at: at)
    }

    /// One line per event, timestamp first. The reader is a person looking at
    /// a GitHub issue, not a parser.
    @Test func everyLineStartsWithAtimestampAndACategory() {
        let rendered = line(.search(query: "fire", results: 3, duration: .milliseconds(12)))
        #expect(rendered.hasPrefix("1970-01-12"))
        #expect(rendered.contains("search"))
        #expect(!rendered.contains("\n"), "an event is one line, whatever it carries")
    }

    @Test func asearchCarriesWhatWasTypedAndWhatCameBack() {
        let rendered = line(.search(query: "fire", results: 3, duration: .milliseconds(12)))
        #expect(rendered.contains("\"fire\""))
        #expect(rendered.contains("3"))
        #expect(rendered.contains("12 ms"))
    }

    /// The environment is recorded as names. A value never reaches the logger
    /// at all — that is the first of redaction's three layers, and it is
    /// enforced by this type having nowhere to put one.
    @Test func arunNamesItsEnvironmentKeysAndNeverTheirValues() {
        let rendered = line(
            .run(
                plugin: "demo.probe",
                executable: "/usr/bin/curl",
                arguments: ["-s", "https://example.com"],
                environmentKeys: ["PATH", "PIUM_SECRET_TOKEN"]
            )
        )
        #expect(rendered.contains("PIUM_SECRET_TOKEN"))
        #expect(rendered.contains("/usr/bin/curl"))
        #expect(rendered.contains("https://example.com"))
    }

    @Test func afinishedRunSaysHowItEnded() {
        #expect(line(.finished(plugin: "demo.probe", ending: .exited(0), output: "", error: ""))
            .contains("exited 0"))
        #expect(line(.finished(plugin: "demo.probe", ending: .timedOut, output: "", error: ""))
            .contains("timed out"))
        #expect(line(.finished(plugin: "demo.probe", ending: .cancelled, output: "", error: ""))
            .contains("cancelled"))
    }

    /// A command's output is many lines and an event is one, so the newlines
    /// become visible rather than structural. Otherwise one `echo` of a
    /// multi-line file turns the log into something no `grep` can read.
    @Test func multiLineOutputStaysOnOneLine() {
        let rendered = line(
            .finished(plugin: "demo.probe", ending: .exited(0), output: "one\ntwo", error: "")
        )
        #expect(!rendered.contains("\n"))
        #expect(rendered.contains("one\\ntwo"))
    }

    @Test func areloadCountsWhatLoadedAndWhatDidNot() {
        #expect(line(.pluginsReloaded(count: 7, invalid: 2)).contains("7"))
        #expect(line(.pluginsReloaded(count: 7, invalid: 2)).contains("2"))
    }

    @Test func thelauncherSaysWhichWayItWent() {
        #expect(line(.launcher(.opened)).contains("opened"))
        #expect(line(.launcher(.dismissed)).contains("dismissed"))
    }
}
