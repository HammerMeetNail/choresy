import SwiftUI

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    init(hexUnsafe hex: String) {
        self = Color(hex: hex) ?? .black
    }

}

/// Semantic design tokens (iOS v1 plan P1/C1).
///
/// Brand hues and branded surfaces live as named colors in Assets.xcassets
/// (light + dark variants, high-contrast where the hue is used as tint/text),
/// so the system resolves appearance and accessibility variants. Structural
/// roles — text, separators — use UIKit semantic colors and inherit correct
/// dark-mode, elevated-context, and increased-contrast behavior for free.
enum DesignColors {
    // Branded surfaces (asset catalog: light / dark)
    static let pageBackground   = Color("PaperBackground")
    static let surface          = Color("Surface")
    static let surfaceSecondary = Color("SurfaceSecondary")
    static let calendarBg       = Color("CalendarBackground")

    // Brand hues (asset catalog; BrandPrimary/BrandAccent carry
    // high-contrast variants because they appear as tints and text)
    static let brand   = Color("BrandTeal")
    static let primary = Color("BrandPrimary")
    static let accent  = Color("BrandAccent")
    static let success = Color("BrandSuccess")
    static let danger  = Color("BrandDanger")

    // Structural roles: system semantics, not brand
    static let textPrimary   = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let border        = Color(uiColor: .separator)
}

enum Typography {
    static let largeTitle = Font.largeTitle
    static let title = Font.title
    static let title2 = Font.title2
    static let title3 = Font.title3
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let subheadline = Font.subheadline
    static let footnote = Font.footnote
    static let caption = Font.caption
}

extension View {
    func pageBackground() -> some View {
        background(DesignColors.pageBackground)
    }

    func surfaceCard() -> some View {
        background(DesignColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}
