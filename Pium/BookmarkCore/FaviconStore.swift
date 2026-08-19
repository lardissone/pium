import AppKit
import OSLog

/// The icon a site says it has.
///
/// Pium's only network traffic besides the update check, and deliberately
/// small: one request per host, the answer kept on disk, and nothing asked for
/// at all unless a bookmark points somewhere over http.
///
/// Observable because a row that asked for an icon and got nothing has to
/// redraw itself when one arrives.
@MainActor
@Observable
final class FaviconStore {
    /// What a fetch needs from the network. Injected so a test can answer for
    /// a host without one.
    typealias Fetch = @Sendable (URL) async -> Data?

    /// An icon is small. Anything that is not is somebody else's problem being
    /// downloaded into Pium's cache directory.
    static let maximumBytes = 256 * 1024

    /// How long a host that did not answer is left alone. Without it, a Mac
    /// with no network fires an attempt per visible bookmark per keystroke.
    static let cooldown: TimeInterval = 5 * 60

    private let logger = Logger(subsystem: Signposts.subsystem, category: "Favicon")
    private let directory: URL
    private let fetch: Fetch
    private let now: @Sendable () -> Date

    /// Decoded icons, keyed by host. The observed state: a row reads this.
    private var icons: [String: NSImage] = [:]
    /// Hosts whose fetch is running, so two rows for one site ask once.
    private var inFlight: Set<String> = []
    /// When a host last failed. In memory only, on purpose — the next launch
    /// is a fresh chance, and a machine that was offline should not stay
    /// punished for it.
    private var failures: [String: Date] = [:]

    /// `~/Library/Caches/Pium/Favicons`. A cache, not application support:
    /// everything here can be fetched again, and macOS may remove it.
    static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "Pium/Favicons")
    }

    init(
        directory: URL = FaviconStore.defaultDirectory,
        fetch: @escaping Fetch = FaviconStore.download,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directory = directory
        self.fetch = fetch
        self.now = now
    }

    /// The icon for a host, and a fetch started when there is not one yet.
    ///
    /// Returning `nil` rather than waiting is what keeps this usable from a
    /// row: the fallback shows now, and the icon replaces it when it lands.
    func icon(forHost host: String) -> NSImage? {
        if let icon = icons[host] { return icon }
        if let stored = loadFromDisk(host) {
            icons[host] = stored
            return stored
        }
        Task { await fetchIfNeeded(host: host) }
        return nil
    }

    /// Warms a host, for the moment a bookmark is saved — so the icon is
    /// normally there before anybody searches for it.
    func prefetch(host: String) {
        Task { await fetchIfNeeded(host: host) }
    }

    func fetchIfNeeded(host: String) async {
        guard icons[host] == nil, !inFlight.contains(host) else { return }
        if let failed = failures[host], now().timeIntervalSince(failed) < Self.cooldown { return }
        if let stored = loadFromDisk(host) {
            icons[host] = stored
            return
        }

        inFlight.insert(host)
        defer { inFlight.remove(host) }

        guard let data = await fetchIcon(host: host), let image = NSImage(data: data) else {
            failures[host] = now()
            return
        }

        failures[host] = nil
        icons[host] = image
        writeToDisk(data, host: host)
    }

    /// `/favicon.ico` first because it costs one request and is usually right,
    /// then the page itself, which is where a site that moved its icon says so.
    private func fetchIcon(host: String) async -> Data? {
        guard var components = URLComponents(string: "https://\(host)") else { return nil }
        components.path = "/favicon.ico"
        if let url = components.url, let data = await bounded(url), NSImage(data: data) != nil {
            return data
        }

        components.path = "/"
        guard
            let pageURL = components.url,
            let page = await bounded(pageURL),
            let html = String(data: page.prefix(Self.htmlBytesRead), encoding: .utf8),
            let href = Self.iconHref(inHTML: html),
            let iconURL = URL(string: href, relativeTo: pageURL)
        else {
            return nil
        }
        return await bounded(iconURL)
    }

    /// Only the first stretch of a page is read: the icon is declared in the
    /// head, and a page that buries it past this is a page Pium falls back for.
    private static let htmlBytesRead = 64 * 1024

    private func bounded(_ url: URL) async -> Data? {
        guard let data = await fetch(url) else { return nil }
        guard data.count <= Self.maximumBytes else {
            logger.debug("Ignoring \(data.count) bytes from \(url.host() ?? "?", privacy: .public)")
            return nil
        }
        return data
    }

    /// The `href` of the first icon a page declares.
    ///
    /// A scan rather than an HTML parser: this reads one attribute out of one
    /// kind of tag, and every parser available would be a dependency taken on
    /// for that. Anything it does not understand falls back, which is the same
    /// outcome as a page with no icon at all.
    nonisolated static func iconHref(inHTML html: String) -> String? {
        for tag in html.components(separatedBy: "<link").dropFirst() {
            let head = String(tag.prefix(400)).lowercased()
            guard let relRange = head.range(of: "rel=") else { continue }
            let rel = attributeValue(in: head, from: relRange.upperBound) ?? ""
            guard rel.split(separator: " ").contains(where: {
                $0 == "icon" || $0 == "shortcut" || $0 == "apple-touch-icon"
            }) else { continue }

            guard let hrefRange = tag.range(of: "href=", options: .caseInsensitive) else { continue }
            if let href = attributeValue(in: tag, from: hrefRange.upperBound), !href.isEmpty {
                return href
            }
        }
        return nil
    }

    /// The quoted value that starts at `index`, in either kind of quote.
    nonisolated private static func attributeValue(in text: String, from index: String.Index) -> String? {
        guard index < text.endIndex else { return nil }
        let quote = text[index]
        guard quote == "\"" || quote == "'" else { return nil }
        let after = text.index(after: index)
        guard let end = text[after...].firstIndex(of: quote) else { return nil }
        return String(text[after..<end])
    }

    private func fileURL(_ host: String) -> URL {
        directory.appending(path: host)
    }

    /// Stored as fetched rather than re-encoded: an `.ico` carries several
    /// sizes and `NSImage` picks between them, which is a choice worth keeping.
    private func writeToDisk(_ data: Data, host: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(host))
        } catch {
            // A cache that cannot be written is a cache, not a failure.
            logger.debug("Could not cache an icon: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadFromDisk(_ host: String) -> NSImage? {
        guard let data = try? Data(contentsOf: fileURL(host)) else { return nil }
        return NSImage(data: data)
    }

    /// The real fetch. A short timeout because nothing waits on this — the row
    /// has already drawn its fallback — and a slow site should not hold a task
    /// open behind it.
    private static let download: Fetch = { url in
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
        else {
            return nil
        }
        return data
    }
}
