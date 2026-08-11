import SwiftUI

/// The Settings content.
///
/// The Appearance, Updates, and Advanced sections arrive with the features
/// they configure, in Phases 5 through 7.
struct SettingsView: View {
    let frecency: any FrecencyStoring
    let access: ProtectedFolderAccess
    let onShortcutChanged: (HotkeyShortcut) -> Void
    let pluginIndex: PluginIndex
    let configuration: any PluginConfigurationStoring
    let secrets: any PluginSecretStoring

    var body: some View {
        TabView {
            GeneralSettingsView(onShortcutChanged: onShortcutChanged)
                .tabItem {
                    Label(
                        String(localized: "settings.general.title"),
                        systemImage: "gearshape"
                    )
                }

            SearchSettingsView(frecency: frecency, access: access)
                .tabItem {
                    Label(
                        String(localized: "settings.search.title"),
                        systemImage: "magnifyingglass"
                    )
                }

            PluginsSettingsView(
                index: pluginIndex,
                configuration: configuration,
                secrets: secrets
            )
            .tabItem {
                Label(
                    String(localized: "settings.plugins.title"),
                    systemImage: "puzzlepiece.extension"
                )
            }
        }
    }
}
