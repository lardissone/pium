import Foundation

/// What a plugin currently is, from the user's point of view.
///
/// Derived on demand rather than stored: it falls out of the manifest, the
/// user's switch, and the values they have filled in, so there is no saved
/// state that can disagree with the folder.
enum PluginState: Sendable, Equatable {
    case invalid(PluginDiagnostic)
    case disabled
    /// The labels of the required fields still empty, in manifest order.
    case missingConfiguration([String])
    case ready
}

@MainActor
struct PluginStatusResolver {
    private let configuration: any PluginConfigurationStoring
    private let secrets: any PluginSecretStoring
    private let disabledIDs: Set<String>

    init(
        configuration: any PluginConfigurationStoring,
        secrets: any PluginSecretStoring,
        disabledIDs: Set<String>
    ) {
        self.configuration = configuration
        self.secrets = secrets
        self.disabledIDs = disabledIDs
    }

    func state(of record: PluginRecord) -> PluginState {
        guard let manifest = record.manifest else {
            return .invalid(record.diagnostic ?? .unreadableFile)
        }
        guard !disabledIDs.contains(manifest.id) else { return .disabled }

        let missing = manifest.configuration
            .filter { $0.required && !isSatisfied($0, pluginID: manifest.id) }
            .map(\.label)
        return missing.isEmpty ? .ready : .missingConfiguration(missing)
    }

    private func isSatisfied(
        _ field: PluginConfigurationField,
        pluginID: String
    ) -> Bool {
        switch field.type {
        case .string:
            configuration.value(pluginID: pluginID, key: field.key) != nil
        case .secret:
            // Presence only. Nothing in this phase reads a secret's value.
            secrets.hasSecret(pluginID: pluginID, key: field.key)
        }
    }
}
