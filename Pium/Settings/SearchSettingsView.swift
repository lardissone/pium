import SwiftUI

/// The Search settings section.
struct SearchSettingsView: View {
    /// The same store the launcher records into, so erasing takes effect
    /// without a relaunch.
    let frecency: any FrecencyStoring

    @State private var isFileSearchEnabled = Preferences.shared.isFileSearchEnabled
    @State private var scope = Preferences.shared.fileSearchScope
    @State private var isConfirmingErase = false
    @State private var hasErased = false

    var body: some View {
        Form {
            Section {
                Toggle(
                    String(localized: "settings.search.fileSearch"),
                    isOn: $isFileSearchEnabled
                )
                .onChange(of: isFileSearchEnabled) { _, enabled in
                    Preferences.shared.isFileSearchEnabled = enabled
                }

                Picker(String(localized: "settings.search.scope"), selection: $scope) {
                    ForEach(FileSearchScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .disabled(!isFileSearchEnabled)
                .onChange(of: scope) { _, newScope in
                    Preferences.shared.fileSearchScope = newScope
                }
            } footer: {
                Text(String(localized: "settings.search.fileSearchExplanation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                // Confirmed before erasing: this cannot be undone and the
                // button sits among controls people click while exploring.
                Button(String(localized: "settings.search.clearHistory"), role: .destructive) {
                    isConfirmingErase = true
                }
                .confirmationDialog(
                    String(localized: "settings.search.clearHistory"),
                    isPresented: $isConfirmingErase
                ) {
                    Button(String(localized: "settings.search.clearHistory"), role: .destructive) {
                        frecency.clear()
                        hasErased = true
                    }
                }
                if hasErased {
                    Text(String(localized: "settings.search.historyErased"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "settings.search.usageHistory"))
            } footer: {
                Text(String(localized: "settings.search.clearHistoryExplanation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private extension FileSearchScope {
    var title: String {
        switch self {
        case .home: String(localized: "settings.search.scope.home")
        case .allIndexedLocal: String(localized: "settings.search.scope.allIndexedLocal")
        }
    }
}
