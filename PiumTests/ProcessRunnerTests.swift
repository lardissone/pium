import Testing
import Foundation
@testable import Pium

@Suite("Process runner")
struct ProcessRunnerTests {
    private func makeDirectory() throws -> URL {
        let root = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func script(_ body: String, in directory: URL) throws -> URL {
        let url = directory.appending(path: "script.sh")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func request(
        _ executable: String,
        _ arguments: [String] = [],
        in directory: URL = URL(filePath: "/tmp"),
        timeoutSeconds: Int? = nil
    ) -> ExecutionRequest {
        ExecutionRequest(
            executable: URL(filePath: executable),
            arguments: arguments,
            workingDirectory: directory,
            environment: ["PATH": "/usr/bin:/bin"],
            timeoutSeconds: timeoutSeconds
        )
    }

    @Test func itReportsOutputAndTheExitCode() async {
        let outcome = await ProcessRunner().run(
            request("/bin/echo", ["hola"]), cancellation: .init()
        )
        #expect(outcome.ending == .exited(0))
        #expect(outcome.standardOutput == "hola\n")
        #expect(outcome.wasTruncated == false)
    }

    /// Past the cap the beginning is kept and reading continues, because a
    /// reader that stops draining blocks the child on its next write — a
    /// truncated output would become a hung command.
    @Test func outputPastTheCapKeepsTheBeginningAndStillFinishes() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // 200 KB, comfortably past the 64 KB cap.
        let url = try script("for i in $(seq 1 200000); do printf 'x'; done", in: directory)

        let outcome = await ProcessRunner().run(request(url.path, in: directory), cancellation: .init())
        #expect(outcome.ending == .exited(0))
        #expect(outcome.standardOutput.count == ProcessRunner.outputCap)
        #expect(outcome.standardOutput.allSatisfy { $0 == "x" })
        #expect(outcome.wasTruncated == true)
    }

    @Test func atimeoutEndsTheRunAsTimedOut() async throws {
        let outcome = await ProcessRunner().run(
            request("/bin/sleep", ["30"], timeoutSeconds: 1), cancellation: .init()
        )
        #expect(outcome.ending == .timedOut)
    }

    @Test func acancellationEndsTheRunAsCancelled() async throws {
        let cancellation = ProcessRunner.Cancellation()
        async let outcome = ProcessRunner().run(request("/bin/sleep", ["30"]), cancellation: cancellation)
        try await Task.sleep(for: .milliseconds(300))
        cancellation.cancel()
        #expect(await outcome.ending == .cancelled)
    }

    /// PRD §11: a user's cancellation is reported as cancelled, never as a
    /// failure, however the process actually died.
    @Test func acancelledRunIsNotReportedAsAFailure() async throws {
        let cancellation = ProcessRunner.Cancellation()
        async let outcome = ProcessRunner().run(request("/bin/sleep", ["30"]), cancellation: cancellation)
        try await Task.sleep(for: .milliseconds(300))
        cancellation.cancel()
        let ending = await outcome.ending
        #expect(ending != .exited(143))
        #expect(ending == .cancelled)
    }

    /// A grandchild the process leaves running — a script that starts a
    /// background daemon and exits — keeps the pipe's write end open long
    /// after the process this run spawned has been reaped. `run` must not
    /// wait on an EOF that will not arrive until that grandchild, which
    /// nobody asked it to track, eventually finishes on its own.
    ///
    /// The grandchild writes continuously — a tight, unpaced loop, not a
    /// sleep between writes — rather than sitting silent. A reader merely
    /// parked inside a blocking read is the benign half of this race: a
    /// close lands cleanly there. The dangerous half is a reader caught
    /// between two reads, right where an earlier version of this fix landed
    /// a forced close and crashed the app instead of hanging it; a tight
    /// write loop is what gives that half a real chance to happen, because
    /// the reader spends most of its time cycling through reads rather than
    /// blocked on any single one. The grandchild's total run time (tens of
    /// seconds at this write rate) deliberately outlasts the time limit
    /// below (the coarsest swift-testing allows is whole minutes): without
    /// the fix, this run waited for the grandchild regardless of whether it
    /// was silent or noisy, so a regression back to that state still fails
    /// here instead of merely running long and passing once the grandchild
    /// exits on its own.
    @Test(.timeLimit(.minutes(1)))
    func agrandchildHoldingStdoutDoesNotHangTheRun() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appending(path: "grandchild.pid")
        let url = try script(
            "(i=0; while [ $i -lt 20000000 ]; do printf x; i=$((i+1)); done) &\n"
                + "echo $! > \(pidFile.path)\necho done",
            in: directory
        )

        let outcome = await ProcessRunner().run(request(url.path, in: directory), cancellation: .init())

        if let text = try? String(contentsOf: pidFile, encoding: .utf8),
            let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(pid, SIGKILL)
        }

        #expect(outcome.ending == .exited(0))
        // Not an exact match: "done" and the grandchild's own "tick" lines
        // race for the pipe, and either may land first.
        #expect(outcome.standardOutput.contains("done"))
    }

    /// PRD §11's grace-then-`SIGKILL` escalation applies to a cancellation
    /// whether or not a timeout was declared. A command that ignores
    /// `SIGTERM` must still die within the cancellation's own grace period,
    /// not linger until a much longer timeout eventually runs its course.
    @Test func acancellationStillEscalatesToSigkillWhenATimeoutIsSet() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try script("trap '' TERM\nsleep 30", in: directory)

        let cancellation = ProcessRunner.Cancellation()
        let clock = ContinuousClock()
        let start = clock.now
        async let outcome = ProcessRunner().run(
            request(url.path, in: directory, timeoutSeconds: 30), cancellation: cancellation
        )
        try await Task.sleep(for: .milliseconds(300))
        cancellation.cancel()
        let ending = await outcome.ending
        let elapsed = clock.now - start

        #expect(ending == .cancelled)
        #expect(elapsed < .seconds(10))
    }

    @Test func amissingExecutableIsReportedAsAFailedSpawn() async {
        let outcome = await ProcessRunner().run(
            request("/bin/definitely-not-here"), cancellation: .init()
        )
        #expect(outcome.ending == .failed(.spawnFailed(code: ENOENT)))
        #expect(outcome.standardOutput == "")
    }

    /// A signal that is neither the cancellation's nor the timeout's own
    /// escalation — here, the command sending one to itself — is reported as
    /// what it was, not folded into a bare exit code. `SIGKILL` rather than
    /// `SIGTERM`: it cannot be caught or ignored, so this cannot be confused
    /// with a disposition the test host happens to have set.
    @Test func asignalledProcessReportsWhichSignalKilledIt() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try script("kill -KILL $$", in: directory)

        let outcome = await ProcessRunner().run(request(url.path, in: directory), cancellation: .init())
        #expect(outcome.ending == .signalled(SIGKILL))
    }

    /// A cancel arriving after `run` has already returned must not reach the
    /// process group it already reaped — the kernel could have recycled that
    /// pgid for an unrelated process by then. Proven directly, without
    /// needing pid recycling or timing luck: a grandchild is left alive in
    /// the group after `run` returns, `cancel()` is called late, and the
    /// grandchild must still be alive afterward. Before `Cancellation.detach`
    /// existed, `cancel()` would still call `child.signalGroup(SIGTERM)` on
    /// this exact scenario; after, `child` is nil and the call is a no-op.
    @Test func alateCancelDoesNotReachAProcessGroupRunAlreadyReaped() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appending(path: "grandchild.pid")
        let url = try script("sleep 30 &\necho $! > \(pidFile.path)\necho done", in: directory)

        let cancellation = ProcessRunner.Cancellation()
        let outcome = await ProcessRunner().run(request(url.path, in: directory), cancellation: cancellation)
        #expect(outcome.ending == .exited(0))

        let text = try String(contentsOf: pidFile, encoding: .utf8)
        let pid = try #require(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        defer { kill(pid, SIGKILL) }
        #expect(kill(pid, 0) == 0, "The grandchild should still be alive before the late cancel")

        cancellation.cancel()
        try await Task.sleep(for: .milliseconds(500))

        #expect(
            kill(pid, 0) == 0,
            "A cancel arriving after run() returned must not reach the process group it already reaped"
        )
    }
}
