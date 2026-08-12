import OSLog

/// Performance instrumentation.
///
/// Categories mirror the budgets in the PRD so a regression can be attributed
/// to a specific stage rather than to "the app feels slow". Signposts are
/// compiled into Release builds; `OSSignposter` is inert unless a trace is
/// recording.
enum Signposts {
    static let subsystem = "com.lardissone.pium"

    /// Shortcut press through visible, focused panel. Budget: p95 ≤ 100 ms.
    static let launcher = OSSignposter(subsystem: subsystem, category: "Launcher")

    /// Query through first rendered result. Budget: p95 ≤ 50 ms for local
    /// providers. Used from Phase 2 onward.
    static let search = OSSignposter(subsystem: subsystem, category: "Search")
}
