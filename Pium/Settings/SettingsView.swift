import SwiftUI

/// The Settings content.
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

            AppearanceSettingsView(onPreview: onPreviewHUD)
                .tabItem {
                    Label(
                        String(localized: "settings.appearance.title"),
                        systemImage: "paintbrush"
                    )
                }

            UpdatesSettingsView(updates: updates)
                .tabItem {
                    Label(
                        String(localized: "settings.updates.title"),
                        systemImage: "arrow.down.circle"
                    )
                }

            AdvancedSettingsView()
                .tabItem {
                    Label(
                        String(localized: "settings.advanced.title"),
                        systemImage: "gearshape.2"
                    )
                }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
