import Testing
import Foundation
@testable import Pium

@Suite("Execution manager")
@MainActor
struct ExecutionManagerTests {
    private func makeDirectory() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func record(
        executable: String,
        arguments: [String] = [],
        configuration: [PluginConfigurationField] = [],
        timeoutSeconds: Int? = nil,
        in directory: URL
    ) -> PluginRecord {
        let manifest = PluginManifest(
            schemaVersion: 1,
            id: "demo.probe",
            name: "Probe",
            description: nil,
            keywords: [],
            aliases: [],
            icon: nil,
            input: PluginInput(mode: .optional, placeholder: nil),
            command: PluginCommand(
                executable: executable, arguments: arguments, workingDirectory: nil
            ),
            configuration: configuration,
            output: PluginOutput(mode: .silent),
            timeoutSeconds: timeoutSeconds,
            confirmBeforeRun: nil
        )
        return PluginRecord(
            fileURL: directory.appending(path: "probe.pium.json"),
            manifest: manifest,
            diagnostic: nil
        )
    }

    private func manager() -> ExecutionManager {
        ExecutionManager(
            configuration: PluginConfigurationStore(
                defaults: UserDefaults(suiteName: UUID().uuidString)!
            ),
            secrets: InMemorySecretStore(secrets: [:]),
            searchPaths: ["/usr/bin", "/bin"]
        )
    }

    /// Waits for a record to reach a final state rather than sleeping a fixed
    /// amount, so a slow machine does not turn into a flaky test.
    private func finalState(
        of id: UUID,
        in manager: ExecutionManager,
        timeout: Duration = .seconds(10)
    ) async throws -> ExecutionRecord.State {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let state = manager.records[id]?.state, state != .running { return state }
            try await Task.sleep(for: .milliseconds(50))
        }
        return manager.records[id]?.state ?? .running
    }

    @Test func asuccessfulRunEndsFinished() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = manager()

        let id = try manager.run(record(executable: "echo", arguments: ["hola"], in: directory), input: "").get()
        #expect(try await finalState(of: id, in: manager) == .finished(exitCode: 0))
    }

    @Test func anUnresolvableExecutableFailsBeforeAnyProcessExists() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = manager()

        guard case .failure(let failure) = manager.run(
            record(executable: "definitely-not-a-real-tool", in: directory), input: ""
        ) else {
            Issue.record("An unresolvable executable must fail before running")
            return
        }
        #expect(
            failure == .executableNotFound(
                name: "definitely-not-a-real-tool", searched: ["/usr/bin", "/bin"]
            )
        )
        #expect(manager.records.isEmpty, "A run that never started leaves no record")
    }

    /// PRD §11: one active process. The refusal names the plugin holding the
    /// slot, so 5b can offer its cancellation in the same breath.
    @Test func asecondRunIsRefusedWhileOneIsActive() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = manager()

        let first = try manager.run(record(executable: "sleep", arguments: ["30"], in: directory), input: "").get()
        guard case .failure(let failure) = manager.run(
            record(executable: "echo", in: directory), input: ""
        ) else {
            Issue.record("A second run must be refused")
            return
        }
        #expect(failure == .alreadyRunning(plugin: "Probe"))
        manager.cancel(first)
    }

    @Test func theSlotIsFreeAgainOnceTheFirstFinishes() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = manager()

        let first = try manager.run(record(executable: "echo", in: directory), input: "").get()
        _ = try await finalState(of: first, in: manager)
        #expect(throws: Never.self) {
            _ = try manager.run(record(executable: "echo", in: directory), input: "").get()
        }
    }

    @Test func acancelledRunEndsCancelled() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = manager()

        let id = try manager.run(record(executable: "sleep", arguments: ["30"], in: directory), input: "").get()
        try await Task.sleep(for: .milliseconds(300))
        manager.cancel(id)
        #expect(try await finalState(of: id, in: manager) == .cancelled)
    }

    @Test func arunPastItsTimeoutEndsTimedOut() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = manager()

        let id = try manager.run(
            record(executable: "sleep", arguments: ["30"], timeoutSeconds: 1, in: directory),
            input: ""
        ).get()
        #expect(try await finalState(of: id, in: manager) == .timedOut)
    }

    @Test func theInputReachesTheCommandAsOneArgument() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = manager()

        let id = try manager.run(
            record(executable: "echo", arguments: ["{{input}}"], in: directory), input: "a b c"
        ).get()
        _ = try await finalState(of: id, in: manager)
        #expect(manager.records[id]?.standardOutput == "a b c\n")
    }

    @Test func amissingRequiredValueFailsBeforeRunning() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = manager()

        let field = PluginConfigurationField(
            key: "token", label: "Token", type: .secret,
            required: true, environmentVariable: "PIUM_SECRET_TOKEN"
        )
        guard case .failure(let failure) = manager.run(
            record(executable: "echo", configuration: [field], in: directory), input: ""
        ) else {
            Issue.record("A missing required secret must stop the run")
            return
        }
        #expect(failure == .missingConfiguration(field: "token"))
    }
}
