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

    @Test func everyFailureHasANonEmptyMessage() {
        let failures: [ExecutionFailure] = [
            .executableNotFound(name: "tool", searched: ["/bin"]),
            .executableMissing(path: "/tmp/x"),
            .executableNotExecutable(path: "/tmp/x"),
            .quarantined(path: "/tmp/x"),
            .invalidManifest(path: "/tmp/x.pium.json"),
            .missingConfiguration(field: "token"),
            .secretUnavailable(field: "token"),
            .alreadyRunning(plugin: "Probe"),
            .spawnFailed(code: 2),
        ]
        for failure in failures {
            #expect(!failure.message.isEmpty, "\(failure) has no message")
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
