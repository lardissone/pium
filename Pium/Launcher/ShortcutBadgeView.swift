import SwiftUI

/// One key combination, rendered as a key cap.
struct ShortcutBadgeView: View {
    let shortcut: ActionShortcut

    var body: some View {
        Text(shortcut.displayString)
            .font(Tokens.TypeScale.shortcutBadge)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                .quaternary,
                in: .rect(cornerRadius: Tokens.Radius.badge)
            )
            // The symbols do not read as words; the combination is announced
            // from the action's own label instead.
            .accessibilityHidden(true)
    }
}
