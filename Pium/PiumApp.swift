import SwiftUI

@main
struct PiumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Pium has no document or main window. The launcher panel, menubar
        // item, Settings, and onboarding are all AppKit windows that
        // `AppDelegate` owns. An `App` must still declare a scene, and an
        // empty `Settings` is the inert choice for a menubar agent.
        Settings {
            EmptyView()
        }
    }
}
