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

    /// How many descriptors this process holds open. `/dev/fd` lists exactly
    /// that on Darwin, which is the cheapest way to ask.
    private func openDescriptorCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0
    }

    /// A finished run must hand its two pipe descriptors back by the time it
    /// returns. Anything that outlives the run while still holding a read end
    /// — a timer, a watchdog, a task nobody cancels — pins two descriptors per
    /// run against a 256 soft limit, and a user doing nothing more exotic than
    /// running commands in a loop hits `EMFILE` on descriptors that belong to
    /// runs which finished long ago.
    ///
    /// The count is taken after a warm-up run so that descriptors the runtime
    /// opens once on first use are not attributed to the runs being measured,
    /// and the tolerance is wide because this suite runs its tests in parallel:
    /// a concurrent run holds its own two descriptors while it lasts. Sixty
    /// runs leak a hundred and twenty descriptors if they leak at all, which is
    /// far outside that noise.
    @Test func afinishedRunReleasesItsPipeDescriptors() async {
        _ = await ProcessRunner().run(request("/bin/echo", ["warm"]), cancellation: .init())

        let before = openDescriptorCount()
        for _ in 0..<60 {
            _ = await ProcessRunner().run(request("/bin/echo", ["x"]), cancellation: .init())
        }
        let after = openDescriptorCount()

        #expect(
            after - before < 40,
            "Sixty finished runs left \(after - before) descriptors open"
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
        #expect(outcome.standardOutput.utf8.count <= ProcessRunner.outputCap)
        #expect(outcome.standardOutput.allSatisfy { $0 == "x" })
        #expect(outcome.wasTruncated == true)
    }

    /// The cap is a byte count and the output is text: a character that
    /// straddles it must be dropped whole rather than decoded into U+FFFD.
    @Test func truncationDoesNotSplitACharacter() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Three-byte characters, so the cap lands mid-character.
        let url = try script("for i in $(seq 1 40000); do printf '€'; done", in: directory)

        let outcome = await ProcessRunner().run(
            request(url.path, in: directory), cancellation: .init()
        )
        #expect(outcome.wasTruncated)
        #expect(!outcome.standardOutput.contains("\u{FFFD}"))
        #expect(outcome.standardOutput.allSatisfy { $0 == "€" })
    }

    /// Every length of dangling byte the cap can leave, not just the one the
    /// obvious fixture happens to produce.
    ///
    /// How many bytes dangle is `(cap - prefix) % width` for a run of
    /// `width`-byte characters, so a few ASCII characters in front of the run
    /// choose it: 64 KB of three-byte `€` leaves one, two ASCII first leaves
    /// two, and one ASCII in front of four-byte characters leaves three. A
    /// UTF-8 sequence is at most four bytes, so those are all of them.
    ///
    /// The assertion is the same in every case: whatever survives decodes to
    /// characters the command actually printed, never to U+FFFD.
    @Test(arguments: [("€", 0, 1), ("€", 2, 2), ("😀", 1, 3)])
    func aDanglingByteOfAnyLengthIsDroppedWhole(
        character: String, prefix: Int, expectedDangle: Int
    ) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let width = character.utf8.count
        #expect(
            (ProcessRunner.outputCap - prefix) % width == expectedDangle,
            "Fixture no longer produces the \(expectedDangle)-byte dangle it is here to cover"
        )
        let url = try script(
            """
            printf '%\(prefix)s' ''
            for i in $(seq 1 30000); do printf '\(character)'; done
            """,
            in: directory
        )

        let outcome = await ProcessRunner().run(
            request(url.path, in: directory), cancellation: .init()
        )
        #expect(outcome.wasTruncated)
        #expect(!outcome.standardOutput.contains("\u{FFFD}"))
        #expect(outcome.standardOutput.dropFirst(prefix).allSatisfy { String($0) == character })
    }

    /// Bytes that are not UTF-8 at all — a command printing binary, which
    /// nothing stops it from doing. Dropping up to three trailing bytes
    /// cannot rescue this, so the decoder's replacement characters are the
    /// honest answer; what matters is that the run still completes and
    /// reports the rest.
    @Test func invalidUtf8DoesNotLoseTheRunOrTheValidTextAroundIt() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try script("printf 'before\\377\\376after'", in: directory)

        let outcome = await ProcessRunner().run(
            request(url.path, in: directory), cancellation: .init()
        )
        #expect(outcome.ending == .exited(0))
        #expect(outcome.wasTruncated == false)
        #expect(outcome.standardOutput.hasPrefix("before"))
        #expect(outcome.standardOutput.hasSuffix("after"))
    }

    /// The two streams arrive as two strings, neither folded into the other:
    /// stderr is where a failing command explains itself, and the interface
    /// shows it on its own.
    @Test func itReportsStandardErrorSeparatelyFromOutput() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try script("echo out; echo err >&2", in: directory)

        let outcome = await ProcessRunner().run(request(url.path, in: directory), cancellation: .init())
        #expect(outcome.ending == .exited(0))
        #expect(outcome.standardOutput == "out\n")
        #expect(outcome.standardError == "err\n")
        #expect(outcome.wasTruncated == false)
    }

    /// Either stream reaching the cap makes the run truncated. A command that
    /// says nothing on stdout and floods stderr is the ordinary shape of a
    /// failure, so the flag cannot be a property of stdout alone.
    @Test func errorPastTheCapKeepsTheBeginningAndMarksTheRunTruncated() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // 200 KB, comfortably past the 64 KB cap.
        let url = try script("for i in $(seq 1 200000); do printf 'x'; done >&2", in: directory)

        let outcome = await ProcessRunner().run(request(url.path, in: directory), cancellation: .init())
        #expect(outcome.ending == .exited(0))
        #expect(outcome.standardOutput == "")
        #expect(outcome.standardError.count == ProcessRunner.outputCap)
        #expect(outcome.standardError.allSatisfy { $0 == "x" })
        #expect(outcome.wasTruncated == true)
    }

    /// Parks blocking work on `DispatchQueue.global(qos: .utility)` until a
    /// fresh item cannot get a worker, and returns the closure that lets it
    /// all go again.
    ///
    /// Saturation is measured rather than assumed: libdispatch grows the pool
    /// when it notices its workers are blocked, so no fixed number of parked
    /// items means "full" on every machine — a ten-core developer Mac takes
    /// several times what a two-core CI runner does. Probing stops as soon as
    /// the pool stops handing out workers, which keeps this as cheap as the
    /// machine allows.
    private func saturateSharedQueue() -> () -> Void {
        let release = DispatchSemaphore(value: 0)
        var parked = 0
        while parked < 1024 {
            for _ in 0..<32 {
                DispatchQueue.global(qos: .utility).async { release.wait() }
            }
            parked += 32
            let probe = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).async { probe.signal() }
            if probe.wait(timeout: .now() + 0.5) == .timedOut { break }
        }
        return { for _ in 0..<parked { release.signal() } }
    }

    /// PIUM-109: what a command printed must reach the caller even when every
    /// worker on the process-wide dispatch pool is busy.
    ///
    /// A run's three blocking waits — reaping the child and draining each of
    /// its two streams — each occupy a worker for the whole life of the
    /// command, so a handful of concurrent runs is enough to fill that pool
    /// with Pium's own work. Anything that then waits on a *fourth* worker
    /// waits for a slot, not for the child: `awaitDrains` would time its
    /// one-second window out against a drain that had not been given a thread
    /// yet and report a clean exit with both streams empty, which is a wrong
    /// answer rather than a slow one. Phase 5b puts that answer in front of
    /// the user, so nothing downstream can tell it apart from a command that
    /// genuinely printed nothing.
    ///
    /// Holding the pool for the whole run, rather than for a fixed interval,
    /// is what makes this a statement about the design instead of about the
    /// margin: it passes only if a run needs no share of that pool at all.
    @Test(.timeLimit(.minutes(1)))
    func abusyMachineStillReportsWhatTheCommandPrinted() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try script("echo out; echo err >&2", in: directory)

        let releaseSharedQueue = saturateSharedQueue()
        defer { releaseSharedQueue() }

        let outcome = await ProcessRunner().run(request(url.path, in: directory), cancellation: .init())

        #expect(outcome.ending == .exited(0))
        #expect(outcome.standardOutput == "out\n")
        #expect(outcome.standardError == "err\n")
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
    /// The grandchild writes in two phases, each defending a different
    /// property of this test.
    ///
    /// Phase 1 is a long, entirely unpaced burst (2,000,000 writes, several
    /// seconds on a typical machine). A reader merely parked inside a
    /// blocking read is the benign half of the close-after-abandon race: a
    /// close lands cleanly there. The dangerous half is a reader caught
    /// between two reads, right where an earlier version of this fix landed
    /// a forced close and crashed the app instead of hanging it — and an
    /// unpaced burst is what gives that half a real chance to happen,
    /// because for as long as it runs the reader is cycling through reads
    /// rather than blocked on any single one. It starts the instant this
    /// subshell does, which is also when `drain`'s roughly one-second grace
    /// period starts counting down from, so the burst reliably overlaps the
    /// window that matters. (A version of this fixture that paced every
    /// write instead reproduced nothing: it left the reader parked for
    /// nearly all of it.)
    ///
    /// Phase 2 is 35 iterations of one write followed by a real two-second
    /// sleep. Its floor — 70 seconds, from the sleeps alone — is what
    /// actually outlasts the time limit below (the coarsest swift-testing
    /// allows is whole minutes), and unlike phase 1's, that floor cannot be
    /// shortened by a faster machine: `sleep` is a wall-clock wait, not a
    /// function of how fast this machine can run a shell loop. (A version
    /// of this fixture that used only phase 1's kind of burst, sized to
    /// take "about a minute", reproduced the crash fine but could in
    /// principle finish under the time limit on a fast enough machine,
    /// silently passing a hang regression instead of catching it.)
    ///
    /// Without the fix, this run waited for the grandchild regardless of
    /// which phase it was in, so a regression back to that state still
    /// fails here instead of merely running long and passing once the
    /// grandchild exits on its own.
    @Test(.timeLimit(.minutes(1)))
    func agrandchildHoldingStdoutDoesNotHangTheRun() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appending(path: "grandchild.pid")
        let url = try script(
            """
            (
              i=0
              while [ $i -lt 2000000 ]; do
                printf x
                i=$((i+1))
              done
              i=0
              while [ $i -lt 35 ]; do
                printf x
                sleep 2
                i=$((i+1))
              done
            ) &
            echo $! > \(pidFile.path)
            echo done
            """,
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

    /// Two things are true at once — the command could not start, and the user
    /// asked for it to stop — and only one of them is worth saying. Somebody
    /// who pressed Cancel is not told a spawn failed; that reads as a fault in
    /// the plugin they just chose to abandon.
    @Test func acancelDuringAFailedSpawnIsReportedAsCancelled() async {
        let cancellation = ProcessRunner.Cancellation()
        cancellation.cancel()
        let outcome = await ProcessRunner().run(
            request("/bin/definitely-not-here"), cancellation: cancellation
        )
        #expect(outcome.ending == .cancelled)
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
    /// pgid for an unrelated process by then. A grandchild is left alive in
    /// the group after `run` returns, `cancel()` is called late, and the
    /// grandchild must still be alive afterward: before `Cancellation.detach`
    /// existed, `cancel()` would still call `child.signalGroup(SIGTERM)` on
    /// this exact scenario; after, `child` is nil and the call is a no-op.
    ///
    /// This cannot actually fail under Xcode's own test host, and that is
    /// worth stating plainly rather than leaving to be discovered: the host
    /// itself has `SIGTERM` set to be ignored, and POSIX propagates an
    /// ignored disposition across every `exec` in the chain, so
    /// `kill(-pid, SIGTERM)` is a no-op for the whole process group
    /// regardless of whether `detach` ran — confirmed by disabling `detach`
    /// and re-running this exact test, which still passed. Kept anyway,
    /// because it is the correct, timing-independent proof of `detach`'s
    /// effect everywhere else this suite runs (a plain `swift test`, any CI
    /// that is not this specific host, a command-line build) — dropping it
    /// would leave that guarantee completely uncovered, and rewriting it
    /// around `SIGKILL` instead would reintroduce a timing dependency this
    /// design specifically avoids.
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
