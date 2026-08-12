import Foundation

/// How long a debug session lasts, and whether one is live.
///
/// The preference behind this is a deadline rather than a switch, so a session
/// ends whether or not anybody remembers to end it. Nothing watches the clock:
/// the deadline is read when an event is about to be recorded and when Settings
/// draws itself. A timer would be polling against a budget that reads
/// "approximately 0%; no polling", and it would buy nothing — nobody watches a
/// log that is not being written.
enum DebugLogging {
    /// PRD §14 asks for an opt-in lifecycle without naming one. A day covers
    /// reproducing a bug, including the relaunch many bugs need, and expires
    /// long before a forgotten session becomes a leak.
    static let sessionLength: TimeInterval = 24 * 60 * 60

    static func deadline(from now: Date) -> Date {
        now.addingTimeInterval(sessionLength)
    }

    /// A deadline exactly reached is over. Half-open in the other direction
    /// would leave one instant where the interface says off and the store
    /// still writes.
    static func isActive(expiry: Date?, now: Date) -> Bool {
        guard let expiry else { return false }
        return now < expiry
    }
}
