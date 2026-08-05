import Foundation

/// The regular, non-secret configuration values a plugin declares.
///
/// Kept in preferences rather than written back into the plugin's JSON: the
/// file belongs to its author and is often under Git, and Pium never modifies
/// it (PRD §10.5).
@MainActor
protocol PluginConfigurationStoring {
    func value(pluginID: String, key: String) -> String?
    /// `nil`, or text that is only whitespace, removes the value.
    func setValue(_ value: String?, pluginID: String, key: String)
}

@MainActor
final class PluginConfigurationStore: PluginConfigurationStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func value(pluginID: String, key: String) -> String? {
        guard let stored = defaults.string(forKey: Self.key(pluginID, key)) else { return nil }
        // Whitespace is what a half-cleared field leaves behind. Reporting it
        // as a value would let a required field look satisfied by nothing.
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : stored
    }

    func setValue(_ value: String?, pluginID: String, key: String) {
        let storageKey = Self.key(pluginID, key)
        guard
            let value,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        defaults.set(value, forKey: storageKey)
    }

    /// Prefixed like every other Pium key so a future migration can find them
    /// without touching system keys in the same domain.
    private static func key(_ pluginID: String, _ field: String) -> String {
        "pium.plugin.\(pluginID).config.\(field)"
    }
}
