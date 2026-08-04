import SwiftUI

/// The Search settings section.
struct SearchSettingsView: View {
    @State private var isFileSearchEnabled = Preferences.shared.isFileSearchEnabled
    @State private var scope = Preferences.shared.fileSearchScope

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
