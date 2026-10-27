import SwiftUI

// Tokens de DESIGN.md. Los colores viven en Assets.xcassets (variante clara y oscura) y se usan
// con los símbolos que Xcode genera: `.accentFill`, `.inkMuted`, `.accentSoft`…
// El tint de la app (AccentColor) es `accent-text`: el naranja que se lee. `.accentFill` es el
// naranja que se rellena y siempre lleva texto `.accentInk` encima.

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    /// Separación entre secciones de una pantalla.
    static let section: CGFloat = 26
    static let xxl: CGFloat = 28
}

enum Radius {
    static let segmentInner: CGFloat = 9
    static let segment: CGFloat = 11
    static let control: CGFloat = 12
    static let card: CGFloat = 16
    static let primaryButton: CGFloat = 18
}
