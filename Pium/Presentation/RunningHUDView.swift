import SwiftUI

/// A HUD's admission that a command is still running: the plugin's name, how
/// long it has been going, and a way to stop it — the same three things
/// `ActiveRunView` shows in the launcher's footer, for the case where the
/// launcher is no longer around to show them.
struct RunningHUDView: View {
    let presentation: RunningPresentation
    let onCancel: () -> Void

    var body: some View {
        // Ticks only while this view exists, the same reasoning as
        // `ActiveRunView`: it is replaced the moment the run ends, so there is
        // nothing here that could keep ticking after that.
        TimelineView(.periodic(from: presentation.startedAt, by: 1)) { context in
            HStack(spacing: Tokens.Spacing.tight) {
                Text(presentation.pluginName)
                    .font(Tokens.TypeScale.resultTitle)
                Text(ElapsedTime.format(elapsedSeconds(at: context.date)))
                    .font(Tokens.TypeScale.resultSubtitle)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: Tokens.Spacing.normal)
                Button(action: onCancel) {
                    Text(String(localized: "launcher.cancel"))
                        .font(Tokens.TypeScale.resultSubtitle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "launcher.cancel"))
            }
            .padding(Tokens.Spacing.normal)
            .frame(width: Tokens.Size.hudWidth, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: Tokens.Radius.panel))
        }
    }

    private func elapsedSeconds(at date: Date) -> Int {
        max(0, Int(date.timeIntervalSince(presentation.startedAt)))
    }
}
