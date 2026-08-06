import Testing
import AppKit
@testable import Pium

@Suite("Settings menu item")
@MainActor
struct SettingsMenuItemTests {
    /// The app menu macOS builds for a SwiftUI `App`: a submenu holding the
    /// `Settings…` item, rather than the item at the top level.
    private func appMenu(keyEquivalent: String = ",") -> NSMenu {
        let item = NSMenuItem(
            title: "Settings…",
            action: Selector(("showSettingsWindow:")),
            keyEquivalent: keyEquivalent
        )
        item.keyEquivalentModifierMask = .command
        let submenu = NSMenu()
        submenu.addItem(NSMenuItem(title: "About Pium", action: nil, keyEquivalent: ""))
        submenu.addItem(item)

        let application = NSMenuItem()
        application.submenu = submenu
        let menu = NSMenu()
        menu.addItem(application)
        return menu
    }

    @Test func itFindsTheCommandCommaItemAndRewiresIt() {
        let menu = appMenu()
        let target = NSObject()

        #expect(SettingsMenuItem.retarget(in: menu, to: target, action: #selector(NSObject.self.description as () -> String)) == true)

        let item = menu.items[0].submenu?.items[1]
        #expect(item?.target === target)
    }

    /// A menu with no such item must say so rather than rewiring something else.
    @Test func itReportsWhenThereIsNothingToRewire() {
        let menu = appMenu(keyEquivalent: "q")
        #expect(
            SettingsMenuItem.retarget(
                in: menu, to: NSObject(), action: #selector(NSObject.self.description as () -> String)
            ) == false
        )
    }
}
