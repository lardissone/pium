import SwiftUI

/// The configuration rows a manifest asks for.
///
/// Generated rather than designed: a plugin declares its fields and this
/// renders them. A secret's value is written and never read back — the row
/// reports only whether one is stored.
struct PluginConfigurationForm: View {
    let manifest: PluginManifest
    let configuration: any PluginConfigurationStoring
    let secrets: any PluginSecretStoring

    @State private var drafts: [String: String] = [:]
    // Keyed by field, not shared: an unrelated field saving successfully must
    // not clear another field's still-outstanding Keychain failure.
    @State private var failures: [String: String] = [:]

    var body: some View {
        Section {
            ForEach(manifest.configuration, id: \.key) { field in
                row(for: field)
            }
        } header: {
            Text(String(localized: "settings.plugins.configuration"))
        } footer: {
            Text(String(localized: "settings.plugins.secretsExplanation"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(for field: PluginConfigurationField) -> some View {
        switch field.type {
        case .string:
            VStack(alignment: .leading, spacing: 4) {
                TextField(label(for: field), text: draft(for: field))
                    .onSubmit { save(field) }
                failureText(for: field)
            }
        case .secret:
            VStack(alignment: .leading, spacing: 4) {
                SecureField(label(for: field), text: draft(for: field))
                    .onSubmit { save(field) }
                HStack {
                    Text(
                        secrets.hasSecret(pluginID: manifest.id, key: field.key)
                            ? String(localized: "settings.plugins.secretStored")
                            : String(localized: "settings.plugins.secretMissing")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if secrets.hasSecret(pluginID: manifest.id, key: field.key) {
                        Button(String(localized: "settings.plugins.clearSecret")) {
                            drafts[field.key] = ""
                            save(field)
                        }
                        .buttonStyle(.link)
                    }
                }
                failureText(for: field)
            }
        }
    }

    /// This field's own outstanding error, if it has one — beside its row
    /// rather than in one shared spot, so it is clear which field failed.
    @ViewBuilder
    private func failureText(for field: PluginConfigurationField) -> some View {
        if let failure = failures[field.key] {
            Text(failure)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    /// Required fields say so, because an empty one blocks execution in Phase 5.
    private func label(for field: PluginConfigurationField) -> String {
        field.required
            ? String(localized: "settings.plugins.requiredField \(field.label)")
            : field.label
    }

    private func draft(for field: PluginConfigurationField) -> Binding<String> {
        Binding(
            get: {
                drafts[field.key]
                    ?? (field.type == .string
                        ? configuration.value(pluginID: manifest.id, key: field.key) ?? ""
                        : "")
            },
            set: { drafts[field.key] = $0 }
        )
    }

    private func save(_ field: PluginConfigurationField) {
        do {
            try Self.save(
                drafts[field.key] ?? "",
                field: field,
                pluginID: manifest.id,
                configuration: configuration,
                secrets: secrets
            )
            // A saved secret is not echoed back into the field.
            if field.type == .secret { drafts[field.key] = "" }
            failures[field.key] = nil
        } catch {
            // A Keychain failure has to be visible: silently not saving a token
            // is how a user spends an evening wondering why nothing works.
            failures[field.key] = String(localized: "settings.plugins.saveFailed \(field.label)")
        }
    }

    /// Routing a value to the right store, which is the only decision here
    /// worth testing without a view.
    static func save(
        _ value: String,
        field: PluginConfigurationField,
        pluginID: String,
        configuration: any PluginConfigurationStoring,
        secrets: any PluginSecretStoring
    ) throws {
        switch field.type {
        case .string:
            configuration.setValue(value, pluginID: pluginID, key: field.key)
        case .secret:
            try secrets.setSecret(value.isEmpty ? nil : value, pluginID: pluginID, key: field.key)
        }
    }
}
