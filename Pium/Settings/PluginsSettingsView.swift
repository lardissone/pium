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

    @State private var selectedID: String?
    @State private var disabledIDs = Preferences.shared.disabledPluginIDs

    var body: some View {
        HSplitView {
            List(index.records, selection: $selectedID) { record in
                row(for: record)
                    .tag(record.id)
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
            set: { isEnabled in
                if isEnabled { disabledIDs.remove(id) } else { disabledIDs.insert(id) }
                Preferences.shared.disabledPluginIDs = disabledIDs
            }
        )
    }
}
