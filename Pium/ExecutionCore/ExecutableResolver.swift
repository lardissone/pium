import Foundation

/// Turns what a manifest declares into a path, or into the reason there is none.
///
/// Three shapes, as PRD §10.4 describes them: an absolute path, a path relative
/// to the plugin file's own directory, and a bare name looked up along the
/// controlled search path.
struct ExecutableResolver {
    private let searchPaths: [String]
    private let fileManager: FileManager

    init(searchPaths: [String] = ControlledPath.default, fileManager: FileManager = .default) {
        self.searchPaths = searchPaths
        self.fileManager = fileManager
    }

    func resolve(
        _ executable: String,
        relativeTo pluginDirectory: URL
    ) -> Result<URL, ExecutionFailure> {
        if executable.hasPrefix("/") {
            return verify(URL(filePath: executable))
        }
        if executable.contains("/") {
            // `appending(path:)` rather than `URL(filePath:relativeTo:)`: the
            // latter follows RFC 3986 relative resolution, which treats a
            // base URL without a trailing slash as a file and discards its
            // last path component instead of appending into it.
            //
            // Canonicalized before anything is checked, so `../` is resolved
            // once and the path that is verified is the path that runs.
            let url = pluginDirectory.appending(path: executable).standardizedFileURL
            return verify(url)
        }
        for directory in searchPaths {
            let candidate = URL(filePath: directory).appending(path: executable)
            // Not the same question `verify` asks about existence, which is
            // why both are here: a plugin that named a path and did not get it
            // is a failure to report, while a search path that does not hold
            // the command only means the next one might. Collapsing the two
            // makes the first directory searched answer for all of them.
            guard fileManager.fileExists(atPath: candidate.path) else { continue }
            return verify(candidate)
        }
        return .failure(.executableNotFound(name: executable, searched: searchPaths))
    }

    private func verify(_ url: URL) -> Result<URL, ExecutionFailure> {
        guard fileManager.fileExists(atPath: url.path) else {
            return .failure(.executableMissing(path: url.path))
        }
        guard fileManager.isExecutableFile(atPath: url.path) else {
            return .failure(.executableNotExecutable(path: url.path))
        }
        guard !isQuarantined(url) else {
            return .failure(.quarantined(path: url.path))
        }
        return .success(url)
    }

    /// A quarantined file is executable by its permission bits and refused by
    /// the kernel, so the bits alone do not answer the question.
    private func isQuarantined(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
        }
    }
}
