import SwiftUI

/// One row of the result list.
struct ResultRowView: View {
    /// Lets the UI tests find rows specifically, rather than any element that
    /// happens to carry the selected trait.
    static let accessibilityIdentifier = "result.row"

    let result: SearchResult
    let isSelected: Bool

    /// Absent wherever no bookmarks are on screen — the previews and the
    /// launcher's own tests among them — in which case a favicon simply never
    /// resolves and its fallback is what shows.
    @Environment(FaviconStore.self) private var favicons: FaviconStore?

    var body: some View {
        HStack(spacing: Tokens.Spacing.normal) {
            icon
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(Tokens.TypeScale.resultTitle)
                    .lineLimit(1)
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(Tokens.TypeScale.resultSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Spacing.loose)
        .padding(.vertical, Tokens.Spacing.tight)
        .frame(height: Tokens.Size.resultRowHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Tokens.Radius.row)
                    .fill(.selection)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        // Spelled out rather than combined from the children: combining reads
        // the title and subtitle and drops the kind along with the icon, which
        // is hidden as decoration — and the kind is the only thing separating
        // an application called Notes from a file called Notes.
        .accessibilityLabel(result.accessibilityDescription)
        .accessibilityIdentifier(Self.accessibilityIdentifier)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// What the row actually draws, once a favicon has been resolved into
    /// either an image or the thing it falls back to.
    ///
    /// A value rather than a view, because the alternative is a `@ViewBuilder`
    /// that calls itself — and a function returning `some View` cannot be
    /// defined in terms of itself.
    private enum Drawable {
        case image(NSImage)
        case file(URL)
        case symbol(String)
        case warning(String)
    }

    private var drawable: Drawable {
        var source = result.iconSource
        // Asking is what starts the fetch. A favicon that has arrived is what
        // to draw; one that has not is its fallback — which is never itself a
        // favicon, and the loop is what makes that true rather than assumed.
        while case .favicon(let host, let fallback) = source {
            if let image = favicons?.icon(forHost: host) { return .image(image) }
            source = fallback
        }
        switch source {
        case .fileIcon(let url): return .file(url)
        case .systemSymbol(let name): return .symbol(name)
        case .warningSymbol(let name): return .warning(name)
        case .favicon: return .symbol("link")
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch drawable {
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        case .file(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
        case .symbol(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        case .warning(let name):
            // Coloured because this row is the only place a broken plugin
            // reports itself until Preferences grows a Plugins section.
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.orange)
        }
    }
}
