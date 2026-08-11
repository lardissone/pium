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
        workingDirectory: String? = nil,
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
                executable: executable, arguments: arguments, workingDirectory: workingDirectory
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

    /// The slot is a slot, not a one-shot: finishing a run has to hand it
    /// back. Both runs are asserted individually, because a second run that
    /// never started would leave the first one's record as the only evidence
    /// and a count alone would not notice.
    @Test func theSlotIsFreeAgainOnceARunFinishes() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = manager()

        let first = try manager.run(
            record(executable: "echo", arguments: ["one"], in: directory), input: ""
        ).get()
        #expect(try await finalState(of: first, in: manager) == .finished(exitCode: 0))
        #expect(manager.activeRecord == nil, "A finished run must not still hold the slot")

        let second = try manager.run(
            record(executable: "echo", arguments: ["two"], in: directory), input: ""
        ).get()
        #expect(second != first)
        #expect(try await finalState(of: second, in: manager) == .finished(exitCode: 0))
    }

    /// A refused second run must change nothing about the first: the menubar
    /// reads `activeRecord` to name what its Cancel entry would stop, so a
    /// refusal that disturbed it would leave Cancel offering to stop a run
    /// that was never started.
    @Test func arefusedSecondRunLeavesTheFirstHoldingTheSlot() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = manager()

        let first = try manager.run(
            record(executable: "sleep", arguments: ["30"], in: directory), input: ""
        ).get()
        defer { manager.cancel(first) }
        #expect(manager.activeRecord?.id == first)

        guard case .failure(let failure) = manager.run(
            record(executable: "echo", arguments: ["two"], in: directory), input: ""
        ) else {
            Issue.record("A second run must be refused while the slot is held")
            return
        }
        #expect(failure == .alreadyRunning(plugin: "Probe"))
        #expect(
            manager.activeRecord?.id == first,
            "The refusal must leave the first run holding the slot"
        )
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

    /// A double space in the input is what makes this discriminate: `echo`
    /// prints it back verbatim only if the whole string reached argv as one
    /// element. Splitting it into separate arguments first — the bug this
    /// guards against — collapses the double space to one when `echo` joins
    /// its arguments back together, so `"a b\n"` here would mean the input
    /// was not kept whole.
    @Test func theInputReachesTheCommandAsOneArgument() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = manager()

        let id = try manager.run(
            record(executable: "echo", arguments: ["{{input}}"], in: directory), input: "a  b"
        ).get()
        _ = try await finalState(of: id, in: manager)
        #expect(manager.records[id]?.standardOutput == "a  b\n")
    }

    /// PRD §10.4: an absolute `workingDirectory` names a directory outright,
    /// the same way `ExecutableResolver` treats an absolute executable path —
    /// it must not be reinterpreted as relative to the plugin's own folder.
    @Test func anAbsoluteWorkingDirectoryIsNotTreatedAsRelativeToThePluginFolder() async throws {
        let pluginDirectory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: pluginDirectory) }
        let workingDirectory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let manager = manager()

        let id = try manager.run(
            record(executable: "pwd", workingDirectory: workingDirectory.path, in: pluginDirectory),
            input: ""
        ).get()
        #expect(try await finalState(of: id, in: manager) == .finished(exitCode: 0))
        let output = manager.records[id]?.standardOutput ?? ""
        // Compared as `.path` strings after resolving symlinks, not as `URL`s:
        // `pwd` reports the kernel's physical path (through /private), the same
        // reason `ChildProcessTests.theWorkingDirectoryIsTheOneGiven` does this.
        #expect(
            URL(filePath: output.trimmingCharacters(in: .newlines)).resolvingSymlinksInPath().path
                == workingDirectory.resolvingSymlinksInPath().path
        )
    }

    /// Records are bounded: each one holds up to two 64 KB captures, and a
    /// menubar app that keeps every run it ever started keeps every byte those
    /// runs ever printed. What survives is the recent end, which is what the
    /// interface asks about.
    @Test func onlyTheMostRecentRunsAreRemembered() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = manager()

        var started: [UUID] = []
        for _ in 0..<(ExecutionManager.historyLimit + 5) {
            let id = try manager.run(record(executable: "echo", in: directory), input: "").get()
            _ = try await finalState(of: id, in: manager)
            started.append(id)
        }

        #expect(manager.records.count == ExecutionManager.historyLimit)
        #expect(manager.records[started[0]] == nil, "The oldest run is still remembered")
        #expect(manager.records[try #require(started.last)] != nil, "The newest run was forgotten")
    }

    /// Forgetting old runs must not disturb the single slot: the run in flight
    /// is the one `activeRecord` names, and it is what a second run is refused
    /// for. Both answers come from the same collection eviction writes to.
    @Test func aRunInFlightIsStillTheActiveOneAfterTheHistoryHasChurned() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = manager()

        for _ in 0..<(ExecutionManager.historyLimit + 5) {
            let id = try manager.run(record(executable: "echo", in: directory), input: "").get()
            _ = try await finalState(of: id, in: manager)
        }

        let inFlight = try manager.run(
            record(executable: "sleep", arguments: ["30"], in: directory), input: ""
        ).get()
        defer { manager.cancel(inFlight) }

        #expect(manager.records[inFlight]?.state == .running)
        #expect(manager.activeRecord?.id == inFlight)
        #expect(manager.records.count == ExecutionManager.historyLimit)
        guard case .failure(let failure) = manager.run(
            record(executable: "echo", in: directory), input: ""
        ) else {
            Issue.record("A second run must still be refused")
            return
        }
        #expect(failure == .alreadyRunning(plugin: "Probe"))
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
