import AppKit
import SwiftUI

enum ZenDesign {
    enum Primitive {
        static let black950 = Color(red: 0.035, green: 0.037, blue: 0.045)
        static let black900 = Color(red: 0.055, green: 0.058, blue: 0.070)
        static let black850 = Color(red: 0.075, green: 0.078, blue: 0.092)
        static let black800 = Color(red: 0.095, green: 0.098, blue: 0.114)
        static let lightCanvas = Color(red: 0.961, green: 0.961, blue: 0.969)
        static let lightSidebar = Color(red: 0.925, green: 0.929, blue: 0.937)
        static let lightSurface = Color.white
        static let lightRaised = Color(red: 0.941, green: 0.945, blue: 0.953)
        static let gold500 = Color(red: 0.76, green: 0.62, blue: 0.39)
        static let gold400 = Color(red: 0.87, green: 0.74, blue: 0.52)
        static let gold700 = Color(red: 0.541, green: 0.408, blue: 0.184)
        static let gold100 = Color(red: 0.945, green: 0.906, blue: 0.831)
        static let green500 = Color(red: 0.35, green: 0.82, blue: 0.55)
        static let green700 = Color(red: 0.141, green: 0.478, blue: 0.267)
        static let red500 = Color(red: 0.95, green: 0.34, blue: 0.38)
        static let red700 = Color(red: 0.769, green: 0.204, blue: 0.231)
        static let white = Color.white
        static let ink = Color(red: 0.067, green: 0.071, blue: 0.086)
        static let inkSecondary = Color(red: 0.302, green: 0.314, blue: 0.345)
        static let inkTertiary = Color(red: 0.420, green: 0.435, blue: 0.471)
    }

    enum Semantic {
        static let canvas = adaptive(
            light: NSColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1),
            dark: NSColor(red: 0.035, green: 0.037, blue: 0.045, alpha: 1)
        )
        static let sidebar = adaptive(
            light: NSColor(red: 0.925, green: 0.929, blue: 0.937, alpha: 1),
            dark: NSColor(red: 0.055, green: 0.058, blue: 0.070, alpha: 1)
        )
        static let surface = adaptive(
            light: .white,
            dark: NSColor(red: 0.075, green: 0.078, blue: 0.092, alpha: 1)
        )
        static let surfaceRaised = adaptive(
            light: NSColor(red: 0.941, green: 0.945, blue: 0.953, alpha: 1),
            dark: NSColor(red: 0.095, green: 0.098, blue: 0.114, alpha: 1)
        )
        static let border = adaptive(
            light: NSColor(red: 0.067, green: 0.071, blue: 0.086, alpha: 0.10),
            dark: NSColor(white: 1, alpha: 0.09)
        )
        static let borderStrong = adaptive(
            light: NSColor(red: 0.067, green: 0.071, blue: 0.086, alpha: 0.18),
            dark: NSColor(white: 1, alpha: 0.16)
        )
        static let textPrimary = adaptive(
            light: NSColor(red: 0.067, green: 0.071, blue: 0.086, alpha: 1),
            dark: NSColor(white: 1, alpha: 0.96)
        )
        static let textSecondary = adaptive(
            light: NSColor(red: 0.302, green: 0.314, blue: 0.345, alpha: 1),
            dark: NSColor(white: 1, alpha: 0.62)
        )
        static let textTertiary = adaptive(
            light: NSColor(red: 0.420, green: 0.435, blue: 0.471, alpha: 1),
            dark: NSColor(white: 1, alpha: 0.40)
        )
        static let accent = adaptive(
            light: NSColor(red: 0.541, green: 0.408, blue: 0.184, alpha: 1),
            dark: NSColor(red: 0.87, green: 0.74, blue: 0.52, alpha: 1)
        )
        static let accentMuted = adaptive(
            light: NSColor(red: 0.945, green: 0.906, blue: 0.831, alpha: 1),
            dark: NSColor(red: 0.76, green: 0.62, blue: 0.39, alpha: 0.16)
        )
        static let success = adaptive(
            light: NSColor(red: 0.141, green: 0.478, blue: 0.267, alpha: 1),
            dark: NSColor(red: 0.35, green: 0.82, blue: 0.55, alpha: 1)
        )
        static let danger = adaptive(
            light: NSColor(red: 0.769, green: 0.204, blue: 0.231, alpha: 1),
            dark: NSColor(red: 0.95, green: 0.34, blue: 0.38, alpha: 1)
        )
        static let textOnAccent = adaptive(
            light: .white,
            dark: NSColor(red: 0.035, green: 0.037, blue: 0.045, alpha: 1)
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
        static let focusRing = Semantic.accent.opacity(0.62)
    }

    enum Spacing {
        static let xs: CGFloat = 10
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 32
    }

    enum Typography {
        static let pageTitle = Font.system(size: 30, weight: .bold)
        static let pageContext = Font.system(size: 12, weight: .semibold)
        static let sectionTitle = Font.system(size: 15, weight: .semibold)
        static let body = Font.system(size: 13)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let caption = Font.system(size: 12)
        static let captionStrong = Font.system(size: 12, weight: .semibold)
        static let button = Font.system(size: 13, weight: .semibold)
        static let metric = Font.system(size: 22, weight: .semibold)
    }

    enum Radius {
        static let small: CGFloat = 9
        static let medium: CGFloat = 14
        static let large: CGFloat = 20
    }
}
