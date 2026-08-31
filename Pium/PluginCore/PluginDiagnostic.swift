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
    case invalidConfigurationKey(String)
    case reservedConfigurationKey(String)
    case duplicateConfigurationKey(String)
    case invalidEnvironmentVariable(String)
    case duplicateEnvironmentVariable(String)
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
        case .invalidConfigurationKey(let key):
            String(localized: "plugin.diagnostic.invalidConfigurationKey \(key)")
        case .reservedConfigurationKey(let key):
            String(localized: "plugin.diagnostic.reservedConfigurationKey \(key)")
        case .duplicateConfigurationKey(let key):
            String(localized: "plugin.diagnostic.duplicateConfigurationKey \(key)")
        case .invalidEnvironmentVariable(let name):
            String(localized: "plugin.diagnostic.invalidEnvironmentVariable \(name)")
        case .duplicateEnvironmentVariable(let name):
            String(localized: "plugin.diagnostic.duplicateEnvironmentVariable \(name)")
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

extension PluginDiagnostic {
    /// A rejected template, said in the terms a manifest's author is working
    /// in. `ArgumentTemplate` reports what was wrong as data and leaves the
    /// sentence to whoever is showing it, because the same rejection reads
    /// differently to somebody editing a JSON file and somebody filling a form.
    init(_ error: ArgumentTemplateError) {
        switch error {
        case .unclosedPlaceholder(let template):
            self = .invalidTemplate(String(localized: "plugin.template.unclosed \(template)"))
        case .unknownVariable(let name):
            self = .invalidTemplate(String(localized: "plugin.template.unknownVariable \(name)"))
        case .unknownFilter(let name):
            self = .invalidTemplate(String(localized: "plugin.template.unknownFilter \(name)"))
        }
    }
}

/// So a `Result` failure can be thrown from tests and callers alike.
extension PluginDiagnostic: Error {}
