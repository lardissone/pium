import Foundation
import OSLog

/// Owns the runs.
///
/// Records live in a collection keyed by `UUID` even though MVP policy admits
/// one at a time (PIUM-DOC-2 §3.2), so allowing concurrency later replaces a
/// policy rather than a model.
///
/// Everything that can fail does so before a process exists: resolving the
/// executable, resolving the arguments, and reading the configuration. What
/// remains after that is a command that ran, and how it ended.
@MainActor
@Observable
final class ExecutionManager {
    private let logger = Logger(subsystem: Signposts.subsystem, category: "Execution")
    private let resolver: ExecutableResolver
    private let environment: ChildEnvironment
    private let configuration: any PluginConfigurationStoring
    private let runner = ProcessRunner()

    /// How many runs are remembered.
    ///
    /// The interface asks about the run in flight and the one that just ended;
    /// nothing asks about a run from last Tuesday, and each record carries up
    /// to two 64 KB captures. A menubar app is open for weeks, so a collection
    /// with no reason to shrink is a collection that only grows.
    ///
    /// Bounded rather than emptying the captures of records that are no longer
    /// current: a record whose output was thrown away reads exactly like a
    /// command that printed nothing, and every record kept here should be able
    /// to say what its run did.
    static let historyLimit = 20

    private(set) var records: [UUID: ExecutionRecord] = [:]
    private var cancellations: [UUID: ProcessRunner.Cancellation] = [:]
    /// The order runs started in, which the dictionary does not keep and
    /// eviction needs.
    private var startOrder: [UUID] = []

    /// Told once a run reaches a final state. 5b's `AppDelegate` is the only
    /// caller; left `nil` here so 5a's own tests, which never set it, run
    /// unaffected.
    private let onFinished: ((ExecutionRecord) -> Void)?

    init(
        configuration: any PluginConfigurationStoring,
        secrets: any PluginSecretStoring,
        searchPaths: [String] = ControlledPath.default,
        onFinished: ((ExecutionRecord) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.resolver = ExecutableResolver(searchPaths: searchPaths)
        self.environment = ChildEnvironment(
            configuration: configuration, secrets: secrets, searchPaths: searchPaths
        )
        self.onFinished = onFinished
    }

    /// The plugin currently holding the single slot, if any.
    var activeRecord: ExecutionRecord? {
        records.values.first(where: \.isRunning)
    }

    @discardableResult
    func run(_ record: PluginRecord, input: String) -> Result<UUID, ExecutionFailure> {
        guard let manifest = record.manifest else {
            return .failure(.invalidManifest(path: record.fileURL.path))
        }
        if let active = activeRecord {
            return .failure(.alreadyRunning(plugin: active.pluginName))
        }

        let directory = record.fileURL.deletingLastPathComponent()
        let executable: URL
        switch resolver.resolve(manifest.command.executable, relativeTo: directory) {
        case .success(let url): executable = url
        case .failure(let failure): return .failure(failure)
        }

        let childEnvironment: [String: String]
        switch environment.build(for: manifest) {
        case .success(let built): childEnvironment = built
        case .failure(let failure): return .failure(failure)
        }

        let arguments = resolvedArguments(of: manifest, input: input)
        let request = ExecutionRequest(
            executable: executable,
            arguments: arguments,
            workingDirectory: resolvedWorkingDirectory(of: manifest, relativeTo: directory),
            environment: childEnvironment,
            timeoutSeconds: manifest.timeoutSeconds
        )

        let id = UUID()
        records[id] = ExecutionRecord(
            id: id,
            pluginID: manifest.id,
            pluginName: manifest.name,
            outputMode: manifest.output.mode,
            startedAt: Date(),
            state: .running,
            standardOutput: "",
            standardError: "",
            wasTruncated: false
        )
        startOrder.append(id)
        evictOldestRuns()
        let cancellation = ProcessRunner.Cancellation()
        cancellations[id] = cancellation

        logger.notice("Running \(manifest.id, privacy: .public)")
        Task { [runner] in
            let outcome = await runner.run(request, cancellation: cancellation)
            finish(id, with: outcome)
        }
        return .success(id)
    }

    func cancel(_ id: UUID) {
        cancellations[id]?.cancel()
    }

    /// Drops the oldest runs past `historyLimit`, skipping any that is still
    /// running: that record is what `activeRecord` answers with, and its
    /// cancellation is the only handle that can stop it.
    private func evictOldestRuns() {
        while startOrder.count > Self.historyLimit {
            guard let oldest = startOrder.firstIndex(where: { records[$0]?.isRunning != true })
            else { return }
            records[startOrder.remove(at: oldest)] = nil
        }
    }

    /// No declaration runs in the plugin's own folder. Otherwise, mirrors
    /// `ExecutableResolver`'s own branch on a leading `/`: an absolute
    /// declaration names a directory outright, and only a relative one
    /// resolves against the plugin's folder.
    private func resolvedWorkingDirectory(of manifest: PluginManifest, relativeTo directory: URL) -> URL {
        guard let declared = manifest.command.workingDirectory else { return directory }
        if declared.hasPrefix("/") {
            return URL(filePath: declared)
        }
        // `appending(path:)`, for the same reason `ExecutableResolver` uses it:
        // `URL(filePath:relativeTo:)` drops the base's last component when the
        // base carries no directory hint.
        return directory.appending(path: declared).standardizedFileURL
    }

    /// Regular configuration may be interpolated into arguments; secrets may
    /// not, which `ManifestValidator` already enforces on the file.
    private func resolvedArguments(of manifest: PluginManifest, input: String) -> [String] {
        var values: [String: String] = [:]
        for field in manifest.configuration where field.type == .string {
            values[field.key] = configuration.value(pluginID: manifest.id, key: field.key)
        }
        let keys = Set(manifest.configuration.map(\.key))

        return manifest.command.arguments.map { argument in
            guard case .success(let tokens) = PluginTemplate.parseAllowingConfiguration(
                argument, configurationKeys: keys
            ) else {
                // Unreachable: the file could not have loaded with a template
                // that does not parse. Passing it through unchanged is the
                // honest fallback — it is what the author wrote.
                return argument
            }
            return PluginTemplate.resolve(tokens, input: input, configuration: values)
        }
    }

    private func finish(_ id: UUID, with outcome: ExecutionOutcome) {
        guard var record = records[id] else { return }
        record.state = .ended(outcome.ending)
        record.standardOutput = outcome.standardOutput
        record.standardError = outcome.standardError
        record.wasTruncated = outcome.wasTruncated
        records[id] = record
        cancellations[id] = nil

        // The log is not the only place a failure is visible: `onFinished`
        // hands the same record to whatever puts it in front of the user.
        // Both still happen — the log outlives any HUD, which times out and
        // closes.
        switch outcome.ending {
        case .exited(let code) where code != 0:
            // The plugin id is public because it is what makes the line
            // useful. The child's stderr is not, and must not become so: a
            // command that traces itself, or that reports the URL a request
            // failed on, prints the token Pium handed it — and the unified log
            // keeps what it is given. Redacted, the line still says which
            // plugin failed and with what code.
            logger.error(
                "\(record.pluginID, privacy: .public) exited \(code): \(record.standardError)"
            )
        case .timedOut:
            logger.error("\(record.pluginID, privacy: .public) timed out")
        case .signalled(let signal):
            logger.error("\(record.pluginID, privacy: .public) was killed by signal \(signal)")
        case .failed(let failure):
            logger.error(
                "\(record.pluginID, privacy: .public) did not run: \(failure.message, privacy: .public)"
            )
        default:
            logger.notice("\(record.pluginID, privacy: .public) finished")
        }

        onFinished?(record)
    }
}
