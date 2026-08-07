import Foundation

/// Everything that can stop a run, before or after the process exists.
///
/// `PluginDiagnostic` covers what is wrong with a *file*; this covers what
/// is wrong with a *run*.
enum ExecutionFailure: Error, Equatable {
    case executableNotFound(name: String, searched: [String])
    case executableMissing(path: String)
    case executableNotExecutable(path: String)
    case quarantined(path: String)
    case invalidManifest(path: String)
    case missingConfiguration(field: String)
    /// The Keychain refused, which is not the same as a field nobody filled.
    case secretUnavailable(field: String)
    case alreadyRunning(plugin: String)
    case spawnFailed(code: Int32)

    /// What a person is told. These reach the HUD, so they name the file and
    /// the thing to do about it rather than the system call that refused.
    var message: String {
        switch self {
        case .executableNotFound(let name, let searched):
            String(localized: "execution.failure.notFound \(name) \(searched.joined(separator: ", "))")
        case .executableMissing(let path):
            String(localized: "execution.failure.missing \(path)")
        case .executableNotExecutable(let path):
            String(localized: "execution.failure.notExecutable \(path)")
        case .quarantined(let path):
            String(localized: "execution.failure.quarantined \(path)")
        case .invalidManifest(let path):
            String(localized: "execution.failure.invalidManifest \(path)")
        case .missingConfiguration(let field):
            String(localized: "execution.failure.missingConfiguration \(field)")
        case .secretUnavailable(let field):
            String(localized: "execution.failure.secretUnavailable \(field)")
        case .alreadyRunning(let plugin):
            String(localized: "execution.failure.alreadyRunning \(plugin)")
        case .spawnFailed(let code):
            String(localized: "execution.failure.spawnFailed \(code)")
        }
    }
}
