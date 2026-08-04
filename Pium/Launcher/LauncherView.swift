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
                    actions: state.visibleActions,
                    filter: state.actionQuery,
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

            TextField(String(localized: "launcher.placeholder"), text: $state.query)
                .textFieldStyle(.plain)
                .font(Tokens.TypeScale.query)
                .focused($isQueryFocused)
                .accessibilityLabel(String(localized: "launcher.search.accessibilityLabel"))
                // Must come first: with the menu open, typing filters it, and
                // the characters have to be taken before the field inserts
                // them. Rejecting them from the binding is not enough — the
                // field keeps its own buffer while editing and would go on
                // showing text the state no longer holds.
                .onKeyPress(phases: .down) { press in
                    handleMenuTyping(press)
                }
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

    /// Routes typing into the open menu's filter.
    ///
    /// Returns `.ignored` for everything else, including every navigation key
    /// and every combination, so the handlers below and ordinary typing are
    /// untouched while the menu is closed.
    ///
    /// ponytail: characters are taken straight from the event rather than from
    /// a real text field, so the filter does not support input-method
    /// composition. Fine for action names; revisit if a language that needs it
    /// ever has to filter here.
    private func handleMenuTyping(_ press: KeyPress) -> KeyPress.Result {
        guard state.isActionMenuPresented else { return .ignored }
        // A combination is somebody else's: `⌘K`, `⌘Return`, and the rest.
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else {
            return .ignored
        }

        switch press.key {
        case .delete:
            state.deleteLastActionQueryCharacter()
            return .handled
        case .upArrow, .downArrow, .return, .escape, .tab:
            return .ignored
        default:
            let typed = press.characters.filter(\.isTypable)
            guard !typed.isEmpty else { return .ignored }
            state.appendToActionQuery(typed)
            return .handled
        }
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

private extension Character {
    /// Whether this is a character the user meant to type, as opposed to a
    /// control code arriving as the event's text.
    var isTypable: Bool {
        isLetter || isNumber || isPunctuation || isSymbol || self == " "
    }
}
