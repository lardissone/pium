import Testing
import SwiftUI
@testable import Pium

@Suite("Design tokens")
struct TokensTests {
    /// Reduced Motion is a system accessibility setting Pium must honour, and
    /// honouring it means no animation at all, not a shorter one.
    @Test func reducedMotionCollapsesAppearanceToZero() {
        #expect(Tokens.Motion.appear(reduceMotion: true) == .zero)
        #expect(Tokens.Motion.appear(reduceMotion: false) > .zero)
    }
}
