// Copyright 2026 Yash Chaudhary
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AppKit
import SwiftUI

/// ZenVoice design tokens — moss on ink.
///
/// The window is a near-black canvas holding large, softly rounded cards, with
/// a translucent sidebar that lets the desktop through. One background family,
/// one surface family, one accent family, one text family.
///
/// The accent is a muted moss green. It is deliberately desaturated: a
/// saturated green at this size, filling selected navigation rows and primary
/// buttons on an almost-black canvas, glows and tires the eye over a long
/// session. Muted reads as considered, and still carries the brand.
///
/// The accent exists in two weights because one colour cannot do both jobs:
///
///   * `accent` is the *foreground* weight — accent text, icons, hairlines and
///     meters drawn directly on the canvas. It is light enough to clear 4.5:1
///     against ink.
///   * `accentFill` is the *background* weight — selected navigation, primary
///     buttons, anything that carries a white label. It is deep enough that
///     white on it clears 4.5:1.
///
/// Using one mid-green for both is the mistake this split prevents: it lands
/// near 3.8:1 in each direction, so accent text on ink and white text on the
/// button are simultaneously too faint.
enum ZenDesign {
    enum Primitive {
        // Base ink background. Never pure black — pure black kills the card
        // edges and makes the translucent sidebar look like a hole.
        static let base = Color(nsColor: NSColor(red: 0.043, green: 0.051, blue: 0.049, alpha: 1))
        static let base900 = Color(nsColor: NSColor(red: 0.063, green: 0.071, blue: 0.069, alpha: 1))
        static let base800 = Color(nsColor: NSColor(red: 0.125, green: 0.141, blue: 0.137, alpha: 1))

        // Surfaces float above the base.
        static let surface = Color(nsColor: NSColor(red: 0.086, green: 0.098, blue: 0.094, alpha: 1))
        static let surfaceRaised = Color(nsColor: NSColor(red: 0.125, green: 0.141, blue: 0.137, alpha: 1))
        static let surfaceSunken = Color(nsColor: NSColor(red: 0.063, green: 0.071, blue: 0.069, alpha: 1))

        // Moss accent family.
        static let accent = Color(nsColor: NSColor(red: 0.310, green: 0.659, blue: 0.549, alpha: 1))
        static let accentFill = Color(nsColor: NSColor(red: 0.208, green: 0.502, blue: 0.416, alpha: 1))
        static let accentMuted = Color(nsColor: NSColor(red: 0.310, green: 0.659, blue: 0.549, alpha: 0.16))

        // Text.
        static let text = Color(nsColor: NSColor(red: 0.937, green: 0.945, blue: 0.941, alpha: 1))
        static let muted = Color(nsColor: NSColor(red: 0.647, green: 0.671, blue: 0.663, alpha: 1))
        static let subtle = Color(nsColor: NSColor(red: 0.486, green: 0.510, blue: 0.502, alpha: 1))

        // Functional colours, pulled toward the same muted register so nothing
        // on screen is brighter than the accent.
        static let success = Color(nsColor: NSColor(red: 0.365, green: 0.769, blue: 0.549, alpha: 1))
        static let warn = Color(nsColor: NSColor(red: 0.902, green: 0.694, blue: 0.353, alpha: 1))
        static let danger = Color(nsColor: NSColor(red: 0.910, green: 0.427, blue: 0.412, alpha: 1))

        static let white = Color.white
        static let black = Color.black
    }

    enum Semantic {
        static let canvas = adaptive(
            light: NSColor(red: 0.965, green: 0.969, blue: 0.965, alpha: 1),
            dark: NSColor(red: 0.043, green: 0.051, blue: 0.049, alpha: 1)
        )
        /// Tint painted *over* the sidebar's vibrancy material.
        ///
        /// Low alpha on purpose: the material carries most of the colour, and
        /// this only settles it enough that navigation text stays readable
        /// against a bright wallpaper.
        static let sidebar = adaptive(
            light: NSColor(red: 0.937, green: 0.945, blue: 0.941, alpha: 0.55),
            dark: NSColor(red: 0.035, green: 0.043, blue: 0.041, alpha: 0.55)
        )
        static let surface = adaptive(
            light: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),
            dark: NSColor(red: 0.086, green: 0.098, blue: 0.094, alpha: 1)
        )
        static let surfaceRaised = adaptive(
            light: NSColor(red: 0.949, green: 0.957, blue: 0.953, alpha: 1),
            dark: NSColor(red: 0.125, green: 0.141, blue: 0.137, alpha: 1)
        )
        static let surfaceSunken = adaptive(
            light: NSColor(red: 0.910, green: 0.922, blue: 0.914, alpha: 1),
            dark: NSColor(red: 0.063, green: 0.071, blue: 0.069, alpha: 1)
        )
        static let border = adaptive(
            light: NSColor(white: 0.0, alpha: 0.08),
            dark: NSColor(white: 1.0, alpha: 0.07)
        )
        static let borderStrong = adaptive(
            light: NSColor(white: 0.0, alpha: 0.14),
            dark: NSColor(white: 1.0, alpha: 0.13)
        )
        static let textPrimary = adaptive(
            light: NSColor(red: 0.078, green: 0.094, blue: 0.086, alpha: 1),
            dark: NSColor(red: 0.937, green: 0.945, blue: 0.941, alpha: 1)
        )
        static let textSecondary = adaptive(
            light: NSColor(red: 0.373, green: 0.400, blue: 0.388, alpha: 1),
            dark: NSColor(red: 0.647, green: 0.671, blue: 0.663, alpha: 1)
        )
        static let textTertiary = adaptive(
            light: NSColor(red: 0.494, green: 0.518, blue: 0.506, alpha: 1),
            dark: NSColor(red: 0.486, green: 0.510, blue: 0.502, alpha: 1)
        )

        /// Foreground weight of the accent: accent text, icons, meters.
        ///
        /// Light mode uses one deep moss for both weights — on a white canvas
        /// a light green cannot clear 4.5:1 as text, and does not need to be
        /// lightened to carry white as a fill.
        static let accent = adaptive(
            light: NSColor(red: 0.102, green: 0.373, blue: 0.294, alpha: 1),
            dark: NSColor(red: 0.310, green: 0.659, blue: 0.549, alpha: 1)
        )

        /// Background weight of the accent: selected navigation, primary
        /// buttons — anything that carries a white label.
        static let accentFill = adaptive(
            light: NSColor(red: 0.102, green: 0.373, blue: 0.294, alpha: 1),
            dark: NSColor(red: 0.208, green: 0.502, blue: 0.416, alpha: 1)
        )

        /// Pressed state for a filled accent control. Always moves *away* from
        /// the white label it carries, never toward it.
        static let accentStrong = adaptive(
            light: NSColor(red: 0.071, green: 0.286, blue: 0.224, alpha: 1),
            dark: NSColor(red: 0.161, green: 0.404, blue: 0.333, alpha: 1)
        )
        static let accentMuted = adaptive(
            light: NSColor(red: 0.102, green: 0.373, blue: 0.294, alpha: 0.10),
            dark: NSColor(red: 0.310, green: 0.659, blue: 0.549, alpha: 0.16)
        )
        static let success = adaptive(
            light: NSColor(red: 0.129, green: 0.510, blue: 0.302, alpha: 1),
            dark: NSColor(red: 0.365, green: 0.769, blue: 0.549, alpha: 1)
        )
        static let successMuted = adaptive(
            light: NSColor(red: 0.129, green: 0.510, blue: 0.302, alpha: 0.10),
            dark: NSColor(red: 0.365, green: 0.769, blue: 0.549, alpha: 0.14)
        )
        static let danger = adaptive(
            light: NSColor(red: 0.769, green: 0.235, blue: 0.220, alpha: 1),
            dark: NSColor(red: 0.910, green: 0.427, blue: 0.412, alpha: 1)
        )
        static let dangerMuted = adaptive(
            light: NSColor(red: 0.769, green: 0.235, blue: 0.220, alpha: 0.10),
            dark: NSColor(red: 0.910, green: 0.427, blue: 0.412, alpha: 0.14)
        )
        static let warn = adaptive(
            light: NSColor(red: 0.639, green: 0.443, blue: 0.129, alpha: 1),
            dark: NSColor(red: 0.902, green: 0.694, blue: 0.353, alpha: 1)
        )
        static let warnMuted = adaptive(
            light: NSColor(red: 0.639, green: 0.443, blue: 0.129, alpha: 0.10),
            dark: NSColor(red: 0.902, green: 0.694, blue: 0.353, alpha: 0.14)
        )

        /// Text drawn on top of `accentFill`.
        ///
        /// White in both appearances, which is only true because `accentFill`
        /// is the deep weight of the accent in both. It clears 4.5:1 on each.
        static let textOnAccent = adaptive(
            light: NSColor(white: 1.0, alpha: 1),
            dark: NSColor(white: 1.0, alpha: 1)
        )

        /// Text drawn on top of a `danger`-filled control.
        static let textOnDanger = adaptive(
            light: NSColor(white: 1.0, alpha: 1),
            dark: NSColor(white: 1.0, alpha: 1)
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
        /// Selected navigation is a *filled* accent pill carrying a white
        /// label — the strongest single mark in the window, and the only place
        /// the fill weight is used at rest.
        static let selectedNavigation = Semantic.accentFill
        static let shortcutBackground = Semantic.surfaceRaised
        static let focusRing = Semantic.accent.opacity(0.55)
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    /// Structural measurements shared by the window chrome.
    ///
    /// The sidebar width lives here because the title bar has to reserve
    /// exactly the same width for the brand block. Two hand-copied constants
    /// drifted apart; one named value cannot.
    enum Layout {
        static let sidebarWidth: CGFloat = 240
        /// Measure for running prose — a page subtitle, a paragraph of
        /// explanation. Cards themselves are not capped: they fill the window,
        /// so full screen looks deliberate rather than centred in a column.
        static let proseColumn: CGFloat = 720

        /// Height of the transparent title bar. Tall enough to clear the
        /// traffic lights, which the window draws over the sidebar material.
        static let titleBar: CGFloat = 52

        /// Minimum hit target for anything clickable.
        static let hitTarget: CGFloat = 44

        /// Height for compact controls that sit inside a row which already
        /// meets `hitTarget`, such as paired buttons on a single line.
        static let control: CGFloat = 32

        /// Painted height of a navigation row in the sidebar.
        ///
        /// Four points short of `hitTarget`, so consecutive rows nearly touch
        /// — as the approved design shows. At 36 the 8pt gutters read as
        /// deliberate separators and broke the rail into floating chips.
        static let navRow: CGFloat = 40

        /// Icon slot in a navigation row. The glyph is drawn at
        /// `Typography.navIcon`; the slot keeps every label on one baseline
        /// regardless of how wide its symbol is.
        static let navIcon: CGFloat = 26
    }

    enum Typography {
        static let display = Font.system(size: 34, weight: .bold)
        static let pageTitle = Font.system(size: 24, weight: .bold)
        static let pageContext = Font.system(size: 12, weight: .semibold)
        static let sectionTitle = Font.system(size: 11, weight: .semibold)
        static let body = Font.system(size: 13)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let caption = Font.system(size: 11.5)
        static let captionStrong = Font.system(size: 11.5, weight: .semibold)
        static let button = Font.system(size: 13, weight: .semibold)
        static let metric = Font.system(size: 34, weight: .bold)
        static let metricCaption = Font.system(size: 11, weight: .medium)
        static let mono = Font.system(size: 12, design: .monospaced)
        static let monoSmall = Font.system(size: 11, design: .monospaced)

        /// Uppercase label above a column, card or field. Pair with
        /// `tracking(1.2)`. Sits at the 11pt floor — uppercase text tracked
        /// out below that is the least legible type an app can ship.
        static let eyebrow = Font.system(size: 11, weight: .semibold)

        /// Text inside a badge or pill.
        static let badge = Font.system(size: 11, weight: .semibold)

        /// Sidebar group heading.
        static let navGroup = Font.system(size: 12, weight: .semibold)

        /// Sidebar row label.
        static let navRow = Font.system(size: 15, weight: .medium)

        /// Selected sidebar row label. Weight, not colour, is what separates
        /// it from its neighbours once the pill is already carrying the
        /// accent.
        static let navRowSelected = Font.system(size: 15, weight: .semibold)

        /// Sidebar row glyph. Deliberately larger than the label: in the
        /// approved design the icons are the thing you scan, and at 13pt they
        /// were smaller than the text beside them and read as decoration.
        static let navIcon = Font.system(size: 19, weight: .medium)
    }

    /// Motion vocabulary: quick easeOut fades/slides everywhere; the single
    /// spring is reserved for the ZenBar waveform — the one living element.
    /// Helpers return `nil` when Reduce Motion is on, so call sites pass
    /// `@Environment(\.accessibilityReduceMotion)` straight through.
    enum Motion {
        static let fastDuration: Double = 0.15
        static let standardDuration: Double = 0.22

        static func fast(_ reduceMotion: Bool = false) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: fastDuration)
        }

        static func standard(_ reduceMotion: Bool = false) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: standardDuration)
        }

        /// ZenBar waveform only.
        static func waveform(_ reduceMotion: Bool = false) -> Animation? {
            reduceMotion
                ? nil
                : .spring(response: 0.35, dampingFraction: 0.7)
        }
    }

    /// Corner radii. Cards are large and soft; controls inside them are
    /// tighter, so nesting reads as depth rather than as one blurry shape.
    /// The ZenBar floats above the desktop and keeps its own tight radius.
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let bar: CGFloat = 9
        static let barControl: CGFloat = 6

        /// Fully rounded — the toolbar cluster and status pills.
        static let pill: CGFloat = 999
    }
}
