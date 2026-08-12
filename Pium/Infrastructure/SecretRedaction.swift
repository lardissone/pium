import Foundation

/// Removes the secret values one run loaded from that run's own output.
///
/// The second of redaction's three layers. The first keeps a secret out of the
/// logger entirely — `DebugEvent` records environment names, never values.
/// This one exists for what the first cannot reach: a script that prints what
/// it was given, a `curl -v`, a traceback carrying the URL with the key in it.
///
/// It scrubs values, not patterns. Pium knows exactly which strings it handed
/// this run, and looking for those is the only thing it can do without
/// guessing at what a secret looks like.
struct SecretRedaction: Sendable {
    static let marker = "<redacted>"

    private let values: [String]

    init(values: [String]) {
        // A field nobody filled would otherwise replace every empty position
        // in the output, which is every position.
        self.values = values.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func scrub(_ text: String) -> String {
        values.reduce(text) { scrubbed, value in
            scrubbed.replacingOccurrences(of: value, with: Self.marker)
        }
    }
}
