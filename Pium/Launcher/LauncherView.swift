import SwiftUI

/// The search surface. Only the bar is visible while the query is empty; the
/// result list expands the panel downward.
struct LauncherView: View {
    @Bindable var state: LauncherState
    let onDismiss: () -> Void
    let onQueryChanged: (String) -> Void
    let onActivate: (SearchResult) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if !state.results.isEmpty {
                Divider()
                ResultListView(state: state, onActivate: onActivate)
            }
        }
        .frame(width: Tokens.Size.panelWidth)
        .background(.regularMaterial, in: .rect(cornerRadius: Tokens.Radius.panel))
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: state.results.isEmpty
        )
        // Not `onAppear`: the panel is hidden rather than destroyed, so the
        // view stays mounted and only the first opening would be reset.
        .onChange(of: state.presentationToken, initial: true) {
            isQueryFocused = true
        }
        .onChange(of: state.query) { _, text in
            onQueryChanged(text)
        }
    }

    private var searchField: some View {
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
                .onKeyPress(.downArrow) {
                    state.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    state.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.return) {
                    guard let selected = state.selectedResult else { return .handled }
                    onActivate(selected)
                    return .handled
                }
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .frame(height: Tokens.Size.searchFieldHeight)
    }
}
