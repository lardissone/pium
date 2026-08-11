import SwiftUI

/// What Pium is, which build this is, and where it came from.
struct AboutView: View {
    /// Read from the bundle rather than passed in: the version is a fact about
    /// the build, and threading it through the caller would only add a way for
    /// the two to disagree.
    private var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(marketing) (\(build))"
    }

    var body: some View {
        VStack(spacing: Tokens.Spacing.normal) {
            Image(.piumWordmark)
                .resizable()
                .scaledToFit()
                .frame(width: 220)
                // The wordmark already says "Pium", so a screen reader that
                // announced both would say it twice.
                .accessibilityHidden(true)

            Text(String(localized: "about.version \(version)"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            VStack(spacing: Tokens.Spacing.tight) {
                Text(String(localized: "about.copyright"))
                Text(String(localized: "about.licence"))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Link(
                String(localized: "about.repository"),
                destination: URL(string: "https://github.com/lardissone/pium")!
            )
            .font(.footnote)
        }
        .multilineTextAlignment(.center)
        .padding(Tokens.Spacing.loose * 2)
        .frame(width: 360)
    }
}
