import SwiftUI

/// The search surface.
///
/// While the query is empty only the bar is visible; the result list arrives in
/// Phase 2 and expands this surface downward.
struct LauncherView: View {
    let onDismiss: () -> Void

    @State private var query = ""
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        HStack(spacing: Tokens.Spacing.normal) {
            Image(systemName: "magnifyingglass")
                .font(Tokens.TypeScale.query)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(String(localized: "launcher.placeholder"), text: $query)
                .textFieldStyle(.plain)
                .font(Tokens.TypeScale.query)
                .focused($isQueryFocused)
                .accessibilityLabel(String(localized: "launcher.search.accessibilityLabel"))
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .frame(
            width: Tokens.Size.panelWidth,
            height: Tokens.Size.searchFieldHeight
        )
        .background(.regularMaterial, in: .rect(cornerRadius: Tokens.Radius.panel))
        .onAppear {
            // Every opening starts focused on an empty query.
            query = ""
            isQueryFocused = true
        }
    }
}
