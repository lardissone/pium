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
    /// Whether the user has been sent to System Settings, which is what makes
    /// their return worth reading the folders again for. See `shouldRefresh`.
    @State private var hasSentUserToSystemSettings = false

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
                                    hasSentUserToSystemSettings = true
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
        // Coming back from System Settings is the one moment an answer can
        // have changed without Pium hearing about it. See `shouldRefresh`.
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refresh(onActivation: true)
        }
    }

    /// Whether a refresh may read the folders again.
    ///
    /// Refreshing is not free of consequence: reading a folder is what makes
    /// macOS ask, and it asks whenever *its* record says undetermined — which
    /// is not always what Pium remembers. The two come apart whenever the
    /// app's code identity changes or somebody removes Pium from System
    /// Settings. Refreshing on every activation therefore raised a prompt on
    /// every activation, one per folder, with no way out but answering them
    /// (PIUM-41).
    ///
    /// So a refresh happens on two occasions only, both of which the user
    /// caused: opening the pane, and returning to Pium after being sent to
    /// System Settings. Any other activation leaves the rows as they are —
    /// a stale row is a smaller wrong than a prompt nobody asked for.
    ///
    /// `isRequesting` excludes a third occasion: answering the system's own
    /// prompt reactivates Pium too, and a refresh racing the request that
    /// raised it can read what Pium remembers *before* the request records
    /// the folder just granted, and put an Allow button back over it.
    ///
    /// Not `private`, so a test can exercise the decision without a window —
    /// the same reason `action(for:)` is not.
    static func shouldRefresh(onActivation: Bool, sentToSystemSettings: Bool, isRequesting: Bool)
        -> Bool {
        guard !isRequesting else { return false }
        return onActivation ? sentToSystemSettings : true
    }

    private func refreshFolderStatuses() {
        refresh(onActivation: false)
    }

    private func refresh(onActivation: Bool) {
        guard Self.shouldRefresh(
            onActivation: onActivation,
            sentToSystemSettings: hasSentUserToSystemSettings,
            isRequesting: isRequesting
        ) else { return }
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
