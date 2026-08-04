import SwiftUI

/// The bar under the result list. It exists to teach the keyboard: what
/// `Return` will do right now, and that `⌘ K` opens everything else.
struct FooterBarView: View {
    let primaryAction: ResultAction?
    let onOpenActions: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Spacing.tight) {
            Spacer(minLength: 0)

            if let primaryAction {
                Text(primaryAction.title)
                    .font(Tokens.TypeScale.footerLabel)
                if let shortcut = primaryAction.shortcut {
                    ShortcutBadgeView(shortcut: shortcut)
                }

                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, Tokens.Spacing.tight)
            }

            Button(action: onOpenActions) {
                HStack(spacing: Tokens.Spacing.tight) {
                    Text(String(localized: "launcher.actions"))
                        .font(Tokens.TypeScale.footerLabel)
                    ShortcutBadgeView(shortcut: .commandK)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "launcher.actions"))
        }
        .padding(.horizontal, Tokens.Spacing.normal)
        .frame(height: Tokens.Size.footerHeight)
    }
}
