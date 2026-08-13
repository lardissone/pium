import SwiftUI

/// PRD §12's Updates section: status, the automatic-check switch, and a
/// button for the person who does not want to wait six hours.
struct UpdatesSettingsView: View {
    let updates: any UpdateAvailability

    /// Held rather than read straight from the updater, for two reasons that
    /// apply to both: flipping the switch has to redraw, and nothing here is
    /// observable — both values live behind stored references the `@Observable`
    /// macro does not see, one of them in shared user defaults that another
    /// process can write. The Settings window is built once and reused for the
    /// life of the app, so whatever is captured stays on screen until
    /// something puts it back in touch with the updater; `onAppear` is that.
    @State private var automatic: Bool
    @State private var lastCheck: Date?

    init(updates: any UpdateAvailability) {
        self.updates = updates
        _automatic = State(initialValue: updates.automaticallyChecks)
        _lastCheck = State(initialValue: updates.lastCheck)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "settings.updates.currentVersion")) {
                    Text(Self.version)
                }

                LabeledContent(String(localized: "settings.updates.lastCheck")) {
                    Text(Self.lastCheck(lastCheck))
                }
            }

            Section {
                Toggle(
                    String(localized: "settings.updates.automatic"),
                    // The setter is a closure rather than the method itself:
                    // passing `setAutomatic` directly crashes the compiler in
                    // IRGen, on the thunk for the isolated method value.
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
        .onAppear {
            automatic = updates.automaticallyChecks
            lastCheck = updates.lastCheck
        }
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

    /// Not private, so the decision is testable without a window — the same
    /// reason `AdvancedSettingsView.remaining` is not.
    static func lastCheck(_ date: Date?) -> String {
        guard let date else { return String(localized: "settings.updates.lastCheck.never") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
