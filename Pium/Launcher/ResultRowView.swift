import SwiftUI

/// One row of the result list.
struct ResultRowView: View {
    let result: SearchResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Tokens.Spacing.normal) {
            icon
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(Tokens.TypeScale.resultTitle)
                    .lineLimit(1)
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(Tokens.TypeScale.resultSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .padding(.vertical, Tokens.Spacing.tight)
        .frame(height: Tokens.Size.resultRowHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Tokens.Radius.row)
                    .fill(.selection)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var icon: some View {
        switch result.iconSource {
        case .applicationBundle(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
        case .systemSymbol(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}
