import Foundation

/// Every key each object in a manifest may carry.
///
/// This is what makes `additionalProperties: false` real: `Codable` cannot
/// report a key no type declares, so the loader compares the raw object against
/// this map before decoding. `PluginSchemaAgreementTests` asserts it equals what
/// the shipped schema advertises, so the two cannot drift apart unnoticed.
enum ManifestKeys {
    /// Keyed by object path. `""` is the root; `"configuration[]"` is one
    /// element of the configuration array.
    static let byPath: [String: Set<String>] = [
        "": [
            "schemaVersion", "id", "name", "description", "keywords", "aliases",
            "icon", "input", "command", "configuration", "output",
            "timeoutSeconds", "confirmBeforeRun",
        ],
        "input": ["mode", "placeholder"],
        "command": ["executable", "arguments", "workingDirectory"],
        "configuration[]": ["key", "label", "type", "required", "environmentVariable"],
        "output": ["mode"],
    ]

    /// The keys a manifest cannot omit. Everything else has a documented
    /// default.
    static let requiredAtRoot: Set<String> = ["schemaVersion", "id", "name", "command"]
}
