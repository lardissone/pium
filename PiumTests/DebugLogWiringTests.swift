import Testing
import Foundation
@testable import Pium

@Suite("Debug log wiring")
@MainActor
struct DebugLogWiringTests {
    private func makeDirectory() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Points the facade at a directory of this test's own, with a session
    /// that is live, and puts the shared seams back afterwards.
    private func withRecording(
        into directory: URL,
        _ body: () async throws -> Void
    ) async rethrows {
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.debugLoggingExpiry = Date().addingTimeInterval(60)
        let previousStore = DebugLog.store
        let previousPreferences = DebugLog.preferences
        DebugLog.store = DebugLogStore(directory: directory, now: { Date() })
        DebugLog.preferences = preferences
        defer {
            DebugLog.store = previousStore
            DebugLog.preferences = previousPreferences
        }
        try await body()
    }

    /// A ranking bug — "this should have been first" — is the one most often
    /// reported and the one a log without the query cannot explain.
    @Test func asearchRecordsWhatWasTypedAndHowManyCameBack() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await withRecording(into: directory) {
            let coordinator = SearchCoordinator(
                providers: [
                    StubProvider(
                        kind: .application,
                        results: [
                            stubResult("Firefox", kind: .application, score: 0.9),
                            stubResult("Fireworks", kind: .application, score: 0.8),
                        ]
                    )
                ],
                frecency: FrecencyStore(
                    fileURL: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
                )
            )
            for await _ in coordinator.search("fire") {}
            try await Task.sleep(for: .milliseconds(200))

            let exported = String(decoding: try await DebugLog.store.export(), as: UTF8.self)
            #expect(exported.contains("search"))
            #expect(exported.contains("\"fire\""), "the query is what makes a ranking bug legible")
            #expect(exported.contains("2 results"))
        }
    }

    /// The phase's whole promise, at the level of one run: the log says what
    /// ran and what came back, and the token that made it work is nowhere in
    /// it — not in the environment, and not in the output the command printed
    /// it into.
    @Test func arunIsRecordedAndItsSecretIsNot() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try await withRecording(into: directory) {
            let manager = ExecutionManager(
                configuration: PluginConfigurationStore(
                    defaults: UserDefaults(suiteName: UUID().uuidString)!
                ),
                secrets: InMemorySecretStore(secrets: ["demo.probe/token": "hunter2"]),
                searchPaths: { ["/usr/bin", "/bin"] }
            )
            let manifest = PluginManifest(
                schemaVersion: 1,
                id: "demo.probe",
                name: "Probe",
                description: nil,
                keywords: [],
                aliases: [],
                icon: nil,
                input: PluginInput(mode: .none, placeholder: nil),
                // The command prints the secret it was handed, which is exactly
                // the leak the point-of-use layer cannot reach.
                command: PluginCommand(
                    executable: "sh",
                    arguments: ["-c", "echo \"$PIUM_SECRET_TOKEN\""],
                    workingDirectory: nil
                ),
                configuration: [
                    PluginConfigurationField(
                        key: "token",
                        label: "Token",
                        type: .secret,
                        required: true,
                        environmentVariable: "PIUM_SECRET_TOKEN"
                    )
                ],
                output: PluginOutput(mode: .toast),
                timeoutSeconds: nil,
                confirmBeforeRun: nil
            )
            let id = try manager.run(
                PluginRecord(
                    fileURL: URL(filePath: "/tmp/probe.pium.json"),
                    manifest: manifest,
                    diagnostic: nil
                ),
                input: ""
            ).get()

            let deadline = ContinuousClock.now + .seconds(10)
            while manager.records[id]?.isRunning != false, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            try await Task.sleep(for: .milliseconds(300))

            let exported = String(decoding: try await DebugLog.store.export(), as: UTF8.self)
            #expect(exported.contains("demo.probe"), "the run itself must be diagnosable")
            #expect(
                exported.contains("PIUM_SECRET_TOKEN"),
                "the variable's name is what makes it diagnosable"
            )
            #expect(
                !exported.contains("hunter2"),
                "the value must not survive anywhere in the log"
            )
            // Without this the test would pass just as happily if the command
            // had printed nothing at all, which proves nothing about scrubbing.
            #expect(
                exported.contains(SecretRedaction.marker),
                "the command did print the token, and the marker is what replaced it"
            )
        }
    }
}
