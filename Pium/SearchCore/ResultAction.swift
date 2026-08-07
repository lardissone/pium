import Foundation

/// Something the user can do with a result.
///
/// The closure runs on the main actor because every action in this phase
/// touches `NSWorkspace`. Actions are values so a result can carry several and
/// the menu can render them without knowing what they do.
struct ResultAction: Identifiable, Sendable {
    let id: String
    let title: String
    /// The combination that runs this action, shown next to it and usable
    /// directly from the result list. `nil` for actions reachable only from the
    /// menu.
    let shortcut: ActionShortcut?
    /// The text typed in argument mode, empty when the launcher is not in it.
    /// Most actions have no use for it; a plugin's execute action does.
    let perform: @Sendable @MainActor (String) -> Void

    init(
        id: String,
        title: String,
        shortcut: ActionShortcut? = nil,
        perform: @escaping @Sendable @MainActor (String) -> Void
    ) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.perform = perform
    }
}
