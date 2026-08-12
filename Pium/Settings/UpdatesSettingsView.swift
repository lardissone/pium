import SwiftUI

/// PRD §12's Updates section: status, the automatic-check switch, and a
/// button for the person who does not want to wait six hours.
struct UpdatesSettingsView: View {
    let updates: any UpdateAvailability

    /// The switch's position, so flipping it redraws. The value it starts from
    /// is read from the updater rather than remembered: Sparkle asks for this
    /// permission itself on a first launch, and the Settings window is built
    /// once and reused, so a position captured at first open would still be on
    /// screen long after it stopped being true.
    @State private var automatic: Bool

    init(updates: any UpdateAvailability) {
        self.updates = updates
        _automatic = State(initialValue: updates.automaticallyChecks)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "settings.updates.currentVersion")) {
                    Text(Self.version)
                }

                LabeledContent(String(localized: "settings.updates.lastCheck")) {
                    Text(Self.lastCheck(updates.lastCheck))
                }
            }

            Section {
                Toggle(
                    String(localized: "settings.updates.automatic"),
                    isOn: Binding(get: { automatic }, set: { setAutomatic($0) })
                )

                Button(String(localized: "settings.updates.checkNow")) {
                    updates.checkForUpdates()
                }
            } footer: {
                Text(String(localized: "settings.updates.automatic.explanation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { automatic = updates.automaticallyChecks }
    }

    /// Written through, then read back: what the switch shows is what the
    /// updater holds, not what it was asked for.
    private func setAutomatic(_ isOn: Bool) {
        updates.automaticallyChecks = isOn
        automatic = updates.automaticallyChecks
    }

    private static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    private static func lastCheck(_ date: Date?) -> String {
        guard let date else { return String(localized: "settings.updates.lastCheck.never") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
