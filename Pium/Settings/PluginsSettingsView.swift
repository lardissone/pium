import AppKit
import SwiftUI

/// The Plugins section of Settings.
///
/// Every plugin is listed, including the ones that are disabled or broken:
/// this is the only place a user can switch one back on or read why it did not
/// load.
struct PluginsSettingsView: View {
    let index: PluginIndex
    let configuration: any PluginConfigurationStoring
    let secrets: any PluginSecretStoring
    let preferences: Preferences

    @State private var selectedID: String?
    @State private var disabledIDs: Set<String>

    init(
        index: PluginIndex,
        configuration: any PluginConfigurationStoring,
        secrets: any PluginSecretStoring,
        preferences: Preferences = .shared
    ) {
        self.index = index
        self.configuration = configuration
        self.secrets = secrets
        self.preferences = preferences
        _disabledIDs = State(initialValue: preferences.disabledPluginIDs)
    }

    var body: some View {
        HSplitView {
            // Orphaned secrets are a property of the folder, not of whichever
            // plugin happens to be selected, so they live below the plugin
            // rows here rather than in the detail pane, where they would
            // appear and disappear with the selection.
            List(selection: $selectedID) {
                ForEach(index.records) { record in
                    row(for: record)
                        .tag(record.id)
                }

                orphans
            }
            .frame(minWidth: 180)

            detail
                .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            // The presence index can drift if someone removes an item in
            // Keychain Access. Here is the only place the difference shows.
            secrets.reconcile()
        }
    }

    private func row(for record: PluginRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(for: record))
                Text(subtitle(for: record))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if record.isValid, let id = record.manifest?.id {
                Toggle("", isOn: binding(for: id))
                    .labelsHidden()
                    .accessibilityLabel(
                        String(localized: "settings.plugins.enabled \(Self.title(for: record))")
                    )
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let record = index.records.first(where: { $0.id == selectedID }) {
            Form {
                if case .invalid(let diagnostic) = state(of: record) {
                    Section {
                        Text(diagnostic.message)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(String(localized: "settings.plugins.problem"))
                    }
                }

                if let manifest = record.manifest, !manifest.configuration.isEmpty {
                    PluginConfigurationForm(
                        manifest: manifest,
                        configuration: configuration,
                        secrets: secrets
                    )
                }

                if let manifest = record.manifest {
                    Section {
                        LabeledContent(
                            String(localized: "settings.plugins.executable"),
                            value: manifest.command.executable
                        )
                        if !manifest.command.arguments.isEmpty {
                            LabeledContent(
                                String(localized: "settings.plugins.arguments"),
                                value: manifest.command.arguments.joined(separator: " ")
                            )
                        }
                        LabeledContent(
                            String(localized: "settings.plugins.workingDirectory"),
                            value: manifest.command.workingDirectory
                                ?? String(localized: "settings.plugins.pluginFolder")
                        )
                        if !manifest.configuration.isEmpty {
                            LabeledContent(
                                String(localized: "settings.plugins.environment"),
                                value: manifest.configuration
                                    .map(\.environmentVariable)
                                    .joined(separator: ", ")
                            )
                        }
                    } header: {
                        Text(String(localized: "settings.plugins.command"))
                    } footer: {
                        Text(String(localized: "settings.plugins.commandExplanation"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    LabeledContent(
                        String(localized: "settings.plugins.file"),
                        value: record.fileURL.lastPathComponent
                    )
                    Button(String(localized: "action.revealJSON")) {
                        NSWorkspace.shared.activateFileViewerSelecting([record.fileURL])
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            Text(String(localized: "settings.plugins.noSelection"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A file that never decoded has no name, so its filename stands in — the
    /// only thing its author knows it by.
    static func title(for record: PluginRecord) -> String {
        record.manifest?.name ?? record.fileURL.lastPathComponent
    }

    /// Plugin ids with stored secrets that no longer have a manifest in the
    /// folder. Sorted so the list does not reshuffle between appearances.
    static func orphanedPluginIDs(
        storedIDs: Set<String>,
        records: [PluginRecord]
    ) -> [String] {
        let present = Set(records.compactMap { $0.manifest?.id })
        return storedIDs.subtracting(present).sorted()
    }

    @ViewBuilder
    private var orphans: some View {
        let ids = Self.orphanedPluginIDs(
            storedIDs: secrets.storedPluginIDs(),
            records: index.records
        )
        if !ids.isEmpty {
            Section {
                ForEach(ids, id: \.self) { id in
                    HStack {
                        Text(id)
                        Spacer()
                        Button(String(localized: "settings.plugins.eraseSecrets"), role: .destructive) {
                            try? secrets.removeSecrets(pluginID: id)
                        }
                    }
                }
            } header: {
                Text(String(localized: "settings.plugins.orphanedSecrets"))
            } footer: {
                Text(String(localized: "settings.plugins.orphanedExplanation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(for record: PluginRecord) -> String {
        switch state(of: record) {
        case .invalid: String(localized: "settings.plugins.status.invalid")
        case .disabled: String(localized: "settings.plugins.status.disabled")
        case .missingConfiguration: String(localized: "settings.plugins.status.needsConfiguration")
        case .ready: String(localized: "settings.plugins.status.ready")
        }
    }

    private func state(of record: PluginRecord) -> PluginState {
        PluginStatusResolver(
            configuration: configuration,
            secrets: secrets,
            disabledIDs: disabledIDs
        ).state(of: record)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !disabledIDs.contains(id) },
            set: { isEnabled in disabledIDs = setEnabled(isEnabled, pluginID: id, in: disabledIDs) }
        )
    }

    /// The write-through behind the toggle: computes the next disabled set
    /// and writes it into `preferences` in the same step, returning it so the
    /// caller can also update its own copy.
    ///
    /// Takes the current set as a parameter and returns the next one, rather
    /// than reading and writing `disabledIDs` itself, so the round trip into
    /// `preferences` can be asserted directly — `@State` only persists a
    /// mutation once a view is installed in a real SwiftUI hierarchy, which a
    /// unit test never is.
    func setEnabled(_ isEnabled: Bool, pluginID: String, in currentDisabledIDs: Set<String>) -> Set<String> {
        var next = currentDisabledIDs
        if isEnabled { next.remove(pluginID) } else { next.insert(pluginID) }
        preferences.disabledPluginIDs = next
        return next
    }
}
