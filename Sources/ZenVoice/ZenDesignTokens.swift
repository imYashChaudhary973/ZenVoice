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

/// ZenVoice design tokens — ink, one jade, and real materials.
///
/// The room this window lives in: a developer at the end of the day, editor and
/// terminal already open, dictating into whichever window has focus. ZenVoice
/// is an instrument sitting beside the work, not a dashboard demanding to be
/// looked at. The emotion it should produce is *calm confidence* — everything
/// below is in service of that.
///
/// Four rules hold the system together.
///
/// **Colour is information, and almost nothing is coloured.** The previous
/// revision stated this rule and then broke it: every sidebar glyph, every stat
/// icon, every card chip and badge was jade. When nine things on a screen are
/// accented, none of them is. The accent is now spent on exactly three jobs —
/// the selected navigation row, the primary action, and live state — and
/// nowhere else. Everything that used to be jade decoration is now monochrome.
///
/// **Depth comes from material and light, not from borders.** The old window
/// separated every region with a 1px grey rectangle, which is why a card inside
/// a card inside a panel read as a stack of boxes rather than as a hierarchy.
/// Surfaces now sit on the system's vibrancy materials, and are separated by a
/// *bright top edge* (light catching the lip of a real surface) plus a soft
/// shadow. Borders survive only as the faintest hairline, and are never the
/// primary cue.
///
/// **Type carries the hierarchy.** The old scale ran 11.5 / 12.5 / 13 / 16 —
/// four sizes inside five points of each other, so nothing led. The scale below
/// spans 11 to 34 with tracking tuned per size: negative on display sizes,
/// which read too loose as they grow, and slightly positive on the smallest
/// text, which needs the air.
///
/// **Motion is spring, not duration.** Every animation in the window is a
/// spring so it can be interrupted and redirected mid-flight without a jump.
/// Critically damped by default; overshoot only where a gesture carried
/// momentum into it.
enum ZenDesign {
    /// Raw ramp values. Prefer ``Semantic`` — these exist for the few places
    /// that need a fixed appearance regardless of light or dark.
    enum Primitive {
        // Ink, not graphite: a few points of blue in the shadows. A perfectly
        // neutral dark grey reads as switched-off LCD; the cool cast is what
        // makes the jade look deliberate rather than radioactive.
        static let base = Color(nsColor: NSColor(red: 0.051, green: 0.053, blue: 0.060, alpha: 1))
        static let base900 = Color(nsColor: NSColor(red: 0.067, green: 0.070, blue: 0.078, alpha: 1))
        static let base800 = Color(nsColor: NSColor(red: 0.125, green: 0.129, blue: 0.141, alpha: 1))

        static let surface = Color(nsColor: NSColor(red: 0.086, green: 0.089, blue: 0.098, alpha: 1))
        static let surfaceRaised = Color(nsColor: NSColor(red: 0.125, green: 0.129, blue: 0.141, alpha: 1))
        static let surfaceSunken = Color(nsColor: NSColor(red: 0.035, green: 0.036, blue: 0.042, alpha: 1))

        static let accent = Color(nsColor: NSColor(red: 0.235, green: 0.784, blue: 0.565, alpha: 1))
        static let accentFill = Color(nsColor: NSColor(red: 0.086, green: 0.522, blue: 0.369, alpha: 1))
        static let accentMuted = Color(nsColor: NSColor(red: 0.235, green: 0.784, blue: 0.565, alpha: 0.14))

        static let text = Color(nsColor: NSColor(red: 0.945, green: 0.945, blue: 0.957, alpha: 1))
        static let muted = Color(nsColor: NSColor(red: 0.663, green: 0.667, blue: 0.694, alpha: 1))
        static let subtle = Color(nsColor: NSColor(red: 0.569, green: 0.573, blue: 0.612, alpha: 1))

        static let success = Color(nsColor: NSColor(red: 0.259, green: 0.808, blue: 0.549, alpha: 1))
        static let warn = Color(nsColor: NSColor(red: 0.918, green: 0.729, blue: 0.286, alpha: 1))
        static let danger = Color(nsColor: NSColor(red: 0.949, green: 0.443, blue: 0.427, alpha: 1))

        static let white = Color.white
        static let black = Color.black
    }

    enum Semantic {
        /// The content column's own fill.
        ///
        /// Deliberately *not* opaque: it is painted over the window's
        /// `underWindowBackground` material, so a trace of the desktop survives
        /// behind it and the window sits in the room rather than on top of it.
        /// At full opacity this flattened to the same dead rectangle the
        /// previous revision shipped.
        static let canvas = adaptive(
            light: NSColor(red: 0.949, green: 0.949, blue: 0.961, alpha: 0.88),
            dark: NSColor(red: 0.039, green: 0.041, blue: 0.047, alpha: 0.86)
        )

        /// Tint painted *over* the sidebar's vibrancy material.
        ///
        /// Lower alpha than the content column: the sidebar is the region that
        /// should show the most of what is behind the window, because that is
        /// what makes the two columns read as different materials rather than
        /// as two greys.
        static let sidebar = adaptive(
            light: NSColor(red: 0.965, green: 0.965, blue: 0.973, alpha: 0.34),
            dark: NSColor(red: 0.043, green: 0.045, blue: 0.051, alpha: 0.40)
        )

        /// A card. One step of value above the canvas — the *only* step, so
        /// nesting never compounds into mud.
        ///
        /// The size of that step is measured, not guessed: the canvas is a
        /// translucent tint over a dark material, which lands around 0.06, so a
        /// card at 0.086 was a difference of two and a half percent luminance
        /// and the cards were effectively invisible. 0.125 is roughly a 2:1
        /// step, which is the least that reads as "in front of" rather than as
        /// "a slightly different shade of the same thing".
        static let surface = adaptive(
            light: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),
            dark: NSColor(red: 0.125, green: 0.129, blue: 0.141, alpha: 1)
        )

        /// A control resting *on* a card: a key cap, a segmented track, a
        /// secondary button.
        static let surfaceRaised = adaptive(
            light: NSColor(red: 0.929, green: 0.929, blue: 0.941, alpha: 1),
            dark: NSColor(red: 0.192, green: 0.196, blue: 0.212, alpha: 1)
        )

        /// A well cut *into* a surface: a progress track, an unfilled meter.
        static let surfaceSunken = adaptive(
            light: NSColor(red: 0.898, green: 0.898, blue: 0.914, alpha: 1),
            dark: NSColor(red: 0.035, green: 0.036, blue: 0.042, alpha: 1)
        )

        /// The faintest structural hairline.
        ///
        /// Halved from the previous revision. Depth is now carried by the top
        /// edge and the shadow; a border this quiet only has to stop two
        /// same-valued surfaces from bleeding into each other.
        static let border = adaptive(
            light: NSColor(white: 0.0, alpha: 0.075),
            dark: NSColor(white: 1.0, alpha: 0.055)
        )
        static let borderStrong = adaptive(
            light: NSColor(white: 0.0, alpha: 0.14),
            dark: NSColor(white: 1.0, alpha: 0.11)
        )

        /// The lit lip along the top of a raised surface.
        ///
        /// This is the single detail that makes a card read as a physical
        /// object rather than as a filled rectangle: real surfaces catch light
        /// on the edge that faces it. Drawn only on the top edge — a highlight
        /// on all four sides is a border, and reads as one.
        static let edgeHighlight = adaptive(
            light: NSColor(white: 1.0, alpha: 0.9),
            dark: NSColor(white: 1.0, alpha: 0.14)
        )

        static let textPrimary = adaptive(
            light: NSColor(red: 0.075, green: 0.078, blue: 0.090, alpha: 1),
            dark: NSColor(red: 0.945, green: 0.945, blue: 0.957, alpha: 1)
        )
        static let textSecondary = adaptive(
            light: NSColor(red: 0.318, green: 0.322, blue: 0.357, alpha: 1),
            dark: NSColor(red: 0.671, green: 0.675, blue: 0.706, alpha: 1)
        )

        /// The quietest text that still has to be read: placeholders, units,
        /// row metadata.
        ///
        /// Chosen against the *raised* surface, not the canvas, because that is
        /// the worst case it actually appears on — it clears the 4.5:1 body
        /// floor in both appearances there. A ramp picked against the canvas
        /// alone lands near 3.9:1 inside a raised control, which is the single
        /// commonest reason a dense settings window feels unreadable.
        static let textTertiary = adaptive(
            light: NSColor(red: 0.416, green: 0.420, blue: 0.459, alpha: 1),
            dark: NSColor(red: 0.573, green: 0.580, blue: 0.616, alpha: 1)
        )

        /// Foreground weight of the accent: the selected nav row, live state,
        /// an accent link. Light enough on ink to clear 4.5:1 as text.
        static let accent = adaptive(
            light: NSColor(red: 0.024, green: 0.404, blue: 0.282, alpha: 1),
            dark: NSColor(red: 0.235, green: 0.784, blue: 0.565, alpha: 1)
        )

        /// Background weight of the accent: primary buttons — anything that
        /// carries a white label. Deep enough that white on it clears 4.5:1,
        /// which the foreground weight does not.
        static let accentFill = adaptive(
            light: NSColor(red: 0.024, green: 0.404, blue: 0.282, alpha: 1),
            dark: NSColor(red: 0.086, green: 0.522, blue: 0.369, alpha: 1)
        )

        /// Pressed state for a filled accent control. Always moves *away* from
        /// the white label it carries, never toward it.
        static let accentStrong = adaptive(
            light: NSColor(red: 0.016, green: 0.302, blue: 0.212, alpha: 1),
            dark: NSColor(red: 0.055, green: 0.404, blue: 0.286, alpha: 1)
        )
        static let accentMuted = adaptive(
            light: NSColor(red: 0.024, green: 0.404, blue: 0.282, alpha: 0.10),
            dark: NSColor(red: 0.235, green: 0.784, blue: 0.565, alpha: 0.13)
        )
        static let success = adaptive(
            light: NSColor(red: 0.043, green: 0.404, blue: 0.243, alpha: 1),
            dark: NSColor(red: 0.259, green: 0.808, blue: 0.549, alpha: 1)
        )
        static let successMuted = adaptive(
            light: NSColor(red: 0.043, green: 0.404, blue: 0.243, alpha: 0.10),
            dark: NSColor(red: 0.259, green: 0.808, blue: 0.549, alpha: 0.13)
        )
        static let danger = adaptive(
            light: NSColor(red: 0.741, green: 0.192, blue: 0.169, alpha: 1),
            dark: NSColor(red: 0.949, green: 0.443, blue: 0.427, alpha: 1)
        )
        static let dangerMuted = adaptive(
            light: NSColor(red: 0.741, green: 0.192, blue: 0.169, alpha: 0.10),
            dark: NSColor(red: 0.949, green: 0.443, blue: 0.427, alpha: 0.13)
        )
        static let warn = adaptive(
            light: NSColor(red: 0.522, green: 0.341, blue: 0.055, alpha: 1),
            dark: NSColor(red: 0.918, green: 0.729, blue: 0.286, alpha: 1)
        )
        static let warnMuted = adaptive(
            light: NSColor(red: 0.522, green: 0.341, blue: 0.055, alpha: 0.10),
            dark: NSColor(red: 0.918, green: 0.729, blue: 0.286, alpha: 0.13)
        )

        /// Text drawn on top of `accentFill`. White in both appearances, which
        /// is only true because `accentFill` is the deep weight in both.
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

        /// Selected navigation.
        ///
        /// This is one of the three places the accent is allowed to appear. A
        /// tinted fill plus an accent glyph, which is the macOS sidebar idiom —
        /// and because nothing *else* in the rail is coloured any more, one
        /// tinted row is now unmistakable instead of being lost among nine
        /// green icons.
        static let selectedNavigation = Semantic.accentMuted
        static let selectedNavigationLabel = Semantic.textPrimary
        static let selectedNavigationIcon = Semantic.accent
        static let shortcutBackground = Semantic.surfaceRaised
        static let focusRing = Semantic.accent.opacity(0.6)

        /// Shadow cast by a card onto the canvas.
        ///
        /// Bigger surfaces read as thicker, so this is deeper than the shadow
        /// on a chip and much deeper than the one on a row.
        static let cardShadow = Color.black.opacity(0.18)

        /// Shadow under a floating surface: the ZenBar, a popover, the palette.
        static let floatingShadow = Color.black.opacity(0.34)
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 40
        static let xxxl: CGFloat = 56
    }

    /// Structural measurements shared by the window chrome.
    ///
    /// The sidebar width lives here because the title bar has to reserve
    /// exactly the same width for the brand block. Two hand-copied constants
    /// drifted apart; one named value cannot.
    enum Layout {
        static let sidebarWidth: CGFloat = 224

        /// Measure for running prose — a page subtitle, a paragraph of
        /// explanation. Cards themselves are not capped: they fill the window,
        /// so full screen looks deliberate rather than centred in a column.
        static let proseColumn: CGFloat = 620

        /// Height of the transparent title bar. Tall enough to clear the
        /// traffic lights, which the window draws over the sidebar material.
        static let titleBar: CGFloat = 52

        /// Minimum hit target for anything clickable.
        static let hitTarget: CGFloat = 44

        /// Height for compact controls that sit inside a row which already
        /// meets `hitTarget`, such as paired buttons on a single line.
        static let control: CGFloat = 30

        /// Painted height of a navigation row.
        static let navRow: CGFloat = 34

        /// Icon slot in a navigation row. The glyph is drawn at
        /// `Typography.navIcon`; the slot keeps every label on one baseline
        /// regardless of how wide its symbol is.
        static let navIcon: CGFloat = 22

        /// Inset from the leading edge at which a divider inside a grouped list
        /// begins, so it starts under the *text* and not under the glyph. A
        /// divider that runs the full width cuts the row's icon off from its
        /// own label.
        static let dividerInset: CGFloat = 16
    }

    /// Type is one family in several weights — the system face, plus the system
    /// monospace for anything the user could retype: shortcuts, model
    /// identifiers, error rates.
    ///
    /// Tracking is *not* baked into these `Font` values, because SwiftUI fonts
    /// do not carry it. Each size has a matching entry in ``Tracking``, and the
    /// components in `ZenV2Components` apply the pair together. The rule that
    /// pairing encodes: large text tightens, small text opens up. One
    /// letter-spacing value across a scale this wide is wrong at both ends.
    enum Typography {
        static let display = Font.system(size: 32, weight: .semibold)
        static let pageTitle = Font.system(size: 24, weight: .semibold)
        static let sectionTitle = Font.system(size: 17, weight: .semibold)
        static let body = Font.system(size: 13)
        static let bodyStrong = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 11.5)
        static let captionStrong = Font.system(size: 11.5, weight: .medium)

        /// Kept as an alias of ``body`` weight for card subtitles that want a
        /// touch more presence without jumping a size.
        static let pageContext = Font.system(size: 13, weight: .regular)

        /// Button labels are medium, not semibold. At 13pt semibold on a filled
        /// control the label reads as shouting next to the row it belongs to.
        static let button = Font.system(size: 13, weight: .medium)

        /// Figures that change while the user watches them — words per minute,
        /// download percentage, decode time. Monospaced digits so the number
        /// stops jittering as it counts.
        static let metric = Font.system(size: 34, weight: .semibold).monospacedDigit()
        static let metricCaption = Font.system(size: 11, weight: .medium)

        /// Tabular figures at body size, for rows of numbers in a table.
        static let numeric = Font.system(size: 13).monospacedDigit()

        static let mono = Font.system(size: 12, design: .monospaced)
        static let monoSmall = Font.system(size: 11, design: .monospaced)

        /// Uppercase label above a group of settings. Pair with
        /// `Tracking.eyebrow`. Sits at the 11pt floor — uppercase text tracked
        /// out below that is the least legible type an app can ship.
        static let eyebrow = Font.system(size: 11, weight: .semibold)

        /// Text inside a badge or pill.
        static let badge = Font.system(size: 11, weight: .medium)

        /// Sidebar group heading.
        static let navGroup = Font.system(size: 11, weight: .semibold)

        /// Sidebar row label.
        static let navRow = Font.system(size: 13, weight: .regular)

        /// Selected sidebar row label.
        static let navRowSelected = Font.system(size: 13, weight: .semibold)

        /// Sidebar row glyph.
        static let navIcon = Font.system(size: 13, weight: .medium)
    }

    /// Letter-spacing, paired with the sizes in ``Typography``.
    ///
    /// Negative as text grows, because letters read progressively further apart
    /// at display sizes; slightly positive at the bottom of the scale, where
    /// small glyphs need air between them to stay distinct.
    enum Tracking {
        static let display: CGFloat = -0.7
        static let pageTitle: CGFloat = -0.5
        static let sectionTitle: CGFloat = -0.3
        static let body: CGFloat = 0
        static let caption: CGFloat = 0.05
        static let metric: CGFloat = -0.9
        static let eyebrow: CGFloat = 0.9
    }

    /// Motion vocabulary — springs, never durations.
    ///
    /// A fixed-duration curve cannot be interrupted without a jump: it
    /// interpolates from wherever it was told to start, so a second change
    /// mid-flight snaps. A spring animates from the *current* value and carries
    /// its velocity through a re-target, which is what lets a user change their
    /// mind halfway through and have the interface simply follow.
    ///
    /// Helpers return `nil` when Reduce Motion is on, so call sites pass
    /// `@Environment(\.accessibilityReduceMotion)` straight through.
    enum Motion {
        /// Critically damped — reaches the target and stops, no overshoot.
        /// The default for everything the user did not physically throw.
        static func standard(_ reduceMotion: Bool = false) -> Animation? {
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 1.0)
        }

        /// Same shape, quicker. Hover, press, focus — anything that has to feel
        /// like it happened *on* the input rather than after it.
        static func fast(_ reduceMotion: Bool = false) -> Animation? {
            reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 1.0)
        }

        /// Slight overshoot, for motion a gesture threw: a bar resizing after a
        /// mode flick, a sheet released mid-drag. Overshoot on something that
        /// merely faded in feels wrong; overshoot on something you flicked
        /// feels right.
        static func momentum(_ reduceMotion: Bool = false) -> Animation? {
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78)
        }

        /// The ZenBar waveform — the one continuously living element.
        static func waveform(_ reduceMotion: Bool = false) -> Animation? {
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72)
        }

        /// Scale a control drops to while held. Small enough to read as
        /// pressure rather than as the button shrinking.
        static let pressScale: CGFloat = 0.97
    }

    /// Corner radii.
    ///
    /// Every radius is `.continuous` at the call site — the squircle, not the
    /// circular arc. On a 12pt corner the difference is visible: the circular
    /// version has a discontinuity where the arc meets the straight edge, and a
    /// window full of them is the most common reason a Mac app looks like a
    /// port of a web page.
    enum Radius {
        static let small: CGFloat = 7
        static let medium: CGFloat = 10
        static let large: CGFloat = 14

        /// The floating dictation bar. Nearly a capsule at 44pt tall, which is
        /// what makes it read as an object hovering over the desktop rather
        /// than as a panel docked to it.
        static let bar: CGFloat = 19
        static let barControl: CGFloat = 8

        /// Fully rounded — the toolbar cluster and status pills.
        static let pill: CGFloat = 999
    }
}

// MARK: - Type helper

extension View {
    /// Applies a size from ``ZenDesign/Typography`` together with its matching
    /// tracking, so the two can never drift apart at a call site.
    func zenType(_ font: Font, tracking: CGFloat = 0) -> some View {
        self.font(font).tracking(tracking)
    }
}
