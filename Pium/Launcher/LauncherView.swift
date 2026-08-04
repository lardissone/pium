import SwiftUI

/// The search surface. Only the bar is visible while the query is empty; the
/// result list and its footer expand the panel downward.
struct LauncherView: View {
    @Bindable var state: LauncherState
    let onDismiss: () -> Void
    let onQueryChanged: (String) -> Void
    let onActivate: (SearchResult) -> Void

    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if !state.results.isEmpty {
                Divider()
                ResultListView(state: state, onActivate: onActivate)
                Divider()
                FooterBarView(primaryAction: state.selectedResult?.primaryAction) {
                    state.presentActionMenu()
                }
            }
        }
        .frame(width: Tokens.Size.panelWidth)
        .background(.regularMaterial, in: .rect(cornerRadius: Tokens.Radius.panel))
        // Anchored to the bottom trailing corner, just above the footer, so the
        // eye travels from the Actions affordance to the menu it opened.
        .overlay(alignment: .bottomTrailing) {
            if state.isActionMenuPresented, let selected = state.selectedResult {
                ActionMenuView(
                    title: selected.title,
                    actions: selected.actions,
                    highlightedID: state.highlightedActionID,
                    onHighlight: { state.highlightAction(id: $0) },
                    onPerform: { perform($0) }
                )
                .padding(.trailing, Tokens.Spacing.normal)
                .padding(.bottom, Tokens.Size.footerHeight + Tokens.Spacing.tight)
            }
        }
        // Pinned to the top: the panel is resized in one step by AppKit, and
        // without this the hosting view centres the content vertically, so the
        // search field slides while the two heights disagree.
        .frame(maxHeight: .infinity, alignment: .top)
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

            TextField(
                String(localized: "launcher.placeholder"),
                text: Binding(get: { state.query }, set: { state.updateQuery($0) })
            )
                .textFieldStyle(.plain)
                .font(Tokens.TypeScale.query)
                .focused($isQueryFocused)
                .accessibilityLabel(String(localized: "launcher.search.accessibilityLabel"))
                .onKeyPress(.escape) {
                    // The PRD: with the menu open, the first Esc returns to
                    // search rather than closing the launcher.
                    if state.isActionMenuPresented {
                        state.dismissActionMenu()
                    } else {
                        onDismiss()
                    }
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    move(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    move(by: -1)
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { press in
                    handleReturn(modifiers: ActionShortcut.Modifiers(press.modifiers))
                }
                .onKeyPress(KeyEquivalent("k"), phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    state.presentActionMenu()
                    return .handled
                }
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .frame(height: Tokens.Size.searchFieldHeight)
    }

    /// The arrows drive whichever list is in front of the user.
    private func move(by offset: Int) {
        if state.isActionMenuPresented {
            state.moveActionHighlight(by: offset)
        } else {
            state.moveSelection(by: offset)
        }
    }

    /// With the menu open, `Return` runs whatever is highlighted. With it
    /// closed, the combination is looked up among the selected result's actions
    /// rather than assumed, so a new action needs no change here.
    private func handleReturn(modifiers: ActionShortcut.Modifiers) -> KeyPress.Result {
        if state.isActionMenuPresented {
            guard let highlighted = state.highlightedAction else { return .handled }
            perform(highlighted)
            return .handled
        }
        guard let action = state.action(matching: .return, modifiers: modifiers) else {
            return .handled
        }
        perform(action)
        return .handled
    }

    /// Running any action closes the launcher, exactly as `Return` on a result
    /// does.
    private func perform(_ action: ResultAction) {
        state.dismissActionMenu()
        onDismiss()
        action.perform()
    }
}
