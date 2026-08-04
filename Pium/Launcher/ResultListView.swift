import SwiftUI

/// The scrolling result list. Keeps the selected row visible as the selection
/// moves, and treats a double click as activation.
struct ResultListView: View {
    @Bindable var state: LauncherState
    let onActivate: (SearchResult) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(state.results) { result in
                        ResultRowView(result: result, isSelected: result.id == state.selectedID)
                            .id(result.id)
                            .onTapGesture(count: 2) { onActivate(result) }
                            .onTapGesture { state.select(id: result.id) }
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
