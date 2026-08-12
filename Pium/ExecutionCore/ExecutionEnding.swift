import Foundation

/// How a run ended.
///
/// One vocabulary, shared by the runner's `ExecutionOutcome` and the manager's
/// `ExecutionRecord`, so a run that ends does not get renamed on the way from
/// one to the other. `ChildProcess.Termination` stays separate on purpose: it
/// is what `wait(2)` reports about a process, and a process cannot be
/// `.cancelled`, `.timedOut`, or `.failed` — those are things Pium knows and
/// the kernel does not.
enum ExecutionEnding: Sendable, Equatable {
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
