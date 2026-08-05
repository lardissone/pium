import Foundation

/// Everything that can be wrong with one plugin file.
///
/// Each case carries enough to fix the file without opening Pium's source. The
/// messages are localized because they reach the result list, which is user
/// interface even when its audience is the author.
enum PluginDiagnostic: Sendable, Equatable {
    case unreadableFile
    case malformedJSON(String)
    case unknownKey(path: String, key: String)
    case missingKey(String)
    case wrongType(path: String, expected: String)
    case unsupportedSchemaVersion(Int)
    case invalidIdentifier(String)
    case invalidTemplate(String)
    case secretInArguments(key: String)
    case invalidTimeout(Int)
    case duplicateIdentifier(String)
    case conflictingAlias(String)

    var message: String {
        switch self {
        case .unreadableFile:
            String(localized: "plugin.diagnostic.unreadableFile")
        case .malformedJSON(let detail):
            String(localized: "plugin.diagnostic.malformedJSON \(detail)")
        case .unknownKey(let path, let key):
            String(localized: "plugin.diagnostic.unknownKey \(key) \(displayPath(path))")
        case .missingKey(let key):
            String(localized: "plugin.diagnostic.missingKey \(key)")
        case .wrongType(let path, let expected):
            String(localized: "plugin.diagnostic.wrongType \(displayPath(path)) \(expected)")
        case .unsupportedSchemaVersion(let version):
            String(
                localized: "plugin.diagnostic.unsupportedSchemaVersion \(version) \(PluginManifest.currentSchemaVersion)"
            )
        case .invalidIdentifier(let identifier):
            String(localized: "plugin.diagnostic.invalidIdentifier \(identifier)")
        case .invalidTemplate(let detail):
            String(localized: "plugin.diagnostic.invalidTemplate \(detail)")
        case .secretInArguments(let key):
            String(localized: "plugin.diagnostic.secretInArguments \(key)")
        case .invalidTimeout(let seconds):
            String(localized: "plugin.diagnostic.invalidTimeout \(seconds)")
        case .duplicateIdentifier(let identifier):
            String(localized: "plugin.diagnostic.duplicateIdentifier \(identifier)")
        case .conflictingAlias(let alias):
            String(localized: "plugin.diagnostic.conflictingAlias \(alias)")
        }
    }

    /// The root object has no name worth printing; nested paths do.
    private func displayPath(_ path: String) -> String {
        path.isEmpty ? String(localized: "plugin.diagnostic.rootObject") : path
    }
}
