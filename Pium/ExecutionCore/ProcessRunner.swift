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
    /// before this run gives up on them and returns what they have. A
    /// grandchild the process left behind — a script that starts a daemon in
    /// the background — can keep holding a pipe's write end open long after
    /// the process we spawned is gone, and EOF never arrives on its own.
    private static let drainGraceSeconds: Double = 1

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

        let outTask = Task { await Self.drain(child.standardOutput) }
        let errTask = Task { await Self.drain(child.standardError) }

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

        let (output, error) = await Self.awaitDrains(outTask, errTask, child: child)
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

    /// Reads to EOF, keeping the first `outputCap` bytes and discarding the
    /// rest. Discarding is not the same as not reading: the child blocks on a
    /// full pipe, so draining continues either way.
    private static func drain(_ handle: FileHandle) async -> (String, Bool) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var kept = Data()
                var truncated = false
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    let room = outputCap - kept.count
                    if room > 0 {
                        kept.append(chunk.prefix(room))
                    }
                    if chunk.count > room { truncated = true }
                }
                continuation.resume(returning: (String(decoding: kept, as: UTF8.self), truncated))
            }
        }
    }

    /// Waits for both drains, but not past `drainGraceSeconds` once the
    /// process has already been reaped. A drain that is still short of EOF
    /// after that is stuck on a grandchild holding the pipe open, not on the
    /// process this run spawned — so the read ends are force-closed, which
    /// unblocks `drain`'s blocking read and lets it return what it kept.
    private static func awaitDrains(
        _ outTask: Task<(String, Bool), Never>,
        _ errTask: Task<(String, Bool), Never>,
        child: ChildProcess
    ) async -> ((String, Bool), (String, Bool)) {
        let closer = Task {
            try await Task.sleep(for: .seconds(drainGraceSeconds))
            child.standardOutput.closeFile()
            child.standardError.closeFile()
        }
        let output = await outTask.value
        let error = await errTask.value
        closer.cancel()
        return (output, error)
    }

    private static func reap(_ child: ChildProcess) async -> ChildProcess.Ending {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: child.waitForExit())
            }
        }
    }
}
