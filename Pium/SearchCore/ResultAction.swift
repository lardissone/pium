import Foundation

/// Something the user can do with a result.
///
/// The closure runs on the main actor because every action in this phase
/// touches `NSWorkspace`. Actions are values so a result can carry several and
/// the menu can render them without knowing what they do.
struct ResultAction: Identifiable, Sendable {
    let id: String
    let title: String
    let perform: @Sendable @MainActor () -> Void

    init(id: String, title: String, perform: @escaping @Sendable @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.perform = perform
    }
}
