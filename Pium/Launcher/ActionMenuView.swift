import SwiftUI

/// The `⌘ Return` contextual menu for the selected result.
struct ActionMenuView: View {
    let actions: [ResultAction]
    let onPerform: (ResultAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(actions) { action in
                Button {
                    onPerform(action)
                } label: {
                    Text(action.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Tokens.Spacing.normal)
                        .padding(.vertical, Tokens.Spacing.tight)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Tokens.Spacing.tight)
        .frame(width: 240)
        .background(.regularMaterial, in: .rect(cornerRadius: Tokens.Radius.row))
    }
}
