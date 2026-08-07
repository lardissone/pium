import SwiftUI

/// The search surface. Only the bar is visible while the query is empty; the
/// result list and its footer expand the panel downward.
struct LauncherView: View {
    @Bindable var state: LauncherState
    /// Read for `activeRecord` alone: while a run is in progress, its footer
    /// replaces the shortcut one, and Cancel is this manager's own.
    let executionManager: ExecutionManager
    let onDismiss: () -> Void
    let onQueryChanged: (String) -> Void
    /// Both halves of what happened, because the result is what usage history
    /// learns from and the action alone does not name it.
    let onPerform: (SearchResult, ResultAction) -> Void

    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if !state.results.isEmpty {
                Divider()
                ResultListView(state: state) { result in
                    // Selecting first, then running the same path `Return`
                    // does, is what makes a double click subject to the same
                    // gates: the row it names becomes the one `Return` would
                    // act on, confirmation included. `select` itself clears
                    // any confirmation pending for a *different* row, so one
                    // cannot be read as an answer about this one.
                    state.select(id: result.id)
                    activateSelected()
                }
            }
            if let confirming = state.confirmingResult, let message = confirming.confirmation {
                Divider()
                ConfirmationBarView(
                    message: message,
                    onConfirm: { confirmSelected() },
                    onCancel: { state.cancelConfirmation() }
                )
            } else if let active = executionManager.activeRecord {
                Divider()
                ActiveRunView(pluginName: active.pluginName, startedAt: active.startedAt) {
                    executionManager.cancel(active.id)
                }
            } else if !state.results.isEmpty {
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
                    onPerform: { attemptToPerform($0, on: selected) }
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

            // Always a slot, so the field below keeps its position and with it
            // its identity: anything that remounts the field costs the focus
            // and empties the text it was holding.
            pill

            queryField
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .frame(height: Tokens.Size.searchFieldHeight)
        .onChange(of: state.isInArgumentMode) { _, isOn in
            // Leaving restores the search the user was in the middle of, which
            // entering cleared.
            if !isOn { onQueryChanged(state.query) }
        }
    }

    /// What the field edits: the search, or the selected plugin's argument.
    private var fieldText: Binding<String> {
        guard state.isInArgumentMode else { return $state.query }
        return Binding(
            get: { state.argumentText },
            set: { state.setArgumentText($0) }
        )
    }

    private var fieldPlaceholder: String {
        guard let request = state.argumentTarget?.argument else {
            return String(localized: "launcher.placeholder")
        }
        return request.placeholder ?? String(localized: "launcher.argument.placeholder")
    }

    private var fieldAccessibilityLabel: String {
        guard let target = state.argumentTarget else {
            return String(localized: "launcher.search.accessibilityLabel")
        }
        return String(localized: "launcher.argument.accessibilityLabel \(target.title)")
    }

    /// Names the plugin the typed text is going to. Present but empty outside
    /// argument mode.
    @ViewBuilder
    private var pill: some View {
        if let target = state.argumentTarget {
            PluginPillView(title: target.title) { state.exitArgumentMode() }
        }
    }

    /// One field throughout. Argument mode swaps what it is bound to rather
    /// than what is on screen, so the text the user is editing changes without
    /// the field itself ever going away.
    private var queryField: some View {
        TextField(fieldPlaceholder, text: fieldText)
            .textFieldStyle(.plain)
            .font(Tokens.TypeScale.query)
            .focused($isQueryFocused)
            .accessibilityLabel(fieldAccessibilityLabel)
            // Must come first: with the menu open, typing filters it, and
            // the characters have to be taken before the field inserts
            // them. Rejecting them from the binding is not enough — the
            // field keeps its own buffer while editing and would go on
            // showing text the state no longer holds.
            .onKeyPress(phases: .down) { press in
                handleMenuTyping(press)
            }
            .onKeyPress(phases: .down) { press in
                handleArgumentTyping(press)
            }
            .onKeyPress(.escape) {
                // The PRD: with the menu open, the first Esc returns to search
                // rather than closing the launcher. A pending confirmation and
                // argument mode get the same courtesy before the launcher
                // closes.
                if state.isActionMenuPresented {
                    state.dismissActionMenu()
                } else if state.confirmingResult != nil {
                    state.cancelConfirmation()
                } else if state.isInArgumentMode {
                    state.exitArgumentMode()
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

        // Delete arrives as backspace or as DEL depending on the path, and
        // matching `KeyEquivalent.delete` alone misses one of them — the key
        // then falls through to the field, which deletes from the search query
        // instead. Always handled while the menu is open, even with an empty
        // filter, so it can never reach the query behind it.
        if press.key.character == "\u{8}" || press.key.character == "\u{7F}" {
            state.deleteLastActionQueryCharacter()
            return .handled
        }

        switch press.key {
        case .upArrow, .downArrow, .return, .escape, .tab:
            return .ignored
        default:
            let typed = press.characters.filter(\.isTypable)
            guard !typed.isEmpty else { return .ignored }
            state.appendToActionQuery(typed)
            return .handled
        }
    }

    /// Enters argument mode, then routes typing into the plugin's argument.
    ///
    /// A space on a selected plugin that takes input enters; after that every
    /// ordinary keystroke belongs to the plugin rather than to the query, and
    /// is taken before the field can insert it. Returns `.ignored` otherwise,
    /// so a space anywhere else is an ordinary space and the handlers below are
    /// untouched.
    private func handleArgumentTyping(_ press: KeyPress) -> KeyPress.Result {
        guard !state.isActionMenuPresented else { return .ignored }

        // A pending confirmation freezes the argument exactly as it was
        // typed. `.handled`, not `.ignored`: `LauncherState`'s mutators
        // already no-op while confirming, but rejecting a keystroke only in
        // the binding is not enough — per the comment on `queryField` above,
        // the field keeps its own buffer while editing, so an ignored
        // keystroke would still move it, leaving the user reading text that
        // is not what the confirmation in front of them is actually about.
        // `Return` and `Esc` still have to reach their own handlers below:
        // they are how this confirmation gets answered or cancelled.
        if state.isInArgumentMode, state.confirmingResult != nil {
            switch press.key {
            case .return, .escape:
                return .ignored
            default:
                return .handled
            }
        }

        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else {
            return .ignored
        }

        if !state.isInArgumentMode {
            guard press.characters == " ", state.enterArgumentMode() else { return .ignored }
            return .handled
        }

        // Typing goes to the field, which is bound to the argument — only the
        // backspace that would delete nothing has to be taken, because that one
        // means "leave" rather than "delete". Delete arrives as backspace or as
        // DEL depending on the path.
        let isDelete = press.key.character == "\u{8}" || press.key.character == "\u{7F}"
        guard isDelete, state.argumentText.isEmpty else { return .ignored }
        state.exitArgumentMode()
        return .handled
    }

    /// The arrows drive whichever list is in front of the user. A pending
    /// confirmation pins the selection to the row it is asking about, so the
    /// arrows do nothing until it is resolved.
    private func move(by offset: Int) {
        if state.isActionMenuPresented {
            state.moveActionHighlight(by: offset)
        } else if state.confirmingResult == nil {
            state.moveSelection(by: offset)
        }
    }

    /// With the menu open, `Return` runs whatever is highlighted. With it
    /// closed, the combination is looked up among the selected result's actions
    /// rather than assumed, so a new action needs no change here.
    private func handleReturn(modifiers: ActionShortcut.Modifiers) -> KeyPress.Result {
        if state.isInArgumentMode {
            guard let target = state.argumentTarget else { return .handled }
            // A required argument that is empty blocks the run — and blocks
            // even asking, per the PRD: confirming is about whether to run,
            // not a way around the gate that decides whether it could.
            if target.argument?.isRequired == true, !state.isArgumentSatisfied {
                return .handled
            }
            guard let action = target.actions.first(where: { $0.id == "execute" }) else {
                return .handled
            }
            attemptToPerform(action, on: target)
            return .handled
        }
        guard let selected = state.selectedResult else { return .handled }

        if state.isActionMenuPresented {
            guard let highlighted = state.highlightedAction else { return .handled }
            attemptToPerform(highlighted, on: selected)
            return .handled
        }

        activateSelected(modifiers: modifiers)
        return .handled
    }

    /// Resolves the selected result's `Return`-shortcut action — the one
    /// `Return` runs — then routes it through `attemptToPerform`. Shared by
    /// the keyboard path above and a double click in the result list.
    @discardableResult
    private func activateSelected(modifiers: ActionShortcut.Modifiers = []) -> Bool {
        guard let selected = state.selectedResult else { return false }
        guard let action = state.action(matching: .return, modifiers: modifiers) else {
            return false
        }
        attemptToPerform(action, on: selected)
        return true
    }

    /// Runs `action` on `result` unless `state.attemptToRun` — the gate
    /// every path that can start a run goes through — decides a confirmation
    /// has to show first instead. Shared by every one of those paths: the
    /// keyboard, a double click, and the action menu, both by key and by
    /// mouse, so none of them can bypass `confirmBeforeRun` (PRD §10.4).
    ///
    /// Resolving which action is meant *before* calling this matters —
    /// `⌘ Return` on a plugin means Reveal JSON, not the run `confirmBeforeRun`
    /// is about, and `attemptToRun` only gates the latter.
    private func attemptToPerform(_ action: ResultAction, on result: SearchResult) {
        guard state.attemptToRun(action, on: result) else { return }
        perform(action, on: result, input: state.argumentText)
    }

    /// What the confirmation bar's Confirm button does — the same as
    /// pressing plain `Return` while its message is showing. Looked up from
    /// `confirmingResult` itself rather than `state.selectedResult`, because
    /// a confirmation begun from argument mode has no selected row: `results`
    /// is empty there by PRD §10.3.
    private func confirmSelected() {
        guard let confirming = state.confirmingResult else { return }
        state.cancelConfirmation()
        guard let action = confirming.actions.first(where: { $0.shortcut == .returnKey }) else {
            return
        }
        perform(action, on: confirming, input: state.argumentText)
    }

    /// Running any action closes the launcher, exactly as `Return` on a result
    /// does, and reports the pair so the panel can record the selection.
    private func perform(_ action: ResultAction, on result: SearchResult, input: String) {
        state.dismissActionMenu()
        onDismiss()
        onPerform(result, action)
        action.perform(input)
    }
}

private extension Character {
    /// Whether this is a character the user meant to type, as opposed to a
    /// control code arriving as the event's text.
    var isTypable: Bool {
        isLetter || isNumber || isPunctuation || isSymbol || self == " "
    }
}

/// Replaces `FooterBarView` while a result's `confirmBeforeRun` message is
/// showing (PRD §10.4): the manifest's message on the left, `Return` to
/// confirm and `Esc` to go back on the right, in `FooterBarView`'s own
/// register of a label next to its shortcut badge.
private struct ConfirmationBarView: View {
    let message: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Spacing.tight) {
            Text(message)
                .font(Tokens.TypeScale.footerLabel)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: onCancel) {
                HStack(spacing: Tokens.Spacing.tight) {
                    Text(String(localized: "launcher.confirmCancel"))
                        .font(Tokens.TypeScale.footerLabel)
                    ShortcutBadgeView(shortcut: .escape)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "launcher.confirmCancel"))

            Divider()
                .frame(height: 14)
                .padding(.horizontal, Tokens.Spacing.tight)

            Button(action: onConfirm) {
                HStack(spacing: Tokens.Spacing.tight) {
                    Text(String(localized: "launcher.confirm"))
                        .font(Tokens.TypeScale.footerLabel)
                    ShortcutBadgeView(shortcut: .returnKey)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "launcher.confirm"))
        }
        .padding(.horizontal, Tokens.Spacing.normal)
        .frame(height: Tokens.Size.footerHeight)
    }
}
