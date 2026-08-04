import SwiftUI

/// The Settings content.
///
/// The Plugins, Appearance, Updates, and Advanced sections arrive with the
/// features they configure, in Phases 4 through 7.
struct SettingsView: View {
    let frecency: any FrecencyStoring
    let onShortcutChanged: (HotkeyShortcut) -> Void

    var body: some View {
        TabView {
            GeneralSettingsView(onShortcutChanged: onShortcutChanged)
                .tabItem {
                    Label(
                        String(localized: "settings.general.title"),
                        systemImage: "gearshape"
                    )
                }

            SearchSettingsView(frecency: frecency)
                .tabItem {
                    Label(
                        String(localized: "settings.search.title"),
                        systemImage: "magnifyingglass"
                    )
                }
        }
    }
}
