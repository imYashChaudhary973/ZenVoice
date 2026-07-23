import SwiftUI

enum ZenDesign {
    enum Primitive {
        static let black950 = Color(red: 0.035, green: 0.037, blue: 0.045)
        static let black900 = Color(red: 0.055, green: 0.058, blue: 0.070)
        static let black850 = Color(red: 0.075, green: 0.078, blue: 0.092)
        static let black800 = Color(red: 0.095, green: 0.098, blue: 0.114)
        static let gold500 = Color(red: 0.76, green: 0.62, blue: 0.39)
        static let gold400 = Color(red: 0.87, green: 0.74, blue: 0.52)
        static let green500 = Color(red: 0.35, green: 0.82, blue: 0.55)
        static let red500 = Color(red: 0.95, green: 0.34, blue: 0.38)
        static let white = Color.white
    }

    enum Semantic {
        static let canvas = Primitive.black950
        static let sidebar = Primitive.black900
        static let surface = Primitive.black850
        static let surfaceRaised = Primitive.black800
        static let border = Primitive.white.opacity(0.09)
        static let borderStrong = Primitive.white.opacity(0.16)
        static let textPrimary = Primitive.white.opacity(0.96)
        static let textSecondary = Primitive.white.opacity(0.62)
        static let textTertiary = Primitive.white.opacity(0.40)
        static let accent = Primitive.gold400
        static let accentMuted = Primitive.gold500.opacity(0.16)
        static let success = Primitive.green500
        static let danger = Primitive.red500
    }

    enum Component {
        static let cardBackground = Semantic.surface
        static let cardBorder = Semantic.border
        static let selectedNavigation = Semantic.accentMuted
        static let shortcutBackground = Primitive.black950
        static let focusRing = Semantic.accent.opacity(0.62)
    }

    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 9
        static let medium: CGFloat = 14
        static let large: CGFloat = 20
    }
}
