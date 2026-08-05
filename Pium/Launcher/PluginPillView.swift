import SwiftUI

/// Names the plugin the typed text is going to.
///
/// PRD §10.3: argument mode must visibly replace the global search context, so
/// it is clear that what follows is not a search. Clicking it returns.
struct PluginPillView: View {
    let title: String
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            Text(title)
                .font(Tokens.TypeScale.query)
                .padding(.horizontal, Tokens.Spacing.normal)
                .padding(.vertical, Tokens.Spacing.tight)
                .background(.tint.opacity(0.2), in: .rect(cornerRadius: Tokens.Radius.panel / 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "launcher.argument.leave \(title)"))
    }
}
