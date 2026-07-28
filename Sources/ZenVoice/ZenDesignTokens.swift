import AppKit
import SwiftUI

/// ZenVoice v3 design tokens — "Ledger", warm editorial utility.
/// Native adaptive colors shared across the Ledger interface.
enum ZenDesign {
    enum Primitive {
        static let ink950 = Color(red: 0.122, green: 0.114, blue: 0.102)
        static let ink900 = Color(red: 0.125, green: 0.118, blue: 0.106)
        static let ink850 = Color(red: 0.149, green: 0.141, blue: 0.129)
        static let ink800 = Color(red: 0.173, green: 0.165, blue: 0.145)
        static let rust300 = Color(red: 0.878, green: 0.604, blue: 0.451)
        static let rust400 = Color(red: 0.839, green: 0.541, blue: 0.384)
        static let rust700 = Color(red: 0.651, green: 0.286, blue: 0.180)
        static let rust800 = Color(red: 0.588, green: 0.259, blue: 0.165)
        static let green400 = Color(red: 0.498, green: 0.714, blue: 0.537)
        static let red400 = Color(red: 0.851, green: 0.482, blue: 0.400)

        // Back-compat aliases (pre-v2 names still referenced in views).
        static let gold300 = rust400
        static let gold200 = rust300
        static let gold700 = rust700
        static let gold800 = rust800
        static let gold500 = rust400
        static let gold400 = rust300
        static let black950 = ink950
        static let white = Color.white
    }

    enum Semantic {
        static let canvas = adaptive(
            light: NSColor(red: 0.969, green: 0.961, blue: 0.941, alpha: 1),
            dark: NSColor(red: 0.047, green: 0.051, blue: 0.057, alpha: 1)
        )
        static let sidebar = adaptive(
            light: NSColor(red: 0.969, green: 0.961, blue: 0.941, alpha: 1),
            dark: NSColor(red: 0.035, green: 0.039, blue: 0.043, alpha: 1)
        )
        static let surface = adaptive(
            light: NSColor(red: 0.988, green: 0.984, blue: 0.969, alpha: 1),
            dark: NSColor(red: 0.078, green: 0.082, blue: 0.090, alpha: 1)
        )
        static let surfaceRaised = adaptive(
            light: NSColor(red: 0.945, green: 0.933, blue: 0.906, alpha: 1),
            dark: NSColor(red: 0.110, green: 0.118, blue: 0.129, alpha: 1)
        )
        static let surfaceSunken = adaptive(
            light: NSColor(red: 0.898, green: 0.882, blue: 0.839, alpha: 1),
            dark: NSColor(red: 0.137, green: 0.145, blue: 0.157, alpha: 1)
        )
        static let border = adaptive(
            light: NSColor(red: 0.216, green: 0.176, blue: 0.125, alpha: 0.09),
            dark: NSColor(white: 0.92, alpha: 0.08)
        )
        static let borderStrong = adaptive(
            light: NSColor(red: 0.216, green: 0.176, blue: 0.125, alpha: 0.16),
            dark: NSColor(white: 0.92, alpha: 0.15)
        )
        static let textPrimary = adaptive(
            light: NSColor(red: 0.122, green: 0.114, blue: 0.102, alpha: 1),
            dark: NSColor(red: 0.925, green: 0.918, blue: 0.902, alpha: 1)
        )
        static let textSecondary = adaptive(
            light: NSColor(red: 0.361, green: 0.337, blue: 0.298, alpha: 1),
            dark: NSColor(red: 0.690, green: 0.682, blue: 0.663, alpha: 1)
        )
        static let textTertiary = adaptive(
            light: NSColor(red: 0.545, green: 0.514, blue: 0.467, alpha: 1),
            dark: NSColor(red: 0.500, green: 0.494, blue: 0.482, alpha: 1)
        )
        static let accent = adaptive(
            light: NSColor(red: 0.651, green: 0.286, blue: 0.180, alpha: 1),
            dark: NSColor(red: 0.839, green: 0.541, blue: 0.384, alpha: 1)
        )
        static let accentStrong = adaptive(
            light: NSColor(red: 0.588, green: 0.259, blue: 0.165, alpha: 1),
            dark: NSColor(red: 0.878, green: 0.604, blue: 0.451, alpha: 1)
        )
        static let accentMuted = adaptive(
            light: NSColor(red: 0.651, green: 0.286, blue: 0.180, alpha: 0.08),
            dark: NSColor(red: 0.839, green: 0.541, blue: 0.384, alpha: 0.12)
        )
        static let success = adaptive(
            light: NSColor(red: 0.200, green: 0.443, blue: 0.247, alpha: 1),
            dark: NSColor(red: 0.498, green: 0.714, blue: 0.537, alpha: 1)
        )
        static let successMuted = adaptive(
            light: NSColor(red: 0.200, green: 0.443, blue: 0.247, alpha: 0.10),
            dark: NSColor(red: 0.498, green: 0.714, blue: 0.537, alpha: 0.12)
        )
        static let danger = adaptive(
            light: NSColor(red: 0.675, green: 0.227, blue: 0.165, alpha: 1),
            dark: NSColor(red: 0.851, green: 0.482, blue: 0.400, alpha: 1)
        )
        static let dangerMuted = adaptive(
            light: NSColor(red: 0.675, green: 0.227, blue: 0.165, alpha: 0.10),
            dark: NSColor(red: 0.851, green: 0.482, blue: 0.400, alpha: 0.12)
        )
        static let warn = adaptive(
            light: NSColor(red: 0.561, green: 0.392, blue: 0.063, alpha: 1),
            dark: NSColor(red: 0.824, green: 0.663, blue: 0.349, alpha: 1)
        )
        static let warnMuted = adaptive(
            light: NSColor(red: 0.561, green: 0.392, blue: 0.063, alpha: 0.10),
            dark: NSColor(red: 0.824, green: 0.663, blue: 0.349, alpha: 0.12)
        )
        static let textOnAccent = adaptive(
            light: NSColor(red: 0.984, green: 0.965, blue: 0.941, alpha: 1),
            dark: NSColor(red: 0.133, green: 0.082, blue: 0.063, alpha: 1)
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

    /// Ledger pairs restrained system text with editorial serif display type.
    enum Typography {
        static let display = Font.system(size: 30, weight: .semibold, design: .serif)
        static let pageTitle = Font.system(size: 26, weight: .semibold, design: .serif)
        static let pageContext = Font.system(size: 11, weight: .semibold)
        static let sectionTitle = Font.system(size: 10, weight: .semibold)
        static let body = Font.system(size: 13)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let caption = Font.system(size: 11.5)
        static let captionStrong = Font.system(size: 11.5, weight: .semibold)
        static let button = Font.system(size: 13, weight: .semibold)
        static let metric = Font.system(size: 22, weight: .semibold, design: .serif)
        static let mono = Font.system(size: 12, design: .monospaced)
        static let monoSmall = Font.system(size: 10.5, design: .monospaced)
    }

    enum Radius {
        static let small: CGFloat = 4
        static let medium: CGFloat = 4
        static let large: CGFloat = 10
    }
}
