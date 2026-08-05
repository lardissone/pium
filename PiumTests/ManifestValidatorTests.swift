import Testing
import Foundation
@testable import Pium

@Suite("Manifest validation")
struct ManifestValidatorTests {
    private func manifest(
        id: String = "web.youtube",
        arguments: [String] = [],
        configuration: [PluginConfigurationField] = [],
        timeoutSeconds: Int? = nil,
        confirmBeforeRun: String? = nil
    ) -> PluginManifest {
        PluginManifest(
            schemaVersion: 1,
            id: id,
            name: "YouTube",
            description: nil,
            keywords: [],
            aliases: [],
            icon: nil,
            input: PluginInput(mode: .optional, placeholder: nil),
            command: PluginCommand(
                executable: "open", arguments: arguments, workingDirectory: nil
            ),
            configuration: configuration,
            output: PluginOutput(mode: .silent),
            timeoutSeconds: timeoutSeconds,
            confirmBeforeRun: confirmBeforeRun
        )
    }

    private func field(
        _ key: String,
        type: PluginConfigurationType
    ) -> PluginConfigurationField {
        PluginConfigurationField(
            key: key,
            label: key,
            type: type,
            required: true,
            environmentVariable: "PIUM_\(key.uppercased())"
        )
    }

    @Test func asoundManifestIsAccepted() {
        #expect(ManifestValidator.validate(manifest()) == nil)
    }

    @Test func idsMayUseLowercaseDigitsDotsAndHyphens() {
        #expect(ManifestValidator.validate(manifest(id: "web.youtube-search")) == nil)
        #expect(ManifestValidator.validate(manifest(id: "a")) == nil)
    }

    /// The id is the trust key in 4b and the frecency key today. Spaces, case,
    /// and unicode would make two ids that look the same behave differently.
    @Test func anIdWithSpacesOrCapitalsIsRejected() {
        #expect(ManifestValidator.validate(manifest(id: "Web YT")) == .invalidIdentifier("Web YT"))
        #expect(ManifestValidator.validate(manifest(id: "WebYT")) == .invalidIdentifier("WebYT"))
        #expect(ManifestValidator.validate(manifest(id: "")) == .invalidIdentifier(""))
        #expect(ManifestValidator.validate(manifest(id: ".leading")) == .invalidIdentifier(".leading"))
    }

    @Test func abrokenTemplateInAnArgumentIsRejected() {
        guard case .invalidTemplate = ManifestValidator.validate(
            manifest(arguments: ["https://x.com/?q={{input"])
        ) else {
            Issue.record("An unclosed template must be rejected")
            return
        }
    }

    @Test func everyArgumentIsChecked() {
        guard case .invalidTemplate = ManifestValidator.validate(
            manifest(arguments: ["fine", "{{input|base64}}"])
        ) else {
            Issue.record("The second argument's template must be checked too")
            return
        }
    }

    /// PRD §10.4: a secret reaches a child process only as an environment
    /// variable. An argument array is visible in the process table.
    @Test func asecretInterpolatedIntoAnArgumentIsRejected() {
        let diagnostic = ManifestValidator.validate(
            manifest(
                arguments: ["--token={{token}}"],
                configuration: [field("token", type: .secret)]
            )
        )
        #expect(diagnostic == .secretInArguments(key: "token"))
    }

    /// Whitespace and a filter are the two ways the same interpolation can be
    /// spelled, and neither may smuggle a secret into the process table.
    @Test func asecretIsRejectedHoweverItIsSpelled() {
        for argument in ["--token={{ token }}", "--token={{token|url_encode}}"] {
            #expect(
                ManifestValidator.validate(
                    manifest(arguments: [argument], configuration: [field("token", type: .secret)])
                ) == .secretInArguments(key: "token"),
                "\(argument) must be rejected"
            )
        }
    }

    /// A regular value is allowed there; only secrets are not.
    @Test func aregularConfigurationValueMayAppearInAnArgument() {
        #expect(
            ManifestValidator.validate(
                manifest(
                    arguments: ["--url={{base-url}}"],
                    configuration: [field("base-url", type: .string)]
                )
            ) == nil
        )
    }

    /// A duplicate key collides on the same storage slot: `ForEach(id: \.key)`
    /// gets two rows with the same identity, and whichever field saves last
    /// silently overwrites the other's stored value.
    @Test func aduplicateConfigurationKeyIsRejected() {
        #expect(
            ManifestValidator.validate(
                manifest(configuration: [
                    field("token", type: .secret),
                    field("token", type: .string),
                ])
            ) == .duplicateConfigurationKey("token")
        )
    }

    /// A key becomes part of a `UserDefaults` key and a Keychain account, so it
    /// needs the same grammar `id` does, for the same reason.
    @Test func aninvalidConfigurationKeyIsRejected() {
        #expect(
            ManifestValidator.validate(manifest(configuration: [field("Token Key", type: .string)]))
                == .invalidConfigurationKey("Token Key")
        )
        #expect(
            ManifestValidator.validate(manifest(configuration: [field("", type: .string)]))
                == .invalidConfigurationKey("")
        )
    }

    @Test func atimeoutMustBeWithinBounds() {
        #expect(ManifestValidator.validate(manifest(timeoutSeconds: 0)) == .invalidTimeout(0))
        #expect(ManifestValidator.validate(manifest(timeoutSeconds: -5)) == .invalidTimeout(-5))
        #expect(ManifestValidator.validate(manifest(timeoutSeconds: 3601)) == .invalidTimeout(3601))
        #expect(ManifestValidator.validate(manifest(timeoutSeconds: 1)) == nil)
        #expect(ManifestValidator.validate(manifest(timeoutSeconds: 3600)) == nil)
    }

    /// PIUM-DOC-2 §5: absent or a nonempty message, never an empty one — an
    /// empty confirmation is a dialog that asks nothing.
    @Test func anEmptyConfirmationMessageIsRejected() {
        guard case .wrongType = ManifestValidator.validate(manifest(confirmBeforeRun: "  ")) else {
            Issue.record("An empty confirmation message must be rejected")
            return
        }
        #expect(ManifestValidator.validate(manifest(confirmBeforeRun: "Sure?")) == nil)
    }
}
