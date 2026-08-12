import Foundation

/// Everything debug logging can record.
///
/// A closed set rather than free-form strings: a call site cannot invent its
/// own format, and — the part that matters — cannot interpolate a secret into
/// a message, because no case has anywhere to put one. A run's environment is
/// carried as key names alone.
enum DebugEvent: Sendable {
    enum LauncherEvent: String, Sendable {
        case opened
        case dismissed
    }

    case search(query: String, results: Int, duration: Duration)
    case run(plugin: String, executable: String, arguments: [String], environmentKeys: [String])
    case finished(plugin: String, ending: ExecutionEnding, output: String, error: String)
    case pluginsReloaded(count: Int, invalid: Int)
    case launcher(LauncherEvent)

    func line(at moment: Date) -> String {
        "\(Self.timestamp.string(from: moment))  \(body)"
    }

    private var body: String {
        switch self {
        case .search(let query, let results, let duration):
            "search  \"\(Self.oneLine(query))\"  \(results) results in \(Self.milliseconds(duration)) ms"
        case .run(let plugin, let executable, let arguments, let environmentKeys):
            "run  \(plugin)  \(executable) \(arguments.map(Self.oneLine).joined(separator: " "))  "
                + "env: \(environmentKeys.sorted().joined(separator: ", "))"
        case .finished(let plugin, let ending, let output, let error):
            "finished  \(plugin)  \(Self.describe(ending))  "
                + "out: \(Self.oneLine(output))  err: \(Self.oneLine(error))"
        case .pluginsReloaded(let count, let invalid):
            "plugins  \(count) loaded, \(invalid) invalid"
        case .launcher(let event):
            "launcher  \(event.rawValue)"
        }
    }

    private static func describe(_ ending: ExecutionEnding) -> String {
        switch ending {
        case .exited(let code): "exited \(code)"
        case .cancelled: "cancelled"
        case .timedOut: "timed out"
        case .signalled(let signal): "signalled \(signal)"
        case .failed(let failure): "did not run: \(failure.message)"
        }
    }

    /// An event is one line and a command's output is many, so the breaks are
    /// made visible instead of structural. A log whose records span lines is a
    /// log no `grep` can read.
    private static func oneLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    /// A `Duration`'s components are seconds and attoseconds; 10^15 of the
    /// latter make a millisecond.
    private static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds * 1_000 + attoseconds / 1_000_000_000_000_000)
    }

    /// Fixed to POSIX so a log written on a Spanish Mac reads the same as one
    /// written anywhere else — the recipient is whoever is diagnosing, not
    /// whoever recorded it.
    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}
