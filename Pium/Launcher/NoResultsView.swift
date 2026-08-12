import SwiftUI

/// What the launcher shows once a search has finished and found nothing.
///
/// Only after it has finished: `LauncherState.showsNoResults` is what decides,
/// and it waits for every provider. The same row rendered from "the list is
/// empty right now" would flash on the way to showing results.
struct NoResultsView: View {
    var body: some View {
        HStack {
            Text(String(localized: "launcher.noResults"))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, Tokens.Spacing.normal)
        .frame(height: Tokens.Size.resultRowHeight)
        // One announcement rather than a label read off a decorative stack.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "launcher.noResults"))
    }
}
