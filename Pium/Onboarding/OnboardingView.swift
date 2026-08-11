import AppKit
import SwiftUI

/// First-launch screen. One page, and it requests no permissions.
struct OnboardingView: View {
    let shortcut: HotkeyShortcut
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.loose) {
            // Centred across the full width rather than sharing the text's
            // left edge: it is the header of this screen, not another
            // paragraph of it.
            //
            // The wordmark repeats what the title says, so it is decoration to
            // a screen reader rather than a second announcement of the name.
            Image(.piumWordmark)
                .resizable()
                .scaledToFit()
                .frame(width: 300)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            Text(String(localized: "onboarding.title"))
                .font(.largeTitle)

            Text(String(localized: "onboarding.shortcutIntro \(shortcut.displayString)"))

            Text(String(localized: "onboarding.pluginsExplanation"))
                .foregroundStyle(.secondary)

            Text(String(localized: "plugins.whatIsAplugin"))
                .foregroundStyle(.secondary)

            HStack {
                Button(String(localized: "onboarding.revealPluginsFolder")) {
                    revealPluginsFolder()
                }
                Spacer()
                Button(String(localized: "onboarding.finish"), action: onFinish)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Spacing.loose * 2)
        .frame(width: 520)
    }

    /// Creates `~/.config/pium/plugins/` and opens it, so a user who never
    /// installs a plugin still has somewhere obvious to put one.
    private func revealPluginsFolder() {
        let url = URL.homeDirectory
            .appending(path: ".config/pium/plugins", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
