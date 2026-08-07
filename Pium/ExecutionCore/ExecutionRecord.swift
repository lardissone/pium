import Foundation

/// One run, from the decision to start it to whatever it ended as.
struct ExecutionRecord: Identifiable, Sendable {
    enum State: Sendable, Equatable {
        case running
        case finished(exitCode: Int32)
        case cancelled
        case timedOut
        /// Killed by a signal nobody here sent — a crash, or something outside
        /// Pium reaching the process.
        case signalled(Int32)
        /// Never ran, or died in a way the runner could name.
        case failed(ExecutionFailure)
    }

    let id: UUID
    let pluginID: String
    let pluginName: String
    /// When the run started, for a footer that measures elapsed time from the
    /// run's own beginning rather than from whenever it happens to be read.
    let startedAt: Date
    var state: State
    var standardOutput: String
    var standardError: String
    var wasTruncated: Bool
}
