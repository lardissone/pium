import SwiftUI

/// The Appearance settings section: where HUDs appear.
struct AppearanceSettingsView: View {
    /// Shows a real HUD at the chosen anchor. Handed in rather than reached
    /// for: the controller that owns the panels outlives this window, and a
    /// preview is the one thing here that has to touch it.
    let onPreview: () -> Void

    @State private var anchor = Preferences.shared.hudAnchor

    /// The six anchors in the arrangement they occupy on a screen, so the
    /// control's geometry carries the meaning a list of names cannot.
    static let rows: [[HUDAnchor]] = [
        [.topLeft, .topCenter, .topRight],
        [.bottomLeft, .bottomCenter, .bottomRight],
    ]

    private static let cell = CGSize(width: 56, height: 34)

    var body: some View {
        Form {
            Section {
                VStack(spacing: Tokens.Spacing.tight) {
                    ForEach(Self.rows, id: \.self) { row in
                        HStack(spacing: Tokens.Spacing.tight) {
                            ForEach(row, id: \.self) { candidate in
                                Button {
                                    select(candidate)
                                } label: {
                                    RoundedRectangle(cornerRadius: Tokens.Radius.row)
                                        .fill(
                                            candidate == anchor
                                                ? AnyShapeStyle(Color.accentColor)
                                                : AnyShapeStyle(.quaternary)
                                        )
                                        .frame(width: Self.cell.width, height: Self.cell.height)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(candidate.title)
                                .accessibilityAddTraits(candidate == anchor ? [.isSelected] : [])
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Button(String(localized: "settings.appearance.preview"), action: onPreview)
                    .frame(maxWidth: .infinity, alignment: .center)
            } header: {
                Text(String(localized: "settings.appearance.hudPosition"))
            } footer: {
                Text(String(localized: "settings.appearance.hudPositionExplanation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { anchor = Preferences.shared.hudAnchor }
    }

    private func select(_ candidate: HUDAnchor) {
        anchor = candidate
        Preferences.shared.hudAnchor = candidate
    }
}

extension HUDAnchor {
    /// Named for VoiceOver, which cannot read a rectangle's position.
    var title: String {
        switch self {
        case .topLeft: String(localized: "settings.appearance.anchor.topLeft")
        case .topCenter: String(localized: "settings.appearance.anchor.topCenter")
        case .topRight: String(localized: "settings.appearance.anchor.topRight")
        case .bottomLeft: String(localized: "settings.appearance.anchor.bottomLeft")
        case .bottomCenter: String(localized: "settings.appearance.anchor.bottomCenter")
        case .bottomRight: String(localized: "settings.appearance.anchor.bottomRight")
        }
    }
}
