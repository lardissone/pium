import SwiftUI

/// The search surface.
///
/// While the query is empty only the bar is visible; the result list arrives in
/// Phase 2 and expands this surface downward.
struct LauncherView: View {
    @Bindable var state: LauncherState
    let onDismiss: () -> Void

    @FocusState private var isQueryFocused: Bool

    var body: some View {
        HStack(spacing: Tokens.Spacing.normal) {
            Image(systemName: "magnifyingglass")
                .font(Tokens.TypeScale.query)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(String(localized: "launcher.placeholder"), text: $state.query)
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
        // Not `onAppear`: the panel is hidden rather than destroyed, so the
        // view stays mounted and only the first opening would be reset.
        .onChange(of: state.presentationToken, initial: true) {
            isQueryFocused = true
        }
    }
}
