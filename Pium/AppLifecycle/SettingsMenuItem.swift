import AppKit

/// Points the app menu's `Settings…` item at the window Pium actually owns.
///
/// An `App` must declare a scene, and `Settings { EmptyView() }` is the inert
/// choice for a menubar agent — but macOS still builds a `Settings…` item for
/// it, and `⌘,` therefore opens that empty scene. The scene stays, because
/// removing it takes the standard Edit menu with it and the search field loses
/// paste. Rewiring the one item is what makes the shortcut reach the real
/// Settings window.
@MainActor
enum SettingsMenuItem {
    /// Rewires the `⌘,` item wherever it sits in `menu`, reporting whether one
    /// was found — a silent no-op would leave the shortcut opening an empty
    /// window with nothing to say why.
    @discardableResult
    static func retarget(in menu: NSMenu, to target: AnyObject, action: Selector) -> Bool {
        for item in menu.items {
            if item.keyEquivalent == ",", item.keyEquivalentModifierMask == .command {
                item.target = target
                item.action = action
                return true
            }
            if let submenu = item.submenu, retarget(in: submenu, to: target, action: action) {
                return true
            }
        }
        return false
    }
}
