import SwiftUI

/// General preferences: shortcut, launch at login, and interface language.
struct GeneralSettingsView: View {
    /// Called after the shortcut changes so the hotkey can be re-registered.
    let onShortcutChanged: (HotkeyShortcut) -> Void

    @State private var shortcut = HotkeyShortcut.optionSpace
    @State private var preferredLanguage = PreferredLanguage.system
    @State private var launchAtLogin = false
    @State private var loginItemError: String?

    private let loginItemController = LoginItemController()

    var body: some View {
        Form {
            LabeledContent(String(localized: "settings.general.shortcut")) {
                ShortcutRecorderView(shortcut: $shortcut)
                    .frame(width: 160, height: 24)
            }

            Toggle(String(localized: "settings.general.launchAtLogin"), isOn: $launchAtLogin)

            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Picker(String(localized: "settings.general.language"), selection: $preferredLanguage) {
                Text(String(localized: "settings.language.system"))
                    .tag(PreferredLanguage.system)
                Text(String(localized: "settings.language.english"))
                    .tag(PreferredLanguage.english)
                Text(String(localized: "settings.language.spanish"))
                    .tag(PreferredLanguage.spanish)
            }

            Text(String(localized: "settings.general.languageRestartNote"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(Tokens.Spacing.loose)
        // Fills, like every other section. A fixed width here sized the whole
        // window back when General was the only section and Settings had no
        // navigation; with a sidebar beside it, the same number left the form
        // stranded in the middle of a window twice its width.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            shortcut = Preferences.shared.shortcut
            preferredLanguage = Preferences.shared.preferredLanguage
            launchAtLogin = loginItemController.isEnabled
        }
        .onChange(of: shortcut) { _, newValue in
            Preferences.shared.shortcut = newValue
            onShortcutChanged(newValue)
        }
        .onChange(of: preferredLanguage) { _, newValue in
            Preferences.shared.preferredLanguage = newValue
        }
        .onChange(of: launchAtLogin) { previous, newValue in
            do {
                try loginItemController.setEnabled(newValue)
                loginItemError = nil
            } catch {
                // Report the failure and put the toggle back, rather than
                // showing a state macOS did not accept.
                loginItemError = error.localizedDescription
                launchAtLogin = previous
            }
        }
    }
}
