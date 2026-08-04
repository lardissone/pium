import SwiftUI

/// The Settings content.
///
/// There is one section, so there is no tab bar: a `TabView` with a single tab
/// renders as a lone pill and collapses its content when hosted in AppKit. The
/// Search, Plugins, Appearance, Updates, and Advanced sections arrive with the
/// features they configure, in Phases 3 through 7, and the tab bar comes back
/// with the second one.
struct SettingsView: View {
    let onShortcutChanged: (HotkeyShortcut) -> Void

    var body: some View {
        GeneralSettingsView(onShortcutChanged: onShortcutChanged)
    }
}
