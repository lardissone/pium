import AppKit

/// What a bookmark's row shows.
///
/// A cascade rather than one lookup, because there are three different reasons
/// a bookmark might have a good icon and only the last of them always works.
/// Written as a function of its two lookups so each step can be tested without
/// caring what is installed on the machine running the test.
enum BookmarkIcon {
    /// Shown when nothing else resolves. Says "a link" and "a place" rather
    /// than leaving the row blank.
    static func fallbackSymbol(for destination: BookmarkDestination) -> String {
        switch destination {
        case .link: "link"
        case .path: "folder"
        }
    }

    static func source(
        for bookmark: Bookmark,
        applicationForBundleIdentifier: (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        applicationToOpen: (URL) -> URL? = {
            NSWorkspace.shared.urlForApplication(toOpen: $0)
        }
    ) -> IconSource {
        let cascade = applicationCascade(
            for: bookmark,
            applicationForBundleIdentifier: applicationForBundleIdentifier,
            applicationToOpen: applicationToOpen
        )
        // A site's own icon says more about a bookmark than the browser that
        // would open it — including when the user named that browser, which is
        // a choice about where it opens rather than about what it is. Only the
        // web has these, so everything else is the cascade outright.
        guard let host = webHost(of: bookmark.destination) else { return cascade }
        return .favicon(host: host, fallback: cascade)
    }

    /// The host to ask, for an `https` or `http` link and nothing else.
    private static func webHost(of destination: BookmarkDestination) -> String? {
        guard
            case .link = destination,
            let url = destination.url(input: ""),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            let host = url.host(), !host.isEmpty
        else {
            return nil
        }
        return host
    }

    private static func applicationCascade(
        for bookmark: Bookmark,
        applicationForBundleIdentifier: (String) -> URL?,
        applicationToOpen: (URL) -> URL?
    ) -> IconSource {
        // The application the user named for this bookmark, which is the most
        // specific thing there is to show. An application that is no longer
        // installed falls through rather than showing nothing.
        if let identifier = bookmark.openWith,
           let application = applicationForBundleIdentifier(identifier) {
            return .fileIcon(application)
        }

        // Resolved with no argument, because an icon is wanted before anybody
        // has typed one. A search URL without its query still names the site
        // that handles it.
        guard let url = bookmark.destination.url(input: "") else {
            return .systemSymbol(fallbackSymbol(for: bookmark.destination))
        }

        // A path shows the thing itself: a folder should look like a folder,
        // not like the application that would open it.
        if case .path = bookmark.destination, FileManager.default.fileExists(atPath: url.path) {
            return .fileIcon(url)
        }

        if let application = applicationToOpen(url) {
            return .fileIcon(application)
        }
        return .systemSymbol(fallbackSymbol(for: bookmark.destination))
    }
}
