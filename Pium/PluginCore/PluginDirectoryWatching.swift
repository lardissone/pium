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
