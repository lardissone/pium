import AppKit
import SwiftUI

/// First-launch screen. One page, and it requests no permissions.
struct OnboardingView: View {
    let shortcut: HotkeyShortcut
    let access: ProtectedFolderAccess
    let onFinish: () -> Void

    @State private var hasAskedForFolders = false

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

            VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
                Button(String(localized: "onboarding.allowFolders")) {
                    Task { await requestFolderAccess() }
                }
                .disabled(hasAskedForFolders)

                Text(String(localized: "onboarding.allowFoldersExplanation"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

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

    /// Asks about all three folders at once. `async` so the test can wait for
    /// the prompts to have been raised; the button does not care when they
    /// finish.
    ///
    /// Not `private`, for the same reason `LauncherView.handleReturn` is not:
    /// this is the decision, and a test reaches it without a window.
    func requestFolderAccess() async {
        hasAskedForFolders = true
        await withCheckedContinuation { continuation in
            access.request(ProtectedFolder.allCases) { _ in
                continuation.resume()
            }
        }
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
