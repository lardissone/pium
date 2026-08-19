import AppKit
import SwiftUI

/// The Bookmarks section of Settings: the only place a bookmark is made.
struct BookmarksSettingsView: View {
    /// Names a test can rely on. A label is what a person reads and what a
    /// translator changes; an identifier is neither, which is the whole point
    /// of having both.
    static let addButtonIdentifier = "bookmark.add"
    static let removeButtonIdentifier = "bookmark.remove"
    static let nameFieldIdentifier = "bookmark.name"
    static let destinationFieldIdentifier = "bookmark.destination"
    static let saveButtonIdentifier = "bookmark.save"
    static let confirmDeleteIdentifier = "bookmark.delete.confirm"

    let store: BookmarkStore
    let applications: ApplicationIndex
    let favicons: FaviconStore

    /// Which bookmark the form is showing, if any. A new one has no id yet —
    /// it is not in the store until it is saved, because a half-typed
    /// destination is not a destination.
    private enum Editing: Equatable {
        case nothing
        case existing(UUID)
        case new
    }

    @State private var editing: Editing = .nothing
    @State private var draft = BookmarkDraft()
    @State private var problem: BookmarkDraftProblem?
    @State private var pendingDeletion: Bookmark?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                list
                Divider()
                footer
                // Under the list rather than in the detail pane: this is true
                // of the section, not of whichever bookmark is selected, and
                // somebody has a right to read it without selecting anything.
                Text(String(localized: "bookmarks.favicon.disclosure"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Tokens.Spacing.tight)
                    .padding(.bottom, Tokens.Spacing.tight)
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)

            detail
                .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .confirmationDialog(
            pendingDeletion.map { String(localized: "bookmarks.delete.title \($0.name)") } ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )
        ) {
            Button(String(localized: "bookmarks.delete.confirm"), role: .destructive) {
                if let doomed = pendingDeletion {
                    store.remove(doomed.id)
                    editing = .nothing
                }
                pendingDeletion = nil
            }
            .accessibilityIdentifier(Self.confirmDeleteIdentifier)
        } message: {
            // A bookmark is the user's own data and there is no undo, so the
            // one destructive control in this section asks first.
            Text(String(localized: "bookmarks.delete.message"))
        }
    }

    private var list: some View {
        List(store.bookmarks, selection: selection) { bookmark in
            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.name)
                Text(bookmark.destination.template)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .tag(bookmark.id)
        }
    }

    /// Selecting a row opens it into the form. Writing through a binding rather
    /// than `onChange` so the draft is replaced in the same turn as the
    /// selection — otherwise a keystroke can land in the previous bookmark's
    /// draft on its way out.
    private var selection: Binding<UUID?> {
        Binding(
            get: { if case .existing(let id) = editing { id } else { nil } },
            set: { id in
                guard let id, let bookmark = store.bookmarks.first(where: { $0.id == id }) else {
                    editing = .nothing
                    return
                }
                editing = .existing(id)
                draft = BookmarkDraft(bookmark)
                problem = nil
            }
        )
    }

    private var footer: some View {
        HStack(spacing: Tokens.Spacing.tight) {
            Button {
                editing = .new
                draft = BookmarkDraft()
                problem = nil
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(String(localized: "bookmarks.add"))
            .accessibilityIdentifier(Self.addButtonIdentifier)

            Button {
                if case .existing(let id) = editing {
                    pendingDeletion = store.bookmarks.first { $0.id == id }
                }
            } label: {
                Image(systemName: "minus")
            }
            .accessibilityLabel(String(localized: "bookmarks.remove"))
            .accessibilityIdentifier(Self.removeButtonIdentifier)
            .disabled(selection.wrappedValue == nil)

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(Tokens.Spacing.tight)
    }

    @ViewBuilder
    private var detail: some View {
        switch editing {
        case .nothing:
            emptyDetail
        case .new, .existing:
            form
        }
    }

    private var emptyDetail: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.tight) {
            if store.bookmarks.isEmpty {
                Text(String(localized: "bookmarks.empty.title"))
                    .font(.headline)
                Text(String(localized: "bookmarks.empty.body"))
                    .foregroundStyle(.secondary)
            }
            Text(String(localized: "bookmarks.whatIsAbookmark"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Tokens.Spacing.normal)
    }

    private var form: some View {
        Form {
            TextField(String(localized: "bookmarks.field.name"), text: $draft.name)
                .accessibilityIdentifier(Self.nameFieldIdentifier)

            VStack(alignment: .leading, spacing: 2) {
                TextField(String(localized: "bookmarks.field.destination"), text: $draft.destination)
                    .accessibilityIdentifier(Self.destinationFieldIdentifier)
                // Said while it is being typed rather than on save: the point
                // is to tell somebody their text is neither a link nor a path
                // while they can still see the field they typed it into.
                if let reading = readingDescription {
                    Text(reading)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                TextField(String(localized: "bookmarks.field.keywords"), text: $draft.keywords)
                Text(String(localized: "bookmarks.field.keywords.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker(String(localized: "bookmarks.field.openWith"), selection: $draft.openWith) {
                Text(String(localized: "bookmarks.openWith.systemDefault")).tag(String?.none)
                ForEach(openableApplications, id: \.id) { application in
                    Text(application.name).tag(String?.some(application.bundleIdentifier ?? ""))
                }
            }

            if let problem {
                Text(problem.message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(String(localized: "bookmarks.save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(Self.saveButtonIdentifier)
            }
        }
        .formStyle(.grouped)
    }

    /// Only applications that can be named: one without a bundle identifier
    /// cannot be stored or resolved later.
    private var openableApplications: [InstalledApplication] {
        applications.applications
            .filter { $0.bundleIdentifier?.isEmpty == false }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var readingDescription: String? {
        switch draft.reading {
        case .empty:
            nil
        case .unreadable:
            // Silent while it is being typed. Every half-written destination
            // passes through unreadable, and shouting at somebody mid-word is
            // worse than saying nothing until they press Save.
            nil
        case .link(let takesArgument):
            [
                String(localized: "bookmarks.reading.link"),
                takesArgument ? String(localized: "bookmarks.reading.takesArgument") : nil,
            ].compactMap(\.self).joined(separator: " ")
        case .path(let takesArgument):
            [
                String(localized: "bookmarks.reading.path"),
                takesArgument ? String(localized: "bookmarks.reading.takesArgument") : nil,
            ].compactMap(\.self).joined(separator: " ")
        }
    }

    private func save() {
        let id: UUID
        switch editing {
        case .existing(let existing): id = existing
        case .new, .nothing: id = UUID()
        }

        switch draft.bookmark(id: id) {
        case .failure(let refused):
            problem = refused
        case .success(let bookmark):
            problem = nil
            if case .existing = editing {
                store.update(bookmark)
            } else {
                store.add(bookmark)
            }
            // Asked for now rather than the first time it is searched for, so
            // the icon is normally already there when the row appears.
            if case .favicon(let host, _) = BookmarkIcon.source(for: bookmark) {
                favicons.prefetch(host: host)
            }
            editing = .existing(bookmark.id)
        }
    }
}
