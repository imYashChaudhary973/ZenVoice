import AppKit
import SwiftUI

/// ZenVoice v2 design tokens — "Ink & Gold", restrained strategy.
/// Contract: ZenVoiceNewDesign/DESIGN.md (values converted from OKLCH to sRGB).
enum ZenDesign {
    enum Primitive {
        static let ink950 = Color(red: 0.033, green: 0.040, blue: 0.053)
        static let ink900 = Color(red: 0.051, green: 0.059, blue: 0.074)
        static let ink850 = Color(red: 0.073, green: 0.082, blue: 0.100)
        static let ink800 = Color(red: 0.099, green: 0.109, blue: 0.130)
        static let gold300 = Color(red: 0.857, green: 0.738, blue: 0.539)
        static let gold200 = Color(red: 0.923, green: 0.802, blue: 0.583)
        static let gold700 = Color(red: 0.523, green: 0.382, blue: 0.168)
        static let gold800 = Color(red: 0.447, green: 0.301, blue: 0.043)
        static let green400 = Color(red: 0.350, green: 0.828, blue: 0.550)
        static let red400 = Color(red: 0.964, green: 0.421, blue: 0.444)

        // Back-compat aliases (pre-v2 names still referenced in views).
        static let gold500 = gold300
        static let gold400 = gold200
        static let black950 = ink950
        static let white = Color.white
    }

    enum Semantic {
        static let canvas = adaptive(
            light: NSColor(red: 0.960, green: 0.964, blue: 0.969, alpha: 1),
            dark: NSColor(red: 0.033, green: 0.040, blue: 0.053, alpha: 1)
        )
        static let sidebar = adaptive(
            light: NSColor(red: 0.925, green: 0.930, blue: 0.938, alpha: 1),
            dark: NSColor(red: 0.051, green: 0.059, blue: 0.074, alpha: 1)
        )
        static let surface = adaptive(
            light: .white,
            dark: NSColor(red: 0.073, green: 0.082, blue: 0.100, alpha: 1)
        )
        static let surfaceRaised = adaptive(
            light: NSColor(red: 0.941, green: 0.945, blue: 0.953, alpha: 1),
            dark: NSColor(red: 0.099, green: 0.109, blue: 0.130, alpha: 1)
        )
        static let surfaceSunken = adaptive(
            light: NSColor(red: 0.913, green: 0.920, blue: 0.930, alpha: 1),
            dark: NSColor(red: 0.024, green: 0.029, blue: 0.041, alpha: 1)
        )
        static let border = adaptive(
            light: NSColor(red: 0.080, green: 0.091, blue: 0.113, alpha: 0.09),
            dark: NSColor(white: 1, alpha: 0.08)
        )
        static let borderStrong = adaptive(
            light: NSColor(red: 0.080, green: 0.091, blue: 0.113, alpha: 0.17),
            dark: NSColor(white: 1, alpha: 0.15)
        )
        static let textPrimary = adaptive(
            light: NSColor(red: 0.080, green: 0.091, blue: 0.113, alpha: 1),
            dark: NSColor(white: 1, alpha: 0.95)
        )
        static let textSecondary = adaptive(
            light: NSColor(red: 0.291, green: 0.302, blue: 0.324, alpha: 1),
            dark: NSColor(white: 1, alpha: 0.64)
        )
        static let textTertiary = adaptive(
            light: NSColor(red: 0.413, green: 0.423, blue: 0.441, alpha: 1),
            dark: NSColor(white: 1, alpha: 0.42)
        )
        static let accent = adaptive(
            light: NSColor(red: 0.523, green: 0.382, blue: 0.168, alpha: 1),
            dark: NSColor(red: 0.857, green: 0.738, blue: 0.539, alpha: 1)
        )
        static let accentStrong = adaptive(
            light: NSColor(red: 0.447, green: 0.301, blue: 0.043, alpha: 1),
            dark: NSColor(red: 0.923, green: 0.802, blue: 0.583, alpha: 1)
        )
        static let accentMuted = adaptive(
            light: NSColor(red: 0.523, green: 0.382, blue: 0.168, alpha: 0.11),
            dark: NSColor(red: 0.857, green: 0.738, blue: 0.539, alpha: 0.13)
        )
        static let success = adaptive(
            light: NSColor(red: 0.000, green: 0.470, blue: 0.253, alpha: 1),
            dark: NSColor(red: 0.350, green: 0.828, blue: 0.550, alpha: 1)
        )
        static let successMuted = adaptive(
            light: NSColor(red: 0.000, green: 0.470, blue: 0.253, alpha: 0.11),
            dark: NSColor(red: 0.350, green: 0.828, blue: 0.550, alpha: 0.13)
        )
        static let danger = adaptive(
            light: NSColor(red: 0.758, green: 0.146, blue: 0.209, alpha: 1),
            dark: NSColor(red: 0.964, green: 0.421, blue: 0.444, alpha: 1)
        )
        static let dangerMuted = adaptive(
            light: NSColor(red: 0.758, green: 0.146, blue: 0.209, alpha: 0.10),
            dark: NSColor(red: 0.964, green: 0.421, blue: 0.444, alpha: 0.14)
        )
        static let warn = adaptive(
            light: NSColor(red: 0.617, green: 0.387, blue: 0.000, alpha: 1),
            dark: NSColor(red: 0.890, green: 0.713, blue: 0.405, alpha: 1)
        )
        static let warnMuted = adaptive(
            light: NSColor(red: 0.617, green: 0.387, blue: 0.000, alpha: 0.12),
            dark: NSColor(red: 0.890, green: 0.713, blue: 0.405, alpha: 0.13)
        )
        static let textOnAccent = adaptive(
            light: .white,
            dark: NSColor(red: 0.044, green: 0.052, blue: 0.069, alpha: 1)
        )

        private static func adaptive(light: NSColor, dark: NSColor) -> Color {
            Color(
                nsColor: NSColor(name: nil) { appearance in
                    let match = appearance.bestMatch(from: [.aqua, .darkAqua])
                    return match == .darkAqua ? dark : light
                }
            )
        }
    }

    enum Component {
        static let cardBackground = Semantic.surface
        static let cardBorder = Semantic.border
        static let selectedNavigation = Semantic.accentMuted
        static let shortcutBackground = Semantic.surface
        static let focusRing = Semantic.accent.opacity(0.35)
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    /// Fixed rem-style scale, ratio ≈ 1.2 (DESIGN.md §3).
    enum Typography {
        static let display = Font.system(size: 26, weight: .bold)
        static let pageTitle = Font.system(size: 20, weight: .bold)
        static let pageContext = Font.system(size: 12, weight: .semibold)
        static let sectionTitle = Font.system(size: 15, weight: .semibold)
        static let body = Font.system(size: 13)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let caption = Font.system(size: 11.5)
        static let captionStrong = Font.system(size: 11.5, weight: .semibold)
        static let button = Font.system(size: 13, weight: .semibold)
        static let metric = Font.system(size: 22, weight: .semibold)
        static let mono = Font.system(size: 12, design: .monospaced)
        static let monoSmall = Font.system(size: 10.5, design: .monospaced)
    }

    enum Radius {
        static let small: CGFloat = 7    // controls
        static let medium: CGFloat = 12  // panels
        static let large: CGFloat = 16   // ceiling — nothing rounder
    }
}
