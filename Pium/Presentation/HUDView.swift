import SwiftUI

/// One command's result, as the user reads it.
struct HUDView: View {
    let presentation: HUDPresentation
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
            HStack(spacing: Tokens.Spacing.tight) {
                Image(systemName: presentation.kind == .failure
                    ? "exclamationmark.triangle.fill"
                    : "checkmark.circle.fill")
                    .foregroundStyle(presentation.kind == .failure ? .orange : .secondary)
                Text(presentation.title)
                    .font(Tokens.TypeScale.resultTitle)
                Spacer(minLength: Tokens.Spacing.normal)
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "hud.copy"))
            }
            Text(presentation.body)
                .font(Tokens.TypeScale.resultSubtitle)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Spacing.normal)
        .frame(width: Tokens.Size.hudWidth, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: Tokens.Radius.panel))
    }
}
