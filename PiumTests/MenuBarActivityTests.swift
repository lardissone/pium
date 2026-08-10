import Testing
import AppKit
@testable import Pium

@Suite("Menubar activity")
@MainActor
struct MenuBarActivityTests {
    private func controller() -> MenuBarController {
        MenuBarController(
            onOpenLauncher: {}, onOpenSettings: {},
            onOpenPluginsFolder: {}, onReloadPlugins: {}, onCancel: {}
        )
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
