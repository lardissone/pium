import Foundation

/// One run, from the decision to start it to whatever it ended as.
struct ExecutionRecord: Identifiable, Sendable {
    /// A run is either still going or it has ended, and how it ended is
    /// `ExecutionEnding` — the same account the runner hands back, rather than
    /// a second set of names for the same five outcomes.
    enum State: Sendable, Equatable {
        case running
        case ended(ExecutionEnding)
    }

    let id: UUID
    let pluginID: String
    let pluginName: String
    /// What the plugin declared about its own output, carried here because it
    /// is a fact about this run that outlives the manifest lookup — and what
    /// `HUDPresentation` needs to decide whether success is worth showing.
    let outputMode: PluginOutputMode
    /// When the run started, for a footer that measures elapsed time from the
    /// run's own beginning rather than from whenever it happens to be read.
    let startedAt: Date
    var state: State
    var standardOutput: String
    var standardError: String
    var wasTruncated: Bool

    var isRunning: Bool { state == .running }
}
