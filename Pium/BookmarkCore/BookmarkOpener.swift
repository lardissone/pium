import AppKit

/// Opens a bookmark.
///
/// Deliberately nothing to do with `ExecutionManager`: opening a link starts no
/// process, takes no time worth measuring, and must not queue behind a plugin
/// holding the single run slot.
@MainActor
final class BookmarkOpener {
    private let applicationForBundleIdentifier: @Sendable @MainActor (String) -> URL?
    private let open: @Sendable @MainActor (URL) -> Void
    private let openWith: @Sendable @MainActor (URL, URL) -> Void
    private let report: @Sendable @MainActor (HUDPresentation) -> Void

    init(
        applicationForBundleIdentifier: @escaping @Sendable @MainActor (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        open: @escaping @Sendable @MainActor (URL) -> Void = {
            NSWorkspace.shared.open($0)
        },
        openWith: @escaping @Sendable @MainActor (URL, URL) -> Void = { url, application in
            NSWorkspace.shared.open(
                [url], withApplicationAt: application, configuration: .init()
            )
        },
        report: @escaping @Sendable @MainActor (HUDPresentation) -> Void
    ) {
        self.applicationForBundleIdentifier = applicationForBundleIdentifier
        self.open = open
        self.openWith = openWith
        self.report = report
    }

    func open(_ bookmark: Bookmark, input: String) {
        // Percent-encoding saves most of what a person can type into an
        // argument, and not all of it. Opening nothing while saying nothing is
        // the one outcome worth ruling out.
        guard let url = bookmark.destination.url(input: input) else {
            report(
                HUDPresentation(
                    kind: .failure,
                    title: bookmark.name,
                    body: String(localized: "bookmark.open.unopenable \(bookmark.destination.template)"),
                    duration: HUDPresentation.failureDuration
                )
            )
            return
        }

        guard let identifier = bookmark.openWith else {
            open(url)
            return
        }

        guard let application = applicationForBundleIdentifier(identifier) else {
            // It still opens. The user asked for this to open, and refusing
            // because their second choice of application is gone helps nobody
            // — but coming up somewhere unexpected without explanation would
            // read as a bug, so it is explained.
            open(url)
            report(
                HUDPresentation(
                    kind: .failure,
                    title: bookmark.name,
                    body: String(localized: "bookmark.open.applicationMissing \(identifier)"),
                    duration: HUDPresentation.failureDuration
                )
            )
            return
        }

        openWith(url, application)
    }
}
