import SwiftUI

/// The Settings window. The Search, Plugins, Appearance, Updates, and Advanced
/// tabs arrive with the features they configure, in Phases 3 through 7.
struct SettingsView: View {
    let onShortcutChanged: (HotkeyShortcut) -> Void

    var body: some View {
        TabView {
            GeneralSettingsView(onShortcutChanged: onShortcutChanged)
                .tabItem {
                    Label(
                        String(localized: "settings.tab.general"),
                        systemImage: "gearshape"
                    )
                }
        }
    }
}
