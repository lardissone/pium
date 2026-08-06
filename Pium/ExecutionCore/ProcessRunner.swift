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
            isCancelled = true
            let child = child
            lock.unlock()
            child?.signalGroup(SIGTERM)
        }

        fileprivate func attach(_ process: ChildProcess) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !isCancelled else { return false }
            child = process
            return true
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

    /// The grace `SIGTERM` gets before `SIGKILL`, per PRD §11.
    private static let graceSeconds: Double = 2

    func run(_ request: ExecutionRequest, cancellation: Cancellation) async -> ExecutionOutcome {
        let child: ChildProcess
        do {
            child = try ChildProcess.spawn(
                executable: request.executable,
                arguments: request.arguments,
                workingDirectory: request.workingDirectory,
                environment: request.environment
            )
        } catch {
            return ExecutionOutcome(
                ending: .exited(-1), standardOutput: "", standardError: "", wasTruncated: false
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

        async let out = Self.drain(child.standardOutput)
        async let err = Self.drain(child.standardError)

        // Whether the timeout fired is recorded by the task that fires it, not
        // inferred from which signal killed the process: a command can be
        // cancelled and killed by the same signal, and guessing gets it wrong.
        let expiry = Expiry()
        if let seconds = request.timeoutSeconds {
            let timeout = Task {
                try await Task.sleep(for: .seconds(seconds))
                expiry.markExpired()
                child.signalGroup(SIGTERM)
                try await Task.sleep(for: .seconds(Self.graceSeconds))
                child.signalGroup(SIGKILL)
            }
            let ending = await Self.reap(child)
            timeout.cancel()
            let (output, error) = await (out, err)
            return Self.outcome(
                ending: ending,
                timedOut: expiry.hasExpired,
                cancelled: cancellation.wasCancelled,
                output: output,
                error: error
            )
        }

        // No timeout: the grace-then-kill escalation still applies to a
        // cancellation, so a command that ignores `SIGTERM` cannot hang Pium.
        let escalation = Task {
            while !cancellation.wasCancelled {
                try await Task.sleep(for: .milliseconds(100))
            }
            try await Task.sleep(for: .seconds(Self.graceSeconds))
            child.signalGroup(SIGKILL)
        }
        let ending = await Self.reap(child)
        escalation.cancel()
        let (output, error) = await (out, err)
        return Self.outcome(
            ending: ending,
            timedOut: false,
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
            else if case .exited(let code) = ending { .exited(code) }
            else { .exited(-1) }

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

    private static func reap(_ child: ChildProcess) async -> ChildProcess.Ending {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: child.waitForExit())
            }
        }
    }
}
