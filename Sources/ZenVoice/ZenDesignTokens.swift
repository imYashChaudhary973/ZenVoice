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

/// ZenVoice v3 design tokens — "Ink & Brass", dark only.
///
/// The brand mark (`Resources/Brand/ZenLogo.png`) is antique-brass concentric
/// voice ripples on a warm ink background. The v2 graphite-and-green system
/// was an invented UI skin; v3 returns to the mark itself.
///
/// Three rules hold the theme together.
///
/// **The canvas is ink.** Warm near-black, taken from the logo's own
/// background. Never pure black (it kills card edges), never cool blue-grey
/// (the default "tool dark" monoculture), and never graphite (v2).
///
/// **Brass carries the brand.** Selection, primary actions, focus, and
/// navigation affordances use the mark's metal. Accent text, icons, hairlines
/// and meters drawn on a dark surface use the light foreground weight
/// (`accent`). Buttons and selected fills use the deep background weight
/// (`accentFill`) so the ink-black label clears 4.5:1.
///
/// **Green is the voice.** Green appears only when the microphone is live,
/// audio is being processed, or a transcript is being produced. If it is
/// green, it is listening.
///
/// **Structure comes from hairlines, not shadows.** Nothing in the window casts
/// a shadow. Edges are 1px borders and a step in surface value.
enum ZenDesign {
    enum Primitive {
        // Ink ramp — warm near-black, never pure black, never grey.
        static let ink = Color(nsColor: NSColor(red: 0.071, green: 0.063, blue: 0.047, alpha: 1))
        static let ink950 = Color(nsColor: NSColor(red: 0.086, green: 0.076, blue: 0.055, alpha: 1))
        static let ink900 = Color(nsColor: NSColor(red: 0.102, green: 0.090, blue: 0.071, alpha: 1))
        static let ink800 = Color(nsColor: NSColor(red: 0.129, green: 0.114, blue: 0.090, alpha: 1))

        // Surfaces float above the canvas by value alone.
        static let surface = Color(nsColor: NSColor(red: 0.102, green: 0.090, blue: 0.071, alpha: 1))       // #1A1712
        static let surfaceRaised = Color(nsColor: NSColor(red: 0.133, green: 0.118, blue: 0.090, alpha: 1))   // #221E17
        static let surfaceSunken = Color(nsColor: NSColor(red: 0.086, green: 0.076, blue: 0.055, alpha: 1))   // #161310

        // Brass — the mark's metal. Two weights so neither text nor label fails contrast.
        static let brass = Color(nsColor: NSColor(red: 0.788, green: 0.663, blue: 0.455, alpha: 1))           // #C9A874
        static let brassFill = Color(nsColor: NSColor(red: 0.663, green: 0.541, blue: 0.361, alpha: 1))       // #A98A5C
        static let brassHover = Color(nsColor: NSColor(red: 0.706, green: 0.584, blue: 0.416, alpha: 1))      // #B4956A
        static let brassPressed = Color(nsColor: NSColor(red: 0.612, green: 0.494, blue: 0.322, alpha: 1))    // #9C7E52
        static let brassMuted = Color(nsColor: NSColor(red: 0.788, green: 0.663, blue: 0.455, alpha: 0.14))

        // Ink label that sits on brass fills.
        static let inkOnBrass = Color(nsColor: NSColor(red: 0.078, green: 0.067, blue: 0.035, alpha: 1))       // #141109

        // Voice / live — the only green in the product.
        static let live = Color(nsColor: NSColor(red: 0.290, green: 0.871, blue: 0.549, alpha: 1))             // #4ADE8C
        static let liveFill = Color(nsColor: NSColor(red: 0.180, green: 0.420, blue: 0.278, alpha: 1))        // #2E6B47
        static let liveMuted = Color(nsColor: NSColor(red: 0.290, green: 0.871, blue: 0.549, alpha: 0.14))

        // Text — warm paper ramp.
        static let text = Color(nsColor: NSColor(red: 0.929, green: 0.906, blue: 0.863, alpha: 1))             // #EDE7DC
        static let muted = Color(nsColor: NSColor(red: 0.659, green: 0.627, blue: 0.576, alpha: 1))           // #A8A093
        static let subtle = Color(nsColor: NSColor(red: 0.580, green: 0.529, blue: 0.490, alpha: 1))           // #948C7D

        // Functional colours. Amber and red are separated from brass by saturation.
        static let success = Color(nsColor: NSColor(red: 0.290, green: 0.871, blue: 0.549, alpha: 1))           // same as live
        static let warn = Color(nsColor: NSColor(red: 0.941, green: 0.694, blue: 0.243, alpha: 1))             // #F0B13E
        static let danger = Color(nsColor: NSColor(red: 0.949, green: 0.439, blue: 0.439, alpha: 1))            // #F27070

        static let white = Color.white
        static let black = Color.black
    }

    enum Semantic {
        static let canvas = Primitive.ink

        /// Tint painted *over* the sidebar's vibrancy material.
        ///
        /// Low alpha on purpose: the material carries most of the value, and
        /// this only settles it enough that navigation text stays readable
        /// against a bright wallpaper.
        static let sidebar = Color(
            nsColor: NSColor(red: 0.055, green: 0.047, blue: 0.035, alpha: 0.62)
        )
        static let surface = Primitive.surface
        static let surfaceRaised = Primitive.surfaceRaised
        static let surfaceSunken = Primitive.surfaceSunken
        static let border = Color(nsColor: NSColor(white: 1.0, alpha: 0.085))
        static let borderStrong = Color(nsColor: NSColor(white: 1.0, alpha: 0.16))
        static let textPrimary = Primitive.text
        static let textSecondary = Primitive.muted
        static let textTertiary = Primitive.subtle

        /// Foreground weight of the brand accent: accent text, icons, meters.
        static let accent = Primitive.brass

        /// Background weight of the brand accent: primary buttons.
        static let accentFill = Primitive.brassFill

        /// Hover and pressed states for a filled accent control.
        ///
        /// `accentHover` is the mouse-over state; `accentStrong` is the
        /// pressed/active state. Both move *away* from the ink label they carry,
        /// never toward it.
        static let accentHover = Primitive.brassHover
        static let accentStrong = Primitive.brassPressed
        static let accentMuted = Primitive.brassMuted

        /// Live / voice accent. The only green in the product.
        static let live = Primitive.live
        static let liveFill = Primitive.liveFill
        static let liveMuted = Primitive.liveMuted

        static let success = Primitive.success
        static let successMuted = Primitive.liveMuted
        static let danger = Primitive.danger
        static let dangerMuted = Color(
            nsColor: NSColor(red: 0.949, green: 0.439, blue: 0.439, alpha: 0.14)
        )
        static let warn = Primitive.warn
        static let warnMuted = Color(
            nsColor: NSColor(red: 0.941, green: 0.694, blue: 0.243, alpha: 0.14)
        )

        /// Text drawn on top of `accentFill`.
        ///
        /// Ink black, which is only possible because `accentFill` is the deep
        /// brass weight. It clears 4.5:1 on brass fill across all states.
        static let textOnAccent = Primitive.inkOnBrass

        /// Text drawn on top of a `danger`-filled control.
        static let textOnDanger = Primitive.white

        /// Text drawn on top of `liveFill`.
        static let textOnLive = Primitive.white
    }

    enum Component {
        static let cardBackground = Semantic.surface
        static let cardBorder = Semantic.border

        /// Selected navigation: a quiet raised row, brass icon, primary label.
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
    /// identifiers, error rates, licence keys. Page titles and dictated text
    /// use New York serif because "your words become print" is the product's
    /// entire point.
    ///
    /// Pairing two sans faces on a contrast axis this small only makes the
    /// window look uncertain.
    enum Typography {
        static let display = Font.system(size: 30, weight: .semibold)
        static let displaySerif = Font.system(size: 30, weight: .semibold, design: .serif)
        static let pageTitle = Font.system(size: 21, weight: .semibold)
        static let pageTitleSerif = Font.system(size: 21, weight: .semibold, design: .serif)
        static let pageContext = Font.system(size: 12, weight: .medium)
        static let sectionTitle = Font.system(size: 11, weight: .semibold)
        static let body = Font.system(size: 13)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let bodySerif = Font.system(size: 13, design: .serif)
        static let caption = Font.system(size: 11.5)
        static let captionStrong = Font.system(size: 11.5, weight: .semibold)
        static let transcript = Font.system(size: 14, design: .serif)
        static let transcriptLarge = Font.system(size: 17, design: .serif)

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

// MARK: - Semantic helpers

extension ZenDesign {
    /// A token that resolves to a different color depending on the current
    /// macOS appearance. Retained for call sites that still need it, but the
    /// v3 redesign forces dark everywhere and does not ship a light token set.
    enum Legacy {
        static func darkOnly(_ dark: NSColor) -> Color {
            Color(nsColor: dark)
        }
    }
}
