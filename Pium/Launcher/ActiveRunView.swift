import SwiftUI

/// How long a command has been running, for a footer that updates once a
/// second. Deliberately not a `DateFormatter`: this is a stopwatch, not a
/// time of day, and it must read the same in every language.
enum ElapsedTime {
    static func format(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds)s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Shown in place of `FooterBarView` while a plugin is running (PRD §11):
/// its name, how long it has been going, and a way to stop it.
///
/// Reopening Pium during a run must show elapsed time measured from when the
/// run started, not from when this view appeared — `startedAt` is the
/// record's own timestamp, carried in from `ExecutionRecord`.
struct ActiveRunView: View {
    let pluginName: String
    let startedAt: Date
    let onCancel: () -> Void

    var body: some View {
        // The tick lives only inside this view's own tree: it stops existing,
        // rather than merely going unused, the moment the run ends and this
        // view is replaced by `FooterBarView`. Nothing here is a `Timer` that
        // could outlive the launcher panel.
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            HStack(spacing: Tokens.Spacing.tight) {
                Text(String(localized: "launcher.running \(pluginName)"))
                    .font(Tokens.TypeScale.footerLabel)
                Text(ElapsedTime.format(elapsedSeconds(at: context.date)))
                    .font(Tokens.TypeScale.footerLabel)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer(minLength: 0)

                Button(action: onCancel) {
                    Text(String(localized: "launcher.cancel"))
                        .font(Tokens.TypeScale.footerLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "launcher.cancel"))
            }
            .padding(.horizontal, Tokens.Spacing.normal)
            .frame(height: Tokens.Size.footerHeight)
        }
    }

    private func elapsedSeconds(at date: Date) -> Int {
        max(0, Int(date.timeIntervalSince(startedAt)))
    }
}
