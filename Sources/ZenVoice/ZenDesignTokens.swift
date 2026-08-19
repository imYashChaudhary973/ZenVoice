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

/// ZenVoice design tokens — graphite and one green.
///
/// The room this window lives in: a developer at the end of the day, terminal
/// and editor already open, dictating into whichever window has focus. The
/// settings window is the third window they reach for, so it is built to be
/// read at a glance and never to flash bright.
///
/// Three rules hold the theme together.
///
/// **The chrome is neutral.** Surfaces are a true graphite ramp with no hue in
/// them. Every earlier revision tinted the greys toward the brand green, which
/// read as olive under warm room light and fought the accent it was supposed to
/// support. Colour is information here, not decoration: if something on screen
/// is coloured, it means something.
///
/// **One accent carries the brand.** Zen green, in two weights, because one
/// colour cannot do both jobs:
///
///   * `accent` is the *foreground* weight — accent text, icons, hairlines and
///     meters drawn on a dark surface. Light enough to clear 4.5:1.
///   * `accentFill` is the *background* weight — primary buttons and anything
///     carrying a white label. Deep enough that white on it clears 4.5:1.
///
/// A single mid-green for both lands near 3.8:1 in each direction, so accent
/// text and the button label are simultaneously too faint. That is the mistake
/// this split exists to prevent.
///
/// **Structure comes from hairlines, not shadows.** Nothing in the window casts
/// a shadow. Edges are 1px borders and a step in surface value, which is what
/// keeps a dense settings window legible instead of soft.
enum ZenDesign {
    enum Primitive {
        // Graphite ramp. Never pure black: pure black kills the card edges and
        // makes the translucent sidebar look like a hole punched in the screen.
        static let base = Color(nsColor: NSColor(red: 0.043, green: 0.043, blue: 0.047, alpha: 1))
        static let base900 = Color(nsColor: NSColor(red: 0.063, green: 0.063, blue: 0.071, alpha: 1))
        static let base800 = Color(nsColor: NSColor(red: 0.118, green: 0.118, blue: 0.129, alpha: 1))

        // Surfaces float above the base by value alone.
        static let surface = Color(nsColor: NSColor(red: 0.082, green: 0.082, blue: 0.090, alpha: 1))
        static let surfaceRaised = Color(nsColor: NSColor(red: 0.118, green: 0.118, blue: 0.129, alpha: 1))
        static let surfaceSunken = Color(nsColor: NSColor(red: 0.063, green: 0.063, blue: 0.071, alpha: 1))

        // Zen green.
        static let accent = Color(nsColor: NSColor(red: 0.208, green: 0.769, blue: 0.541, alpha: 1))
        static let accentFill = Color(nsColor: NSColor(red: 0.082, green: 0.498, blue: 0.353, alpha: 1))
        static let accentMuted = Color(nsColor: NSColor(red: 0.208, green: 0.769, blue: 0.541, alpha: 0.14))

        // Text.
        static let text = Color(nsColor: NSColor(red: 0.925, green: 0.925, blue: 0.933, alpha: 1))
        static let muted = Color(nsColor: NSColor(red: 0.647, green: 0.647, blue: 0.678, alpha: 1))
        static let subtle = Color(nsColor: NSColor(red: 0.553, green: 0.553, blue: 0.603, alpha: 1))

        // Functional colours. Amber and red are the only hues besides the
        // accent, and both are reserved for state the user must act on.
        static let success = Color(nsColor: NSColor(red: 0.247, green: 0.796, blue: 0.533, alpha: 1))
        static let warn = Color(nsColor: NSColor(red: 0.890, green: 0.702, blue: 0.255, alpha: 1))
        static let danger = Color(nsColor: NSColor(red: 0.937, green: 0.420, blue: 0.420, alpha: 1))

        static let white = Color.white
        static let black = Color.black
    }

    enum Semantic {
        static let canvas = adaptive(
            light: NSColor(red: 0.980, green: 0.980, blue: 0.984, alpha: 1),
            dark: NSColor(red: 0.043, green: 0.043, blue: 0.047, alpha: 1)
        )

        /// Tint painted *over* the sidebar's vibrancy material.
        ///
        /// Low alpha on purpose: the material carries most of the value, and
        /// this only settles it enough that navigation text stays readable
        /// against a bright wallpaper.
        static let sidebar = adaptive(
            light: NSColor(red: 0.965, green: 0.965, blue: 0.972, alpha: 0.62),
            dark: NSColor(red: 0.035, green: 0.035, blue: 0.039, alpha: 0.62)
        )
        static let surface = adaptive(
            light: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),
            dark: NSColor(red: 0.082, green: 0.082, blue: 0.090, alpha: 1)
        )
        static let surfaceRaised = adaptive(
            light: NSColor(red: 0.945, green: 0.945, blue: 0.953, alpha: 1),
            dark: NSColor(red: 0.118, green: 0.118, blue: 0.129, alpha: 1)
        )
        static let surfaceSunken = adaptive(
            light: NSColor(red: 0.918, green: 0.918, blue: 0.933, alpha: 1),
            dark: NSColor(red: 0.063, green: 0.063, blue: 0.071, alpha: 1)
        )
        static let border = adaptive(
            light: NSColor(white: 0.0, alpha: 0.10),
            dark: NSColor(white: 1.0, alpha: 0.085)
        )
        static let borderStrong = adaptive(
            light: NSColor(white: 0.0, alpha: 0.17),
            dark: NSColor(white: 1.0, alpha: 0.16)
        )
        static let textPrimary = adaptive(
            light: NSColor(red: 0.090, green: 0.090, blue: 0.102, alpha: 1),
            dark: NSColor(red: 0.925, green: 0.925, blue: 0.933, alpha: 1)
        )
        static let textSecondary = adaptive(
            light: NSColor(red: 0.310, green: 0.310, blue: 0.345, alpha: 1),
            dark: NSColor(red: 0.647, green: 0.647, blue: 0.678, alpha: 1)
        )

        /// The quietest text that still has to be read: placeholders, units,
        /// row metadata.
        ///
        /// Chosen against the *raised* surface, not the canvas, because that is
        /// the worst case it actually appears on: 5.1:1 in dark and 4.9:1 in
        /// light, so it clears the 4.5:1 body-text floor everywhere it is used.
        /// The first draft of this ramp was picked against the canvas alone and
        /// landed at 3.9:1 inside a raised panel — which is the single commonest
        /// reason a dense settings window feels unreadable.
        static let textTertiary = adaptive(
            light: NSColor(red: 0.408, green: 0.408, blue: 0.447, alpha: 1),
            dark: NSColor(red: 0.553, green: 0.553, blue: 0.603, alpha: 1)
        )

        /// Foreground weight of the accent: accent text, icons, meters.
        ///
        /// Light mode uses one deep green for both weights — on a white canvas
        /// a light green cannot clear 4.5:1 as text, and does not need to be
        /// lightened to carry a white label.
        static let accent = adaptive(
            light: NSColor(red: 0.043, green: 0.420, blue: 0.294, alpha: 1),
            dark: NSColor(red: 0.208, green: 0.769, blue: 0.541, alpha: 1)
        )

        /// Background weight of the accent: primary buttons — anything that
        /// carries a white label.
        static let accentFill = adaptive(
            light: NSColor(red: 0.043, green: 0.420, blue: 0.294, alpha: 1),
            dark: NSColor(red: 0.082, green: 0.498, blue: 0.353, alpha: 1)
        )

        /// Pressed state for a filled accent control. Always moves *away* from
        /// the white label it carries, never toward it.
        static let accentStrong = adaptive(
            light: NSColor(red: 0.031, green: 0.322, blue: 0.224, alpha: 1),
            dark: NSColor(red: 0.063, green: 0.408, blue: 0.282, alpha: 1)
        )
        static let accentMuted = adaptive(
            light: NSColor(red: 0.043, green: 0.420, blue: 0.294, alpha: 0.10),
            dark: NSColor(red: 0.208, green: 0.769, blue: 0.541, alpha: 0.14)
        )
        static let success = adaptive(
            light: NSColor(red: 0.055, green: 0.420, blue: 0.255, alpha: 1),
            dark: NSColor(red: 0.247, green: 0.796, blue: 0.533, alpha: 1)
        )
        static let successMuted = adaptive(
            light: NSColor(red: 0.055, green: 0.420, blue: 0.255, alpha: 0.10),
            dark: NSColor(red: 0.247, green: 0.796, blue: 0.533, alpha: 0.14)
        )
        static let danger = adaptive(
            light: NSColor(red: 0.753, green: 0.204, blue: 0.180, alpha: 1),
            dark: NSColor(red: 0.937, green: 0.420, blue: 0.420, alpha: 1)
        )
        static let dangerMuted = adaptive(
            light: NSColor(red: 0.753, green: 0.204, blue: 0.180, alpha: 0.10),
            dark: NSColor(red: 0.937, green: 0.420, blue: 0.420, alpha: 0.14)
        )
        static let warn = adaptive(
            light: NSColor(red: 0.541, green: 0.353, blue: 0.067, alpha: 1),
            dark: NSColor(red: 0.890, green: 0.702, blue: 0.255, alpha: 1)
        )
        static let warnMuted = adaptive(
            light: NSColor(red: 0.541, green: 0.353, blue: 0.067, alpha: 0.10),
            dark: NSColor(red: 0.890, green: 0.702, blue: 0.255, alpha: 0.14)
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

        /// Selected navigation is a *quiet* raised row, not a saturated pill.
        ///
        /// A filled green row is the loudest possible mark in a window the user
        /// keeps open all day, and it made the sidebar shout its own state
        /// louder than the setting the user came to change. The active row is
        /// now identified the way an editor does it: a step up in surface, a
        /// heavier label, and the accent moved onto the icon alone.
        static let selectedNavigation = Semantic.surfaceRaised
        static let selectedNavigationLabel = Semantic.textPrimary
        static let selectedNavigationIcon = Semantic.accent
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
        /// Narrower than the previous rail. The longest label ("Languages and
        /// Models") sets the floor, and everything past that was padding that
        /// pushed the content column right for no gain.
        static let sidebarWidth: CGFloat = 216

        /// Measure for running prose — a page subtitle, a paragraph of
        /// explanation. Cards themselves are not capped: they fill the window,
        /// so full screen looks deliberate rather than centred in a column.
        static let proseColumn: CGFloat = 680

        /// Height of the transparent title bar. Tall enough to clear the
        /// traffic lights, which the window draws over the sidebar material.
        static let titleBar: CGFloat = 48

        /// Minimum hit target for anything clickable.
        static let hitTarget: CGFloat = 44

        /// Height for compact controls that sit inside a row which already
        /// meets `hitTarget`, such as paired buttons on a single line.
        static let control: CGFloat = 32

        /// Painted height of a navigation row.
        ///
        /// Denser than before: at 40pt the rail held nine rows and a scroll
        /// bar, and the window's own navigation was the least efficient part of
        /// the screen. 32pt is the height an editor sidebar uses, and the rows
        /// still nearly touch so the rail reads as one list.
        static let navRow: CGFloat = 32

        /// Icon slot in a navigation row. The glyph is drawn at
        /// `Typography.navIcon`; the slot keeps every label on one baseline
        /// regardless of how wide its symbol is.
        static let navIcon: CGFloat = 22
    }

    /// Type is one family in several weights — the system face, plus the system
    /// monospace for anything the user could retype: shortcuts, model
    /// identifiers, error rates, licence keys. Pairing two sans faces on a
    /// contrast axis this small only makes the window look uncertain.
    enum Typography {
        static let display = Font.system(size: 30, weight: .semibold)
        static let pageTitle = Font.system(size: 21, weight: .semibold)
        static let pageContext = Font.system(size: 12, weight: .medium)
        static let sectionTitle = Font.system(size: 11, weight: .semibold)
        static let body = Font.system(size: 13)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let caption = Font.system(size: 11.5)
        static let captionStrong = Font.system(size: 11.5, weight: .semibold)

        /// Button labels are medium, not semibold. At 13pt semibold on a filled
        /// control the label reads as shouting next to the row it belongs to.
        static let button = Font.system(size: 13, weight: .medium)

        /// Figures that change while the user watches them — words per minute,
        /// download percentage, decode time. Monospaced digits so the number
        /// stops jittering as it counts.
        static let metric = Font.system(size: 28, weight: .semibold).monospacedDigit()
        static let metricCaption = Font.system(size: 11, weight: .medium)

        /// Tabular figures at body size, for rows of numbers in a table.
        static let numeric = Font.system(size: 13).monospacedDigit()

        static let mono = Font.system(size: 12, design: .monospaced)
        static let monoSmall = Font.system(size: 11, design: .monospaced)

        /// Uppercase label above a group of settings. Pair with
        /// `tracking(1.1)`. Sits at the 11pt floor — uppercase text tracked out
        /// below that is the least legible type an app can ship. Used for
        /// sidebar groups and nothing else; an eyebrow over every card is
        /// scaffolding, not hierarchy.
        static let eyebrow = Font.system(size: 11, weight: .semibold)

        /// Text inside a badge or pill.
        static let badge = Font.system(size: 11, weight: .medium)

        /// Sidebar group heading.
        static let navGroup = Font.system(size: 11, weight: .semibold)

        /// Sidebar row label.
        static let navRow = Font.system(size: 13, weight: .regular)

        /// Selected sidebar row label. Weight is what marks the active row now
        /// that the row itself is quiet.
        static let navRowSelected = Font.system(size: 13, weight: .semibold)

        /// Sidebar row glyph. Slightly larger than its label so the column of
        /// icons stays scannable, but no longer the outsized mark it was when
        /// the rail was 40pt tall.
        static let navIcon = Font.system(size: 14, weight: .medium)
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

    /// Corner radii. Tighter than the previous set across the board: large soft
    /// corners read as consumer-friendly, and this is a tool that sits beside a
    /// terminal. Controls stay a step tighter than the card holding them, so
    /// nesting reads as depth rather than as one blurry shape.
    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let bar: CGFloat = 10
        static let barControl: CGFloat = 6

        /// Fully rounded — the toolbar cluster and status pills.
        static let pill: CGFloat = 999
    }
}
