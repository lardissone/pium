import SwiftUI

/// One row, above the results, saying a version is available.
///
/// Deliberately quiet: PRD §13 calls it discreet, and the launcher's first
/// principle is that the search field is what the eye lands on. It only ever
/// announces — installing is a separate, explicit action the user takes here.
///
/// There is no way to dismiss it, by design. Sparkle hands a scheduled update
/// over on the understanding that the reminder stays until it is answered: it
/// holds the update session open and its check timer stays stopped for as long
/// as it waits. Installing is what ends that session and starts the timer
/// again, so a row that could be sent away would leave the app never checking
/// for another version until it is relaunched.
struct UpdateNoticeView: View {
    let update: PendingUpdate
    let onInstall: () -> Void

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
        }
        .padding(.horizontal, Tokens.Spacing.normal)
        .frame(height: Tokens.Size.footerHeight)
    }
}
