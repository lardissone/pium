import SwiftUI

/// Centralised visual constants.
///
/// Every surface reads its geometry, type, and motion from here, so basic
/// customisation can be added later without hunting literals through views.
/// Values are starting points; the PRD marks final dimensions, tokens, and
/// motion curves as tunable during implementation.
enum Tokens {
    enum Spacing {
        static let tight: CGFloat = 6
        static let normal: CGFloat = 12
        static let loose: CGFloat = 20
    }

    enum Radius {
        static let panel: CGFloat = 14
        static let row: CGFloat = 8
        static let badge: CGFloat = 4
        static let menu: CGFloat = 10
    }

    enum Size {
        static let panelWidth: CGFloat = 680
        static let searchFieldHeight: CGFloat = 56
        static let resultRowHeight: CGFloat = 44
        static let footerHeight: CGFloat = 38
        static let actionMenuWidth: CGFloat = 260
        /// Cap for the expanded result list, applied from Phase 2 onward.
        static let maxResultListHeight: CGFloat = 420
    }

    enum TypeScale {
        static let query = Font.system(size: 24, weight: .regular)
        static let resultTitle = Font.system(size: 14, weight: .medium)
        static let resultSubtitle = Font.system(size: 12, weight: .regular)
        static let footerLabel = Font.system(size: 12, weight: .medium)
        static let shortcutBadge = Font.system(size: 11, weight: .medium)
    }

    enum Motion {
        /// Duration for the panel and result list appearing.
        static let appearDuration = Duration.milliseconds(120)

        /// The appearance duration, honouring the system Reduced Motion
        /// setting. Reduced Motion means no animation, not a faster one.
        static func appear(reduceMotion: Bool) -> Duration {
            reduceMotion ? .zero : appearDuration
        }
    }
}
