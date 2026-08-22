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

/// ZenVoice design tokens translated from the supplied graphite/violet system.
enum ZenDesign {
    enum Primitive {
        static let base = Color(nsColor: NSColor(red: 0.094, green: 0.094, blue: 0.106, alpha: 1))
        static let base900 = Color(nsColor: NSColor(red: 0.071, green: 0.071, blue: 0.078, alpha: 1))
        static let base800 = Color(nsColor: NSColor(red: 0.141, green: 0.141, blue: 0.157, alpha: 1))

        static let surface = Color(nsColor: NSColor(red: 0.118, green: 0.118, blue: 0.133, alpha: 1))
        static let surfaceRaised = Color(nsColor: NSColor(red: 0.141, green: 0.141, blue: 0.157, alpha: 1))
        static let surfaceSunken = Color(nsColor: NSColor(red: 0.071, green: 0.071, blue: 0.078, alpha: 1))

        static let accent = Color(nsColor: NSColor(red: 0.671, green: 0.545, blue: 0.945, alpha: 1))
        static let accentFill = Color(nsColor: NSColor(red: 0.486, green: 0.310, blue: 0.878, alpha: 1))
        static let accentMuted = Color(nsColor: NSColor(red: 0.486, green: 0.310, blue: 0.878, alpha: 0.18))

        static let text = Color(nsColor: NSColor(white: 1, alpha: 0.92))
        static let muted = Color(nsColor: NSColor(white: 1, alpha: 0.62))
        static let subtle = Color(nsColor: NSColor(white: 1, alpha: 0.56))

        static let success = Color(nsColor: NSColor(red: 0.204, green: 0.780, blue: 0.471, alpha: 1))
        static let warn = Color(nsColor: NSColor(red: 0.878, green: 0.647, blue: 0.173, alpha: 1))
        static let danger = Color(nsColor: NSColor(red: 0.937, green: 0.294, blue: 0.294, alpha: 1))

        static let white = Color.white
        static let black = Color.black
    }

    enum Semantic {
        static let canvas = Color(nsColor: .windowBackgroundColor)
        static let sidebar = Color(nsColor: .controlBackgroundColor)
        static let surface = Color(nsColor: .controlBackgroundColor)
        static let surfaceRaised = Color(nsColor: .underPageBackgroundColor)
        static let surfaceSunken = Color(nsColor: .textBackgroundColor)
        static let border = Color(nsColor: .separatorColor)
        static let borderStrong = Color(nsColor: .gridColor)
        static let textPrimary = Color(nsColor: .labelColor)
        static let textSecondary = Color(nsColor: .secondaryLabelColor)

        /// The quietest text that still has to be read: placeholders, units,
        /// and row metadata. AppKit adjusts it for appearance and contrast.
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)

        /// Foreground weight of the accent: accent text, icons, meters.
        ///
        /// The lighter weight clears 4.5:1 on the raised graphite surface.
        static let accent = adaptive(
            light: NSColor(red: 0.325, green: 0.180, blue: 0.710, alpha: 1),
            dark: NSColor(red: 0.671, green: 0.545, blue: 0.945, alpha: 1)
        )

        /// Background weight of the accent for prominent controls.
        static let accentFill = adaptive(
            light: NSColor(red: 0.420, green: 0.245, blue: 0.820, alpha: 1),
            dark: NSColor(red: 0.540, green: 0.370, blue: 0.930, alpha: 1)
        )

        static let accentStrong = adaptive(
            light: NSColor(red: 0.315, green: 0.165, blue: 0.660, alpha: 1),
            dark: NSColor(red: 0.430, green: 0.280, blue: 0.800, alpha: 1)
        )
        static let accentMuted = adaptive(
            light: NSColor(red: 0.420, green: 0.245, blue: 0.820, alpha: 0.12),
            dark: NSColor(red: 0.540, green: 0.370, blue: 0.930, alpha: 0.18)
        )
        static let success = adaptive(
            light: NSColor(red: 0.204, green: 0.780, blue: 0.471, alpha: 1),
            dark: NSColor(red: 0.204, green: 0.780, blue: 0.471, alpha: 1)
        )
        static let successMuted = adaptive(
            light: NSColor(red: 0.055, green: 0.420, blue: 0.255, alpha: 0.10),
            dark: NSColor(red: 0.247, green: 0.796, blue: 0.533, alpha: 0.14)
        )
        static let danger = adaptive(
            light: NSColor(red: 0.937, green: 0.294, blue: 0.294, alpha: 1),
            dark: NSColor(red: 0.937, green: 0.294, blue: 0.294, alpha: 1)
        )
        static let dangerMuted = adaptive(
            light: NSColor(red: 0.753, green: 0.204, blue: 0.180, alpha: 0.10),
            dark: NSColor(red: 0.937, green: 0.420, blue: 0.420, alpha: 0.14)
        )
        static let warn = adaptive(
            light: NSColor(red: 0.878, green: 0.647, blue: 0.173, alpha: 1),
            dark: NSColor(red: 0.878, green: 0.647, blue: 0.173, alpha: 1)
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

        static let selectedNavigation = Semantic.accentMuted
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
        /// The wider reference rail gives 15pt labels and 18pt glyphs enough
        /// room to keep their generous spacing without truncation.
        static let sidebarWidth: CGFloat = 236

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

        /// Painted height of a navigation row. It also meets the pointer and
        /// accessibility hit target without needing invisible overflow.
        static let navRow: CGFloat = 44

        /// Icon slot in a navigation row. The glyph is drawn at
        /// `Typography.navIcon`; the slot keeps every label on one baseline
        /// regardless of how wide its symbol is.
        static let navIcon: CGFloat = 24
    }

    /// Type is one family in several weights — the system face, plus the system
    /// monospace for anything the user could retype: shortcuts, model
    /// identifiers, error rates, licence keys. Pairing two sans faces on a
    /// contrast axis this small only makes the window look uncertain.
    enum Typography {
        static let display = Font.system(size: 30, weight: .semibold)
        static let pageTitle = Font.system(size: 21, weight: .semibold)
        static let pageContext = Font.system(size: 12, weight: .medium)
        static let sectionTitle = Font.system(size: 17, weight: .semibold)
        static let body = Font.system(size: 14)
        static let bodyStrong = Font.system(size: 14, weight: .semibold)
        static let caption = Font.system(size: 12)
        static let captionStrong = Font.system(size: 12, weight: .semibold)

        /// Button labels are medium, not semibold. At 13pt semibold on a filled
        /// control the label reads as shouting next to the row it belongs to.
        static let button = Font.system(size: 14, weight: .medium)

        /// Figures that change while the user watches them — words per minute,
        /// download percentage, decode time. Monospaced digits so the number
        /// stops jittering as it counts.
        static let metric = Font.system(size: 34, weight: .semibold).monospacedDigit()
        static let metricCaption = Font.system(size: 12, weight: .medium)

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
        static let navRow = Font.system(size: 14, weight: .regular)

        /// Selected sidebar row label. Weight is what marks the active row now
        /// that the row itself is quiet.
        static let navRowSelected = Font.system(size: 14, weight: .semibold)

        /// Sidebar row glyph. Slightly larger than its label so the column of
        /// icons remains the primary scanning aid.
        static let navIcon = Font.system(size: 16, weight: .regular)
    }

    /// Motion vocabulary follows Apple's behavior-over-animation approach.
    /// Interactive state changes use critically damped springs so they can be
    /// retargeted without a velocity discontinuity. Reduce Motion removes the
    /// spatial spring; callers keep opacity and color feedback.
    enum Motion {
        static func fast(_ reduceMotion: Bool = false) -> Animation? {
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.28, dampingFraction: 1)
        }

        static func standard(_ reduceMotion: Bool = false) -> Animation? {
            reduceMotion
                ? .easeOut(duration: 0.16)
                : .spring(response: 0.35, dampingFraction: 1)
        }

        /// The waveform carries physical momentum, so a small amount of
        /// overshoot is appropriate here and nowhere else.
        static func waveform(_ reduceMotion: Bool = false) -> Animation? {
            reduceMotion
                ? .easeOut(duration: 0.16)
                : .spring(response: 0.4, dampingFraction: 0.8)
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
