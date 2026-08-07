import Darwin
import Foundation

/// What to run.
struct ExecutionRequest: Sendable {
    let executable: URL
    let arguments: [String]
    let workingDirectory: URL
    let environment: [String: String]
    /// Absent means no timeout: PRD §10.4 makes it optional, and a global
    /// default would kill legitimate long commands.
    let timeoutSeconds: Int?
}

/// How a run ended, and what it printed.
struct ExecutionOutcome: Sendable, Equatable {
    enum Ending: Sendable, Equatable {
        case exited(Int32)
        case cancelled
        case timedOut
        /// Killed by a signal that was neither the cancellation's nor the
        /// timeout's escalation — a self-signal, a crash, or a `kill` from
        /// outside Pium altogether.
        case signalled(Int32)
        /// The process never started. Carries the reason `ChildProcess.spawn`
        /// gave rather than collapsing it to a bare failure code.
        case failed(ExecutionFailure)
    }

    let ending: Ending
    let standardOutput: String
    let standardError: String
    /// Whether either stream was cut at the cap, so a reader knows the text is
    /// a beginning rather than the whole story.
    let wasTruncated: Bool
}

/// Runs one request to completion: draining both streams under a cap, arming
/// the timeout, and turning however the process died into one outcome.
struct ProcessRunner {
    /// 64 KB per stream. Enough for any message meant for a person, small
    /// enough that a runaway command cannot grow Pium's memory without bound.
    static let outputCap = 64 * 1024

    /// The handle a caller keeps to stop a run in flight.
    ///
    /// A class because the caller holds it while `run` is already awaiting, and
    /// the two need to see the same state.
    final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var child: ChildProcess?
        private var isCancelled = false

        func cancel() {
            lock.lock()
            defer { lock.unlock() }
            isCancelled = true
            child?.signalGroup(SIGTERM)
        }

        fileprivate func attach(_ process: ChildProcess) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !isCancelled else { return false }
            child = process
            return true
        }

        /// Stops tracking the child once `run` has reaped it, so a signal
        /// arriving afterwards — a caller's late `cancel()`, or an escalation
        /// task that raced past its last suspension point — finds nothing to
        /// reach. Without this, `kill(-pid, …)` could land on a process group
        /// the kernel has since recycled for someone else.
        fileprivate func detach() {
            lock.lock()
            defer { lock.unlock() }
            child = nil
        }

        /// Signals the tracked child, gated on the same lock `detach` uses:
        /// a signal that starts before `detach` completes still reaches a
        /// live child, and one that starts after finds none. There is no
        /// window where a check succeeds but the signal itself arrives late.
        fileprivate func signal(_ signal: Int32) {
            lock.lock()
            defer { lock.unlock() }
            child?.signalGroup(signal)
        }

        fileprivate var wasCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return isCancelled
        }
    }

    /// Whether the timeout fired, written by the task that fires it and read
    /// once the process has been reaped.
    private final class Expiry: @unchecked Sendable {
        private let lock = NSLock()
        private var expired = false

        func markExpired() {
            lock.lock()
            expired = true
            lock.unlock()
        }

        var hasExpired: Bool {
            lock.lock()
            defer { lock.unlock() }
            return expired
        }
    }

    /// The grace `SIGTERM` gets before `SIGKILL`, per PRD §11. Applies to both
    /// a cancellation and a timeout, regardless of the other.
    private static let graceSeconds: Double = 2

    /// How long the drains may run once the process itself has been reaped,
    /// before this run gives up waiting on them and returns what they have
    /// kept so far. A grandchild the process left behind — a script that
    /// starts a daemon in the background — can keep holding a pipe's write
    /// end open long after the process we spawned is gone, and EOF never
    /// arrives on its own.
    private static let drainGraceSeconds: Double = 1

    /// How long a drain nobody is waiting on any more may keep reading
    /// before it gives up and lets go of its half of the pipe. `drain` runs
    /// on `DispatchQueue.global`, the same pool `reap` uses, so a grandchild
    /// that keeps writing for its entire remaining lifetime — potentially
    /// never finishing — would otherwise strand a worker thread and a file
    /// descriptor per abandoned stream indefinitely; enough concurrent runs
    /// like that exhaust the descriptor table and stall reaping for runs
    /// that have nothing to do with the grandchild.
    ///
    /// Long, because letting go closes the read end, and that `SIGPIPE`s
    /// whatever is still writing — a process the user started and Pium was
    /// never asked to touch. `drainGraceSeconds` above already covers the
    /// common case, a grandchild that goes quiet within a few seconds,
    /// without ever reaching this.
    private static let abandonedDrainHardCapSeconds: Double = 300

    /// How often a drain wakes from `poll` to ask whether it has been
    /// abandoned. Only the abandonment deadline, five minutes out, depends on
    /// this granularity, so a full second between checks is ample — and it
    /// costs one wakeup per second per live stream, nothing more.
    private static let abandonmentCheckMilliseconds: Int32 = 1000

    /// What a drain has kept, readable at any time — including while the
    /// drain itself is still running. `awaitDrains` needs this: giving up on
    /// a drain that is taking too long still has to return what it kept, and
    /// it cannot wait for the drain to finish first without defeating the
    /// point of giving up.
    private final class CapturedOutput: @unchecked Sendable {
        private let lock = NSLock()
        private var kept = Data()
        private var truncated = false

        fileprivate func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }
            let room = ProcessRunner.outputCap - kept.count
            if room > 0 {
                kept.append(chunk.prefix(room))
            }
            if chunk.count > room { truncated = true }
        }

        var snapshot: (String, Bool) {
            lock.lock()
            defer { lock.unlock() }
            return (ProcessRunner.text(of: kept), truncated)
        }
    }

    /// Decodes what was kept, discarding a trailing byte sequence the cap cut
    /// in half. `String(decoding:)` would turn those bytes into U+FFFD, which
    /// is a character the command never printed.
    private static func text(of bytes: Data) -> String {
        if let complete = String(data: bytes, encoding: .utf8) { return complete }
        // A UTF-8 sequence is at most four bytes, so at most three can dangle.
        for dropped in 1...3 where bytes.count > dropped {
            let shortened = bytes.dropLast(dropped)
            if let complete = String(data: shortened, encoding: .utf8) { return complete }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The moment `run` stopped waiting on its drains, and the deadline that
    /// follows from it. A drain reads until EOF for as long as somebody is
    /// waiting on the answer; once nobody is, it has `abandonedDrainHardCapSeconds`
    /// to reach EOF on its own before it gives up.
    ///
    /// The deadline has to start here rather than when the drain does: a
    /// command that legitimately runs for an hour keeps its drains short of
    /// EOF that whole time, and cutting them off at a fixed age would truncate
    /// its output and `SIGPIPE` the command itself mid-run.
    private final class Abandonment: @unchecked Sendable {
        private let lock = NSLock()
        private var deadline: ContinuousClock.Instant?

        /// Starts the clock; the first call fixes the deadline.
        fileprivate func begin() {
            lock.lock()
            defer { lock.unlock() }
            guard deadline == nil else { return }
            deadline = ContinuousClock().now + .seconds(ProcessRunner.abandonedDrainHardCapSeconds)
        }

        fileprivate var isPastDeadline: Bool {
            lock.lock()
            defer { lock.unlock() }
            guard let deadline else { return false }
            return ContinuousClock().now >= deadline
        }
    }

    /// Resumes its single waiter the moment it is first opened; further
    /// calls are no-ops. `awaitDrains` uses this to race the drains against
    /// a timer without the structured wait a task group would impose — the
    /// loser here is allowed to never finish.
    ///
    /// `isOpen` latches the state: both racers in `awaitDrains` are
    /// unstructured tasks, so `open()` can reach this actor before `wait()`
    /// has registered a continuation — the common case is exactly that race,
    /// since both drains are often already at EOF by the time `awaitDrains`
    /// starts. Without the latch, that `open()` would resume nothing, and
    /// `wait()` would then park on a continuation nobody is ever going to
    /// open again.
    private actor OneShotGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    func run(_ request: ExecutionRequest, cancellation: Cancellation) async -> ExecutionOutcome {
        let child: ChildProcess
        do {
            child = try ChildProcess.spawn(
                executable: request.executable,
                arguments: request.arguments,
                workingDirectory: request.workingDirectory,
                environment: request.environment
            )
        } catch let failure as ExecutionFailure {
            return ExecutionOutcome(
                ending: .failed(failure), standardOutput: "", standardError: "", wasTruncated: false
            )
        } catch {
            // ChildProcess.spawn only ever throws ExecutionFailure; this
            // branch exists so the catch is exhaustive without silently
            // discarding whatever else somehow reached it.
            return ExecutionOutcome(
                ending: .failed(.spawnFailed(code: -1)),
                standardOutput: "",
                standardError: "",
                wasTruncated: false
            )
        }

        // Cancelled between the decision to run and the spawn: signal at once
        // rather than leaving an orphan nobody is waiting on.
        guard cancellation.attach(child) else {
            child.signalGroup(SIGKILL)
            _ = await Self.reap(child)
            return ExecutionOutcome(
                ending: .cancelled, standardOutput: "", standardError: "", wasTruncated: false
            )
        }

        let outCaptured = CapturedOutput()
        let errCaptured = CapturedOutput()
        let abandonment = Abandonment()
        let outTask = Task {
            await Self.drain(child.standardOutput, into: outCaptured, abandonment: abandonment)
        }
        let errTask = Task {
            await Self.drain(child.standardError, into: errCaptured, abandonment: abandonment)
        }

        // Whether the timeout fired is recorded by the task that fires it, not
        // inferred from which signal killed the process: a command can be
        // cancelled and killed by the same signal, and guessing gets it wrong.
        let expiry = Expiry()

        // Escalates a cancellation to SIGKILL after the grace period, whether
        // or not a timeout was ever declared: PRD §11's grace-then-kill
        // sequence is not conditional on §10.4's timeout being set.
        let cancelEscalation = Task {
            while !cancellation.wasCancelled {
                try await Task.sleep(for: .milliseconds(100))
            }
            try await Task.sleep(for: .seconds(Self.graceSeconds))
            cancellation.signal(SIGKILL)
        }

        // Escalates a timeout, independently of the cancellation escalation
        // above: the two can both be armed at once, and either may fire first.
        let timeoutEscalation: Task<Void, Error>? = request.timeoutSeconds.map { seconds in
            Task {
                try await Task.sleep(for: .seconds(seconds))
                expiry.markExpired()
                cancellation.signal(SIGTERM)
                try await Task.sleep(for: .seconds(Self.graceSeconds))
                cancellation.signal(SIGKILL)
            }
        }

        let ending = await Self.reap(child)
        // Nothing sent after this point can reach the pid we just reaped: see
        // `Cancellation.detach`.
        cancellation.detach()
        cancelEscalation.cancel()
        timeoutEscalation?.cancel()

        let (output, error) = await Self.awaitDrains(
            outTask, errTask, out: outCaptured, err: errCaptured, abandonment: abandonment
        )
        return Self.outcome(
            ending: ending,
            timedOut: expiry.hasExpired,
            cancelled: cancellation.wasCancelled,
            output: output,
            error: error
        )
    }

    private static func outcome(
        ending: ChildProcess.Ending,
        timedOut: Bool,
        cancelled: Bool,
        output: (String, Bool),
        error: (String, Bool)
    ) -> ExecutionOutcome {
        let resolved: ExecutionOutcome.Ending =
            if cancelled { .cancelled }
            else if timedOut { .timedOut }
            else {
                switch ending {
                case .exited(let code): .exited(code)
                case .signalled(let signal): .signalled(signal)
                }
            }

        return ExecutionOutcome(
            ending: resolved,
            standardOutput: output.0,
            standardError: error.0,
            wasTruncated: output.1 || error.1
        )
    }

    /// Reads to EOF, keeping the first `outputCap` bytes in `captured` and
    /// discarding the rest. Discarding is not the same as not reading: the
    /// child blocks on a full pipe, so draining continues either way.
    ///
    /// Waits in `poll` rather than in `read` so the loop comes up for air
    /// every `abandonmentCheckMilliseconds` even when the pipe is silent. That
    /// is what lets a drain nobody is waiting on any more notice its own
    /// deadline and stop — releasing the worker thread it occupies and, once
    /// it drops the last reference to `handle`, the read end of the pipe.
    /// Bounding an abandoned drain from inside the drain is the whole reason
    /// for the `poll`: the alternative is a second party closing this
    /// descriptor from another thread while this loop sits between two reads,
    /// which reads whatever the kernel has since handed that number to.
    ///
    /// `Darwin.read` rather than `FileHandle.availableData` because the latter
    /// raises an Objective-C exception, which Swift cannot catch, where `read`
    /// reports the same conditions as an ordinary `-1`.
    private static func drain(
        _ handle: FileHandle,
        into captured: CapturedOutput,
        abandonment: Abandonment
    ) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let fd = handle.fileDescriptor
                var buffer = [UInt8](repeating: 0, count: outputCap)
                readLoop: while !abandonment.isPastDeadline {
                    var watched = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                    let ready = poll(&watched, 1, abandonmentCheckMilliseconds)
                    if ready < 0 {
                        if errno == EINTR { continue readLoop }
                        break readLoop
                    }
                    // Nothing to read this interval; go round and re-check the
                    // deadline. A closed write end shows up as readable too,
                    // and `read` reports it as the EOF it is.
                    guard ready > 0 else { continue readLoop }

                    let bytesRead = buffer.withUnsafeMutableBytes { pointer in
                        Darwin.read(fd, pointer.baseAddress, pointer.count)
                    }
                    switch bytesRead {
                    case ..<0:
                        // EINTR is a spurious wakeup, worth retrying; any
                        // other error ends the loop.
                        if errno == EINTR { continue readLoop }
                        break readLoop
                    case 0:
                        break readLoop // genuine EOF
                    default:
                        captured.append(Data(buffer[0..<bytesRead]))
                    }
                }
                continuation.resume()
            }
        }
    }

    /// Waits for both drains, but not past `drainGraceSeconds` once the
    /// process has already been reaped: a grandchild the process left
    /// running — still writing, not merely holding the pipe silently open —
    /// can keep a drain short of EOF indefinitely.
    ///
    /// Past the bound, this run gives up on the *wait*, not on the pipe:
    /// closing the read end here, the moment the bound elapses, would
    /// `SIGPIPE` the grandchild on its next write and kill a process nobody
    /// asked Pium to touch. Giving up on the wait instead just stops looking:
    /// this run returns whatever `captured` held at that moment, and the drain
    /// keeps reading quietly in the background until the pipe closes or its
    /// own, much longer, `Abandonment` deadline passes.
    ///
    /// That deadline starts here, whichever way the race went — a drain that
    /// has already finished is not listening, and one that has not is exactly
    /// what the deadline is for.
    private static func awaitDrains(
        _ outTask: Task<Void, Never>,
        _ errTask: Task<Void, Never>,
        out: CapturedOutput,
        err: CapturedOutput,
        abandonment: Abandonment
    ) async -> ((String, Bool), (String, Bool)) {
        let gate = OneShotGate()
        Task {
            _ = await outTask.value
            _ = await errTask.value
            await gate.open()
        }
        Task {
            try? await Task.sleep(for: .seconds(drainGraceSeconds))
            await gate.open()
        }
        await gate.wait()
        abandonment.begin()
        return (out.snapshot, err.snapshot)
    }

    private static func reap(_ child: ChildProcess) async -> ChildProcess.Ending {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: child.waitForExit())
            }
        }
    }
}
