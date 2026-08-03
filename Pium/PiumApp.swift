import SwiftUI

@main
struct PiumApp: App {
    var body: some Scene {
        // Pium has no document or main window. The launcher panel, menubar
        // item, and onboarding window are created by AppKit controllers.
        Settings {
            EmptyView()
        }
    }
}
