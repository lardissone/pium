import SwiftUI

/// The contextual action menu for the selected result.
///
/// Rendered inside the launcher panel rather than in an `NSPopover`: the panel
/// is non-activating, and a second window would fight it for key status.
struct ActionMenuView: View {
    /// Lets the UI tests find menu rows specifically.
    static let rowAccessibilityIdentifier = "action.row"

    let title: String
    let actions: [ResultAction]
    /// What has been typed into the menu. Shown at the bottom so the user can
    /// see why the list narrowed.
    let filter: String
    let highlightedID: String?
    let onHighlight: (String) -> Void
    let onPerform: (ResultAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Tokens.TypeScale.resultSubtitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, Tokens.Spacing.normal)
                .padding(.vertical, Tokens.Spacing.tight)

            ForEach(actions) { action in
                row(for: action)
            }

            Divider()
                .padding(.top, Tokens.Spacing.tight)

            Text(filter.isEmpty ? String(localized: "launcher.searchActions") : filter)
                .font(Tokens.TypeScale.footerLabel)
                .foregroundStyle(filter.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .padding(.horizontal, Tokens.Spacing.normal)
                .padding(.top, Tokens.Spacing.tight)
                .accessibilityLabel(String(localized: "launcher.searchActions"))
        }
        .padding(.vertical, Tokens.Spacing.tight)
        .frame(width: Tokens.Size.actionMenuWidth)
        .background(.regularMaterial, in: .rect(cornerRadius: Tokens.Radius.menu))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.menu)
                .strokeBorder(.separator)
        )
        .shadow(radius: 12, y: 4)
    }

    private func row(for action: ResultAction) -> some View {
        HStack(spacing: Tokens.Spacing.tight) {
            Text(action.title)
                .font(Tokens.TypeScale.resultTitle)
                .lineLimit(1)

            Spacer(minLength: Tokens.Spacing.normal)

            if let shortcut = action.shortcut {
                ShortcutBadgeView(shortcut: shortcut)
            }
        }
        .padding(.horizontal, Tokens.Spacing.normal)
        .padding(.vertical, Tokens.Spacing.tight)
        .background {
            if action.id == highlightedID {
                RoundedRectangle(cornerRadius: Tokens.Radius.row)
                    .fill(.selection)
            }
        }
        .padding(.horizontal, Tokens.Spacing.tight)
        .contentShape(.rect)
        .onTapGesture { onPerform(action) }
        .onHover { isInside in
            if isInside { onHighlight(action.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(Self.rowAccessibilityIdentifier)
        .accessibilityAddTraits(action.id == highlightedID ? [.isSelected] : [])
    }
}
