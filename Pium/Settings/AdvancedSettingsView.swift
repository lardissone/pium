import AppKit
import SwiftUI

/// The Advanced settings section: the controlled `PATH`, and debug logging.
struct AdvancedSettingsView: View {
    @State private var expiry = Preferences.shared.debugLoggingExpiry
    @State private var additionalPaths = Preferences.shared.additionalSearchPaths
    @State private var newPath = ""
    @State private var isConfirmingEnable = false
    @State private var isConfirmingDelete = false
    @State private var exportFailed = false

    /// How long a live session has left, floored at zero.
    ///
    /// Not private, so the decision is testable without a window — the same
    /// reason `SearchSettingsView.shouldRefresh` is not.
    static func remaining(until deadline: Date, now: Date) -> TimeInterval {
        max(0, deadline.timeIntervalSince(now))
    }

    /// A directory as it should be stored, or `nil` when it is not one.
    ///
    /// A path pasted from a terminal arrives with a trailing slash or a stray
    /// space as often as not, and the same directory stored twice reads as two
    /// entries that resolve identically.
    static func normalisedPath(_ raw: String) -> String? {
        let expanded = (raw.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
            .expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        let tidied = expanded.count > 1 && expanded.hasSuffix("/")
            ? String(expanded.dropLast())
            : expanded
        return tidied.isEmpty ? nil : tidied
    }

    var body: some View {
        Form {
            Section {
                ForEach(additionalPaths, id: \.self) { path in
                    LabeledContent(path) {
                        HStack(spacing: Tokens.Spacing.tight) {
                            // A directory that is not there is kept rather
                            // than refused: a volume can mount later.
                            if !FileManager.default.fileExists(atPath: path) {
                                Text(String(localized: "settings.advanced.pathMissing"))
                                    .foregroundStyle(.secondary)
                            }
                            Button(String(localized: "settings.advanced.pathRemove")) {
                                remove(path)
                            }
                            // Every row's button says "Remove" and they are
                            // told apart by the path beside them, which a
                            // screen reader reads separately or not at all.
                            .accessibilityLabel(
                                String(localized: "settings.advanced.pathRemoveLabel \(path)")
                            )
                        }
                    }
                }
                HStack {
                    TextField(
                        String(localized: "settings.advanced.pathPlaceholder"), text: $newPath
                    )
                    Button(String(localized: "settings.advanced.pathAdd"), action: add)
                        .disabled(Self.normalisedPath(newPath) == nil)
                }
                LabeledContent(String(localized: "settings.advanced.effectivePath")) {
                    Text(ControlledPath.effective(adding: additionalPaths).joined(separator: ":"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            } header: {
                Text(String(localized: "settings.advanced.path"))
            } footer: {
                Text(String(localized: "settings.advanced.pathExplanation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    String(localized: "settings.advanced.debugLogging"),
                    isOn: Binding(
                        get: { expiry != nil },
                        set: { isOn in isOn ? (isConfirmingEnable = true) : disable() }
                    )
                )
                .confirmationDialog(
                    String(localized: "settings.advanced.debugWarningTitle"),
                    isPresented: $isConfirmingEnable
                ) {
                    Button(String(localized: "settings.advanced.debugEnable")) { enable() }
                    Button(String(localized: "settings.advanced.debugCancel"), role: .cancel) {}
                } message: {
                    Text(String(localized: "settings.advanced.debugWarning"))
                }

                if let expiry {
                    LabeledContent(String(localized: "settings.advanced.debugRemaining")) {
                        HStack(spacing: Tokens.Spacing.tight) {
                            Text(
                                Duration.seconds(Self.remaining(until: expiry, now: Date()))
                                    .formatted(.units(allowed: [.hours, .minutes]))
                            )
                            Button(String(localized: "settings.advanced.debugRenew")) { enable() }
                        }
                    }
                }

                Button(String(localized: "settings.advanced.exportLogs"), action: export)
                Button(String(localized: "settings.advanced.deleteLogs"), role: .destructive) {
                    isConfirmingDelete = true
                }
                .confirmationDialog(
                    String(localized: "settings.advanced.deleteLogs"),
                    isPresented: $isConfirmingDelete
                ) {
                    Button(String(localized: "settings.advanced.deleteLogs"), role: .destructive) {
                        Task { await DebugLog.store.deleteAll() }
                    }
                }
                if exportFailed {
                    Text(String(localized: "settings.advanced.exportFailed"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "settings.advanced.diagnostics"))
            } footer: {
                Text(String(localized: "settings.advanced.debugExplanation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { expiry = Preferences.shared.debugLoggingExpiry }
    }

    private func enable() {
        let deadline = DebugLogging.deadline(from: Date())
        Preferences.shared.debugLoggingExpiry = deadline
        expiry = deadline
    }

    private func disable() {
        Preferences.shared.debugLoggingExpiry = nil
        expiry = nil
    }

    private func add() {
        guard let path = Self.normalisedPath(newPath), !additionalPaths.contains(path) else {
            return
        }
        additionalPaths.append(path)
        Preferences.shared.additionalSearchPaths = additionalPaths
        newPath = ""
    }

    private func remove(_ path: String) {
        additionalPaths.removeAll { $0 == path }
        Preferences.shared.additionalSearchPaths = additionalPaths
    }

    /// The privacy warning appears again here, as PRD §14 requires: exporting
    /// is the moment the file stops being local.
    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "pium-debug.log"
        panel.message = String(localized: "settings.advanced.exportWarning")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await DebugLog.store.export().write(to: url)
                exportFailed = false
            } catch {
                exportFailed = true
            }
        }
    }
}
