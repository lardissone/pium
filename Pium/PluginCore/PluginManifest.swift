import Foundation

/// One command, as declared by one JSON file.
///
/// Deliberately not `Codable`: a synthesised `init(from:)` accepts unknown keys
/// silently, and rejecting them is the schema's most important rule.
/// `ManifestDecoder` owns the conversion.
struct PluginManifest: Sendable, Equatable {
    /// The only version this build understands. A manifest declaring anything
    /// else is rejected with a message naming both numbers, rather than being
    /// decoded on a guess.
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    /// Stable and globally unique. Usage history is keyed to it, so it may not
    /// change without the plugin becoming a different plugin.
    let id: String
    let name: String
    let description: String?
    let keywords: [String]
    let aliases: [String]
    /// An SF Symbol name. Validity is a runtime question, so an unknown symbol
    /// falls back rather than invalidating the plugin.
    let icon: String?
    let input: PluginInput
    let command: PluginCommand
    let configuration: [PluginConfigurationField]
    let output: PluginOutput
    let timeoutSeconds: Int?
    /// When present, a non-empty message shown before every run.
    let confirmBeforeRun: String?
}

struct PluginInput: Sendable, Equatable {
    let mode: PluginInputMode
    let placeholder: String?
}

enum PluginInputMode: String, Sendable, Equatable, CaseIterable {
    case none
    case optional
    case required

    /// Whether typing a space on this plugin enters argument mode.
    var acceptsArgument: Bool { self != .none }
}

struct PluginCommand: Sendable, Equatable {
    let executable: String
    let arguments: [String]
    /// Relative paths resolve from the manifest's directory. Resolution is
    /// Phase 5; this phase only carries the declaration.
    let workingDirectory: String?
}

struct PluginConfigurationField: Sendable, Equatable {
    let key: String
    let label: String
    let type: PluginConfigurationType
    let required: Bool
    /// The name the value is exported under. Secrets reach a child process only
    /// this way — never through an argument.
    let environmentVariable: String
}

enum PluginConfigurationType: String, Sendable, Equatable, CaseIterable {
    case string
    case secret
}

struct PluginOutput: Sendable, Equatable {
    let mode: PluginOutputMode
}

enum PluginOutputMode: String, Sendable, Equatable, CaseIterable {
    case silent
    case toast
}
