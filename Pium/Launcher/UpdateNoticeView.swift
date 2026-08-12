import SwiftUI

/// One row, above the results, saying a version is available.
///
/// Deliberately quiet: PRD §13 calls it discreet, and the launcher's first
/// principle is that the search field is what the eye lands on. It only ever
/// announces — installing is a separate, explicit action the user takes here.
struct UpdateNoticeView: View {
    let update: PendingUpdate
    let onInstall: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Spacing.tight) {
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(String(localized: "update.notice.available \(update.version)"))
                .font(Tokens.TypeScale.footerLabel)

            Spacer(minLength: 0)

            Button(String(localized: "update.notice.install"), action: onInstall)
                .buttonStyle(.link)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "update.notice.dismiss"))
        }
        .padding(.horizontal, Tokens.Spacing.normal)
        .frame(height: Tokens.Size.footerHeight)
    }
}
