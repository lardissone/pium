import Testing
import AppKit
@testable import Pium

@Suite("Menubar activity")
@MainActor
struct MenuBarActivityTests {
    private func controller(
        onOpenAbout: @escaping () -> Void = {},
        onCheckForUpdates: @escaping () -> Void = {}
    ) -> MenuBarController {
        MenuBarController(
            onOpenLauncher: {}, onOpenSettings: {},
            onOpenPluginsFolder: {}, onReloadPlugins: {}, onCancel: {},
            onOpenAbout: onOpenAbout,
            onCheckForUpdates: onCheckForUpdates
        )
    }

    /// `LSUIElement` leaves Pium without an application menu, so this menu is
    /// the only route to About. It survives a run starting and ending, since
    /// `setActive` rebuilds the whole menu (PIUM-33).
    @Test func aboutIsReachableWhetherOrNotSomethingIsRunning() {
        let controller = controller()
        #expect(controller.menu.items.contains { $0.identifier?.rawValue == "about" })
        controller.setActive("Probe")
        #expect(controller.menu.items.contains { $0.identifier?.rawValue == "about" })
    }

    @Test func theAboutItemOpensAbout() throws {
        final class Opened { var value = false }
        let opened = Opened()
        let controller = controller { opened.value = true }
        let item = try #require(
            controller.menu.items.first { $0.identifier?.rawValue == "about" }
        )
        _ = item.target?.perform(item.action, with: item)
        #expect(opened.value)
    }

    /// PRD §6.1 lists "check for updates" among the menu's entries.
    @Test func theMenuOffersToCheckForUpdates() throws {
        final class Checks { var count = 0 }
        let checks = Checks()
        let controller = controller(onCheckForUpdates: { checks.count += 1 })
        let item = try #require(
            controller.menu.items.first { $0.identifier?.rawValue == "checkForUpdates" }
        )
        _ = item.target?.perform(item.action, with: item)
        #expect(checks.count == 1)
    }

    @Test func thereIsNoCancelItemWhileNothingRuns() {
        let menu = controller().menu
        #expect(!menu.items.contains { $0.identifier?.rawValue == "cancel" })
    }

    @Test func acancelItemNamesTheRunningPlugin() {
        let controller = controller()
        controller.setActive("Probe")
        let cancel = controller.menu.items.first { $0.identifier?.rawValue == "cancel" }
        #expect(cancel != nil)
        #expect(cancel?.title.contains("Probe") == true)
    }

    @Test func itGoesAwayWhenTheRunEnds() {
        let controller = controller()
        controller.setActive("Probe")
        controller.setActive(nil)
        #expect(!controller.menu.items.contains { $0.identifier?.rawValue == "cancel" })
    }
}
