import SwiftUI

@main
struct PiumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Pium has no document or main window. The launcher panel, menubar
        // item, and onboarding window are created by AppKit controllers that
        // `AppDelegate` owns.
        Settings {
            SettingsView { shortcut in
                appDelegate.registerShortcut(shortcut)
            }
        }
    }
}
