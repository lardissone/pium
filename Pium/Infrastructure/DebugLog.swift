import Foundation

/// What every call site talks to.
///
/// The point of a facade here is the off path. `record` takes an autoclosure,
/// so an event is not built — no string interpolated, no array copied — unless
/// a session is live. Search and execution call this from inside a 50 ms
/// budget, and an event that is never recorded must cost nothing to not
/// record.
///
/// The deadline is also settled here rather than inside the store, because
/// this is the main actor, and the main actor is where every other preference
/// is written.
@MainActor
enum DebugLog {
    /// Replaced in tests. There is one log for the app, the same way there is
    /// one `Preferences.shared`.
    static var store = DebugLogStore()
    static var preferences = Preferences.shared

    /// Whether a session is live right now — what Settings draws itself from.
    static var isRecording: Bool {
        DebugLogging.isActive(expiry: preferences.debugLoggingExpiry, now: Date())
    }

    static func record(_ event: @autoclosure () -> DebugEvent) {
        guard let expiry = preferences.debugLoggingExpiry else { return }
        guard DebugLogging.isActive(expiry: expiry, now: Date()) else {
            // The session ended while nobody was looking. Clearing it here
            // keeps the interface from claiming otherwise, and means the next
            // event costs one optional read.
            preferences.debugLoggingExpiry = nil
            return
        }
        let event = event()
        Task { [store] in await store.write(event) }
    }
}
