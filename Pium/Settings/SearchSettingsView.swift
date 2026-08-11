import AppKit
import SwiftUI

/// The Search settings section.
struct SearchSettingsView: View {
    /// The same store the launcher records into, so erasing takes effect
    /// without a relaunch.
    let frecency: any FrecencyStoring
    /// Injected so a test can drive the rows without raising a real prompt.
    let access: ProtectedFolderAccess

    @State private var isFileSearchEnabled = Preferences.shared.isFileSearchEnabled
    @State private var scope = Preferences.shared.fileSearchScope
    @State private var isConfirmingErase = false
    @State private var hasErased = false
    @State private var folderStatuses: [ProtectedFolder: ProtectedFolderAccess.Status] = [:]
    @State private var isRequesting = false

    /// What a row can offer, given where its folder stands.
    ///
    /// Not `private`, so a test can exercise the decision without a window —
    /// the same reason `PluginsSettingsView.setEnabled` is not.
    enum RowAction: Equatable {
        case allow
        case alreadyAllowed
        case openSystemSettings
    }

    func action(for status: ProtectedFolderAccess.Status) -> RowAction {
        switch status {
        case .notRequested: .allow
        case .granted: .alreadyAllowed
        // macOS does not ask twice, so there is nothing left for Pium to do
        // but point at the place where the answer can be changed.
        case .blocked: .openSystemSettings
        }
    }

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

            Section {
                ForEach(ProtectedFolder.allCases, id: \.self) { folder in
                    LabeledContent(folder.title) {
                        switch action(for: folderStatuses[folder] ?? .notRequested) {
                        case .allow:
                            Button(String(localized: "settings.search.folderAllow")) {
                                request([folder])
                            }
                            .disabled(isRequesting)
                        case .alreadyAllowed:
                            Text(String(localized: "settings.search.folderAllowed"))
                                .foregroundStyle(.secondary)
                        case .openSystemSettings:
                            // The button alone would not say what is wrong, so
                            // the state is named beside it.
                            HStack(spacing: Tokens.Spacing.tight) {
                                Text(String(localized: "settings.search.folderBlocked"))
                                    .foregroundStyle(.secondary)
                                Button(String(localized: "settings.search.folderOpenSettings")) {
                                    access.openSystemSettings()
                                }
                            }
                        }
                    }
                }
            } header: {
                Text(String(localized: "settings.search.folders"))
            } footer: {
                Text(String(localized: "settings.search.foldersExplanation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshFolderStatuses)
        // Granting access in System Settings tells Pium nothing, and coming
        // back to Pium is what follows it. Without this, a row that sent
        // somebody to System Settings keeps saying so after they obeyed it.
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refreshFolderStatuses()
        }
    }

    /// Whether a refresh may replace what is on screen.
    ///
    /// A request in flight owns the answer, and a refresh must not race it.
    /// Answering the system's prompt reactivates Pium, which is what a refresh
    /// listens for — so the refresh can read what Pium remembers asking about
    /// *before* the request has recorded the folder it just asked for. It
    /// would then classify a folder the user has this second granted as one
    /// nobody ever asked about, and replace `granted` with an Allow button.
    ///
    /// Nothing is lost by skipping: the request reports every folder it was
    /// given, which is what redraws the rows.
    ///
    /// Not `private`, so a test can exercise the decision without a window —
    /// the same reason `action(for:)` is not.
    static func shouldRefresh(whileRequesting isRequesting: Bool) -> Bool {
        !isRequesting
    }

    private func refreshFolderStatuses() {
        guard Self.shouldRefresh(whileRequesting: isRequesting) else { return }
        access.statuses(of: ProtectedFolder.allCases) { statuses in
            folderStatuses = statuses
        }
    }

    private func request(_ folders: [ProtectedFolder]) {
        isRequesting = true
        access.request(folders) { statuses in
            folderStatuses.merge(statuses) { _, new in new }
            isRequesting = false
        }
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
