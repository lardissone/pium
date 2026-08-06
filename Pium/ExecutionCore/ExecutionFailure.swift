import Foundation

/// Everything that can stop a run, before or after the process exists.
///
/// Not localized in this phase: these reach the unified log, and Phase 5b —
/// which puts them on screen — brings the strings. `PluginDiagnostic` covers
/// what is wrong with a *file*; this covers what is wrong with a *run*.
enum ExecutionFailure: Error, Equatable {
    case executableNotFound(name: String, searched: [String])
    case executableMissing(path: String)
    case executableNotExecutable(path: String)
    case missingConfiguration(field: String)
    /// The Keychain refused, which is not the same as a field nobody filled.
    case secretUnavailable(field: String)
    case alreadyRunning(plugin: String)
    case spawnFailed(code: Int32)

    var logDescription: String {
        switch self {
        case .executableNotFound(let name, let searched):
            "Could not find \(name) in \(searched.joined(separator: ":"))"
        case .executableMissing(let path):
            "No file at \(path)"
        case .executableNotExecutable(let path):
            "\(path) is not executable; it needs its execute bit (chmod +x)"
        case .missingConfiguration(let field):
            "Required configuration \(field) is empty"
        case .secretUnavailable(let field):
            "The Keychain would not return the secret for \(field)"
        case .alreadyRunning(let plugin):
            "\(plugin) is still running"
        case .spawnFailed(let code):
            "The process could not be started (posix_spawn returned \(code))"
        }
    }
}
