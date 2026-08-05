import CoreServices
import Foundation

/// Watches the plugin folder and reports that something changed.
///
/// A protocol so the index is testable without a real directory, real events,
/// or waiting on a debounce.
@MainActor
protocol PluginDirectoryWatching {
    func start(root: URL, onChange: @escaping @MainActor () -> Void)
    func stop()
}

/// Watches a directory tree with FSEvents.
///
/// FSEvents rather than `DispatchSource.makeFileSystemObjectSource`, which
/// `ApplicationIndex` uses: a vnode source on a directory reports changes to the
/// *directory* — files created, deleted, renamed — and stays silent when an
/// existing file's contents are edited in place. Editing a manifest is the
/// common case here, so the two indexes deliberately watch differently.
@MainActor
final class FileSystemEventWatcher: PluginDirectoryWatching {
    /// Long enough that an editor writing a file in chunks produces one reload.
    /// FSEvents has its own latency; this is the second stage.
    /// Nonisolated so it can be the default for `init`, which is evaluated
    /// outside the main actor.
    nonisolated static let defaultDebounce = Duration.milliseconds(300)

    private let debounce: Duration
    private var stream: FSEventStreamRef?
    private var onChange: (@MainActor () -> Void)?
    private var pending: Task<Void, Never>?

    init(debounce: Duration = FileSystemEventWatcher.defaultDebounce) {
        self.debounce = debounce
    }

    func start(root: URL, onChange: @escaping @MainActor () -> Void) {
        stop()
        self.onChange = onChange

        // Passed unretained: `stop()` always runs before this object goes away,
        // and taking a strong reference here would make the stream own the
        // watcher that owns the stream.
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileSystemEventWatcher>
                .fromOpaque(info).takeUnretainedValue()
            // The stream is scheduled on the main queue, so this callback
            // arrives there and the isolation is real rather than assumed.
            MainActor.assumeIsolated { watcher.scheduleChange() }
        }

        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0,
            // FileEvents reports individual files rather than only directories,
            // which is the whole reason for using FSEvents here.
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
            )
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        pending?.cancel()
        pending = nil
        onChange = nil

        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Coalesces a burst of events into one report.
    private func scheduleChange() {
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            onChange?()
        }
    }
}
