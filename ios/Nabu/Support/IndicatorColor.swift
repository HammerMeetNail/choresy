import SwiftUI

/// Stable colors for indicator/stack labels, ported from the PWA's
/// `colorForIndicator` (`web/static/js/stats.js`). The four predefined
/// baby-care labels keep their historical colors for continuity; any other
/// label (including user-defined chore indicator labels) gets a stable color
/// from a distinct palette via a hash of the label text, so custom labels get
/// identical colors on both clients. Kept in sync with the PWA — see
/// docs/plans/client-parity.md.
enum IndicatorColor {
    static let knownColors: [String: String] = [
        "🍼 formula": "#EC4899",
        "🤱 breast": "#F59E0B",
        "💩 poo": "#8B4513",
        "💛 pee": "#FACC15",
    ]

    static let palette: [String] = [
        "#2E86AB", "#A23B72", "#F18F01", "#386641", "#8B5CF6",
        "#0EA5E9", "#DB2777", "#65A30D", "#D97706", "#0D9488",
        "#7C3AED", "#059669",
    ]

    /// JS `hashLabel`: h = (Math.imul(h, 31) + s.charCodeAt(i)) | 0 over
    /// UTF-16 code units, then Math.abs. Int32 wrapping arithmetic over
    /// String.utf16 reproduces it exactly (JS strings are UTF-16).
    static func hashLabel(_ s: String) -> UInt32 {
        var h: Int32 = 0
        for unit in s.utf16 {
            h = h &* 31 &+ Int32(unit)
        }
        return h.magnitude
    }

    /// Hex color (e.g. "#EC4899") for an indicator/stack label.
    static func hexColor(for label: String?) -> String {
        guard let label else { return palette[0] }
        if let known = knownColors[label] { return known }
        return palette[Int(hashLabel(label)) % palette.count]
    }

    /// SwiftUI color for an indicator/stack label.
    static func color(for label: String?) -> Color {
        Color(hexUnsafe: hexColor(for: label))
    }
}
