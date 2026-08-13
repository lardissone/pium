import SwiftUI

/// The Settings content.
///
/// The sections are a list beside the content rather than a `TabView`, and the
/// list is a plain column rather than a `NavigationSplitView` pane. Both of the
/// obvious alternatives put chrome in the title bar that cannot be taken back
/// out: tabs collapse into an overflow chevron when they do not fit (PIUM-132),
/// and a split view fits a collapse button that neither placing nor removing
/// would move. Settings has six sections and no reason to hide them, so it
/// keeps none of that.
struct SettingsView: View {
    let frecency: any FrecencyStoring
    let access: ProtectedFolderAccess
    let onShortcutChanged: (HotkeyShortcut) -> Void
    let pluginIndex: PluginIndex
    let configuration: any PluginConfigurationStoring
    let secrets: any PluginSecretStoring
    let updates: any UpdateAvailability
    /// Shows a real HUD where the chosen anchor puts it. Owned by
    /// `AppDelegate`, which holds the controller that outlives this window.
    let onPreviewHUD: () -> Void

    @State private var section: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $section) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            // Room for the traffic lights, which sit over the sidebar now that
            // the window draws under its own title bar.
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: Self.titleBarHeight)
            }
            // Fixed rather than resizable. There is no divider to drag and no
            // button to collapse it, so the one width it has is the one it
            // needs: enough for the longest section name in either language.
            .frame(width: Self.sidebarWidth)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // The rule and the list run behind the title bar; a section's
                // controls must not. The top of the window drags it, so a
                // control up there is one the user cannot press.
                .safeAreaInset(edge: .top) {
                    Color.clear.frame(height: Self.titleBarHeight)
                }
        }
        // Both the list and the rule beside it run behind the title bar rather
        // than starting under it. Without this the window wears a lighter band
        // across its full width and the rule begins below it, which reads as a
        // sidebar stopping short of the top edge.
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Wide enough for "Actualizaciones", which is the longest section name in
    /// either language Pium ships.
    private static let sidebarWidth: CGFloat = 190

    /// The standard title bar, which the window draws under.
    private static let titleBarHeight: CGFloat = 28

    @ViewBuilder
    private var content: some View {
        switch section {
        case .general:
            GeneralSettingsView(onShortcutChanged: onShortcutChanged)
        case .search:
            SearchSettingsView(frecency: frecency, access: access)
        case .plugins:
            PluginsSettingsView(
                index: pluginIndex,
                configuration: configuration,
                secrets: secrets
            )
        case .appearance:
            AppearanceSettingsView(onPreview: onPreviewHUD)
        case .updates:
            UpdatesSettingsView(updates: updates)
        case .advanced:
            AdvancedSettingsView()
        }
    }
}

/// The sections of Settings, in the order they are listed.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case search
    case plugins
    case appearance
    case updates
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "settings.general.title")
        case .search: String(localized: "settings.search.title")
        case .plugins: String(localized: "settings.plugins.title")
        case .appearance: String(localized: "settings.appearance.title")
        case .updates: String(localized: "settings.updates.title")
        case .advanced: String(localized: "settings.advanced.title")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .search: "magnifyingglass"
        case .plugins: "puzzlepiece.extension"
        case .appearance: "paintbrush"
        case .updates: "arrow.down.circle"
        case .advanced: "gearshape.2"
        }
    }
}
