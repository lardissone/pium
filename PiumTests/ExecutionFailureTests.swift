import Testing
import Foundation
@testable import Pium

@Suite("Execution failure messages")
struct ExecutionFailureTests {
    /// A user who downloaded a plugin cannot act on "posix_spawn returned 1".
    /// They can act on being told the file is quarantined.
    @Test func aquarantinedExecutableSaysSoAndSaysWhatToDo() {
        let message = ExecutionFailure.quarantined(path: "/tmp/run.sh").message
        #expect(message.contains("/tmp/run.sh"))
        #expect(message.lowercased().contains("quarantine"))
        #expect(message.contains("xattr"))
    }

    /// The file is there; it failed to decode or validate. Saying "no file"
    /// sends its author looking for the wrong thing.
    @Test func aninvalidManifestIsNotReportedAsAMissingFile() {
        let message = ExecutionFailure.invalidManifest(path: "/tmp/probe.pium.json").message
        #expect(!message.lowercased().contains("no file"))
        #expect(message.contains("/tmp/probe.pium.json"))
    }

    /// A key the catalog has no entry for is not an error: `String(localized:)`
    /// hands back the key itself, which is non-empty and would satisfy any
    /// "has a message" check while the user reads `execution.failure.spawnFailed 2`.
    /// So the bar is the rendered sentence: every key here lives under the
    /// `execution.failure.` namespace, and no rendered message does.
    @Test func everyFailureRendersItsCatalogEntryAndNamesItsSubject() {
        let failures: [(ExecutionFailure, subject: String)] = [
            (.executableNotFound(name: "tool", searched: ["/bin"]), "tool"),
            (.executableMissing(path: "/tmp/x"), "/tmp/x"),
            (.executableNotExecutable(path: "/tmp/x"), "/tmp/x"),
            (.quarantined(path: "/tmp/x"), "/tmp/x"),
            (.invalidManifest(path: "/tmp/x.pium.json"), "/tmp/x.pium.json"),
            (.missingConfiguration(field: "token"), "token"),
            (.secretUnavailable(field: "token"), "token"),
            (.alreadyRunning(plugin: "Probe"), "Probe"),
            (.spawnFailed(code: 2), "2"),
        ]
        for (failure, subject) in failures {
            let message = failure.message
            #expect(
                !message.hasPrefix("execution.failure."),
                "\(failure) shows its lookup key instead of a message: \(message)"
            )
            #expect(message.contains(subject), "\(failure) never names \(subject): \(message)")
        }
    }

    /// The searched paths are what makes "not found" actionable, per PRD §10.4.
    @Test func anUnresolvableExecutableNamesWhereItLooked() {
        let message = ExecutionFailure.executableNotFound(
            name: "ha", searched: ["/opt/homebrew/bin", "/usr/bin"]
        ).message
        #expect(message.contains("/opt/homebrew/bin"))
        #expect(message.contains("/usr/bin"))
    }
}
