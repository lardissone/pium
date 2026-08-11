import Foundation

/// What a finished run puts on screen, or `nil` for the runs that say nothing.
///
/// PRD §10.7 in one place: `silent` is silent about success, `toast` shows what
/// the command printed, and a failure is shown whatever the mode. A cancelled
/// run shows nothing — the user pressed Cancel and does not need telling.
struct HUDPresentation: Equatable, Sendable {
    enum Kind: Sendable { case success, failure }

    /// PRD §11: an error remains visible longer than a success message.
    static let successDuration: Duration = .seconds(4)
    static let failureDuration: Duration = .seconds(10)

    let kind: Kind
    let title: String
    let body: String
    let duration: Duration

    static func forOutcome(
        _ record: ExecutionRecord,
        mode: PluginOutputMode
    ) -> HUDPresentation? {
        switch record.state {
        case .running, .cancelled:
            nil
        case .finished(let code) where code == 0:
            mode == .toast ? success(record) : nil
        case .finished(let code):
            failure(record, body: exitBody(record, code: code))
        case .timedOut:
            failure(record, body: String(localized: "hud.timedOut"))
        case .signalled(let signal):
            // An `Int` interpolation asks the catalog for `%lld`, which is how
            // every numeric string in it is keyed. An `Int32` would ask for
            // `%d` and match nothing, leaving the key itself on screen.
            failure(record, body: String(localized: "hud.signalled \(Int(signal))"))
        case .failed(let cause):
            failure(record, body: cause.message)
        }
    }

    private static func success(_ record: ExecutionRecord) -> HUDPresentation? {
        let body = text(record.standardOutput, truncated: record.wasTruncated)
        guard !body.isEmpty else { return nil }
        return HUDPresentation(
            kind: .success, title: record.pluginName, body: body, duration: successDuration
        )
    }

    private static func failure(_ record: ExecutionRecord, body: String) -> HUDPresentation {
        HUDPresentation(
            kind: .failure, title: record.pluginName, body: body, duration: failureDuration
        )
    }

    /// A non-zero exit is explained by whatever the command said on `stderr`;
    /// with nothing said, the code is all there is.
    private static func exitBody(_ record: ExecutionRecord, code: Int32) -> String {
        let error = text(record.standardError, truncated: record.wasTruncated)
        // `Int(code)` for the same reason as `hud.signalled` above.
        return error.isEmpty ? String(localized: "hud.exited \(Int(code))") : error
    }

    /// How many lines of a command's output a HUD can hold, matching
    /// `HUDView`'s own limit. Beyond it the text is not drawn, but it is still
    /// measured: `fittingSize` walks the whole string to size the panel, so a
    /// 64 KB body costs that walk on every layout pass to show eight lines.
    private static let bodyLineLimit = 8

    /// A ceiling on characters as well as lines: eight lines is no bound at
    /// all when a command prints 64 KB without a single newline, which is
    /// ordinary for a program piping JSON. Generous enough that eight full
    /// lines at the HUD's width always survive it.
    private static let bodyCharacterLimit = 2_000

    private static func text(_ raw: String, truncated: Bool) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var shown = String(trimmed.prefix(bodyCharacterLimit))
        let lines = shown.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > bodyLineLimit {
            shown = lines.prefix(bodyLineLimit).joined(separator: "\n")
        }
        // Cut past what can be shown, and say so — the same sentence a run
        // truncated at the byte cap already uses, since from the reader's side
        // the two are one fact: this is not all of it.
        guard truncated || shown.count < trimmed.count, !shown.isEmpty else { return shown }
        return shown + "\n" + String(localized: "hud.truncated")
    }
}
