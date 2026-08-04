import SwiftUI

/// The scrolling result list. Keeps the selected row visible as the selection
/// moves, and treats a double click as activation.
struct ResultListView: View {
    @Bindable var state: LauncherState
    let onActivate: (SearchResult, ResultAction) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(state.results) { result in
                        ResultRowView(result: result, isSelected: result.id == state.selectedID)
                            .id(result.id)
                            // A row with no actions has nothing to activate,
                            // and a double click on one must not be recorded as
                            // a selection either.
                            .onTapGesture(count: 2) {
                                guard let action = result.primaryAction else { return }
                                onActivate(result, action)
                            }
                            // Simultaneous, not chained: a plain second
                            // `onTapGesture` would wait out the double-click
                            // window before selecting, which reads as a hang.
                            .simultaneousGesture(
                                TapGesture().onEnded { state.select(id: result.id) }
                            )
                    }
                }
                .padding(.vertical, Tokens.Spacing.tight)
            }
            .frame(maxHeight: Tokens.Size.maxResultListHeight)
            .onChange(of: state.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}
