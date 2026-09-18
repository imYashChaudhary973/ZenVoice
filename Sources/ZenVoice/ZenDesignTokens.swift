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

/// ZenVoice design tokens — "dark glass settings panel".
///
/// The window shell is the only translucent surface: real background blur
/// under a fixed dark tint so wallpaper bleeds through faintly. Every card,
/// chip, and control on top is solid. Color is confined to nav icon tiles,
/// the single pink accent, and HUD previews; everything else is layered
/// charcoal gray.
enum ZenDesign {
    /// Solid surfaces layered on the glass.
    enum Primitive {
        static let base = Color(red: 0x15 / 255.0, green: 0x19 / 255.0, blue: 0x20 / 255.0) // #151920
        static let base900 = Color(red: 0x0A / 255.0, green: 0x0A / 255.0, blue: 0x0C / 255.0) // #0A0A0C HUD-only black
        static let base800 = Color(red: 0x1E / 255.0, green: 0x21 / 255.0, blue: 0x28 / 255.0) // #1E2128

        static let surface = Color(red: 0x27 / 255.0, green: 0x2A / 255.0, blue: 0x31 / 255.0) // #272A31 card
        static let surfaceRaised = Color(red: 0x37 / 255.0, green: 0x3C / 255.0, blue: 0x43 / 255.0) // #373C43 selected row
        static let surfaceSunken = Color(red: 0x1E / 255.0, green: 0x21 / 255.0, blue: 0x28 / 255.0) // #1E2128

        static let accent = Color(red: 0xD4 / 255.0, green: 0x52 / 255.0, blue: 0x8C / 255.0) // #D4528C core pink
        static let accentFill = Color(red: 0xD4 / 255.0, green: 0x52 / 255.0, blue: 0x8C / 255.0) // #D4528C
        static let accentMuted = Color(red: 0xD4 / 255.0, green: 0x52 / 255.0, blue: 0x8C / 255.0).opacity(0.15)

        static let text = Color.white
        static let muted = Color(red: 0xB4 / 255.0, green: 0xB4 / 255.0, blue: 0xBC / 255.0) // #B4B4BC
        static let subtle = Color(red: 0x94 / 255.0, green: 0x94 / 255.0, blue: 0x9C / 255.0) // #94949C

        static let success = Color(red: 0.204, green: 0.780, blue: 0.471)
        static let warn = Color(red: 0.878, green: 0.647, blue: 0.173)
        static let danger = Color(red: 0.937, green: 0.294, blue: 0.294)

        static let white = Color.white
        static let black = Color.black
    }

    enum Semantic {
        /// Opaque page base for windows that cannot be glass (approval
        /// dialog, exported share card). The settings window does not use it:
        /// its shell is `ZenWindowGlass`.
        static let canvas = Primitive.base800
        /// Sidebar tint over the glass — slightly lighter than the content
        /// pane per the reference.
        static let sidebar = Color(red: 0x32 / 255.0, green: 0x36 / 255.0, blue: 0x3E / 255.0) // #32363E
        static let surface = Primitive.surface
        static let surfaceRaised = Primitive.surfaceRaised
        static let surfaceSunken = Primitive.surfaceSunken
        static let border = Color.white.opacity(0.05)
        static let borderStrong = Color.white.opacity(0.12)
        static let textPrimary = Color.white
        static let textSecondary = Color(red: 0xB4 / 255.0, green: 0xB4 / 255.0, blue: 0xBC / 255.0) // #B4B4BC

        /// The quietest text that still has to be read: placeholders, units,
        /// sidebar section headers.
        static let textTertiary = Color(red: 0x94 / 255.0, green: 0x94 / 255.0, blue: 0x9C / 255.0) // #94949C

        /// Foreground weight of the accent: icons, links, thin glow elements.
        static let accent = Color(red: 0xE4 / 255.0, green: 0x71 / 255.0, blue: 0xA0 / 255.0) // #E471A0

        /// Background weight of the accent for prominent controls.
        static let accentFill = Color(red: 0xD4 / 255.0, green: 0x52 / 255.0, blue: 0x8C / 255.0) // #D4528C

        /// Pressed / dim weight of the accent.
        static let accentStrong = Color(red: 0xA8 / 255.0, green: 0x3A / 255.0, blue: 0x6A / 255.0) // #A83A6A
        static let accentMuted = Color(red: 0xD4 / 255.0, green: 0x52 / 255.0, blue: 0x8C / 255.0).opacity(0.15)
        static let success = Primitive.success
        static let successMuted = Color(red: 0.247, green: 0.796, blue: 0.533).opacity(0.14)
        static let danger = Primitive.danger
        static let dangerMuted = Color(red: 0.937, green: 0.420, blue: 0.420).opacity(0.14)
        static let warn = Primitive.warn
        static let warnMuted = Color(red: 0.890, green: 0.702, blue: 0.255).opacity(0.14)

        /// Text drawn on top of `accentFill`.
        static let textOnAccent = Color.white

        /// Text drawn on top of a `danger`-filled control.
        static let textOnDanger = Color.white
    }

    enum Component {
        static let cardBackground = Primitive.surface
        static let cardBorder = Semantic.border

        /// Selected sidebar row: solid fill, not a tinted wash.
        static let selectedNavigation = Primitive.surfaceRaised
        static let selectedNavigationLabel = Color.white
        static let selectedNavigationIcon = Semantic.accent
        /// Chip / small-button fill.
        static let shortcutBackground = Color(red: 0x3A / 255.0, green: 0x3E / 255.0, blue: 0x44 / 255.0) // #3A3E44
        /// Selection ring weight of the accent.
        static let focusRing = Color(red: 0xD2 / 255.0, green: 0x57 / 255.0, blue: 0x9E / 255.0) // #D2579E
    }

    /// The translucent shell. Blur is `NSVisualEffectView` under the window;
    /// these are the fixed tints composited over it.
    enum Glass {
        /// Dark tint over the behind-window blur: composites ≈#151920 over a
        /// dark wallpaper, ≈#25303F over light-blue.
        static let windowTint = Color(red: 12 / 255.0, green: 14 / 255.0, blue: 20 / 255.0).opacity(0.55)
        /// Near-black glass for the floating HUD pill — the one pure-black
        /// surface in the system.
        static let hudTint = Color(red: 4 / 255.0, green: 4 / 255.0, blue: 6 / 255.0).opacity(0.85)
        /// Mandatory 1px top inner highlight on every elevated surface.
        static let topHighlight = Color.white.opacity(0.10)
        /// Chip-weight top inner highlight.
        static let chipTopHighlight = Color.white.opacity(0.08)
        static let hairline = Color.white.opacity(0.06)
        /// Large ambient-only card shadow: 0 8px 32px rgba(0,0,0,0.40).
        static func cardShadow() -> some ShapeStyle { Color.black.opacity(0.40) }
        static let glow = Color(red: 0xD4 / 255.0, green: 0x52 / 255.0, blue: 0x8C / 255.0).opacity(0.35)
    }

    /// Colorismorphism: the canvas is desaturated; the only saturated
    /// surfaces are these nav tiles, the pink accent, and HUD previews.
    /// Vertical two-stop gradients, light top → deep bottom.
    enum Gradient {
        static let violet = LinearGradient(
            colors: [Color(red: 0x98 / 255.0, green: 0x84 / 255.0, blue: 0xEF / 255.0),
                     Color(red: 0x84 / 255.0, green: 0x68 / 255.0, blue: 0xE6 / 255.0)],
            startPoint: .top, endPoint: .bottom
        )
        static let indigo = LinearGradient(
            colors: [Color(red: 0x90 / 255.0, green: 0x8D / 255.0, blue: 0xD7 / 255.0),
                     Color(red: 0x77 / 255.0, green: 0x6E / 255.0, blue: 0xCC / 255.0)],
            startPoint: .top, endPoint: .bottom
        )
        static let pink = LinearGradient(
            colors: [Color(red: 0xD6 / 255.0, green: 0x71 / 255.0, blue: 0xA3 / 255.0),
                     Color(red: 0xCF / 255.0, green: 0x4B / 255.0, blue: 0x83 / 255.0)],
            startPoint: .top, endPoint: .bottom
        )
        static let orchid = LinearGradient(
            colors: [Color(red: 0xC8 / 255.0, green: 0x6D / 255.0, blue: 0xE0 / 255.0),
                     Color(red: 0xB4 / 255.0, green: 0x42 / 255.0, blue: 0xD3 / 255.0)],
            startPoint: .top, endPoint: .bottom
        )
        static let rose = LinearGradient(
            colors: [Color(red: 0xE2 / 255.0, green: 0x6A / 255.0, blue: 0x77 / 255.0),
                     Color(red: 0xD1 / 255.0, green: 0x44 / 255.0, blue: 0x52 / 255.0)],
            startPoint: .top, endPoint: .bottom
        )
        static let coral = LinearGradient(
            colors: [Color(red: 0xE9 / 255.0, green: 0x7F / 255.0, blue: 0x5E / 255.0),
                     Color(red: 0xD9 / 255.0, green: 0x5C / 255.0, blue: 0x34 / 255.0)],
            startPoint: .top, endPoint: .bottom
        )
        static let orange = LinearGradient(
            colors: [Color(red: 0xE7 / 255.0, green: 0x88 / 255.0, blue: 0x48 / 255.0),
                     Color(red: 0xE4 / 255.0, green: 0x6A / 255.0, blue: 0x2C / 255.0)],
            startPoint: .top, endPoint: .bottom
        )
        static let amber = LinearGradient(
            colors: [Color(red: 0xEA / 255.0, green: 0xA9 / 255.0, blue: 0x4D / 255.0),
                     Color(red: 0xD8 / 255.0, green: 0x86 / 255.0, blue: 0x32 / 255.0)],
            startPoint: .top, endPoint: .bottom
        )
        static let gold = LinearGradient(
            colors: [Color(red: 0xE6 / 255.0, green: 0xC0 / 255.0, blue: 0x49 / 255.0),
                     Color(red: 0xC9 / 255.0, green: 0x9A / 255.0, blue: 0x33 / 255.0)],
            startPoint: .top, endPoint: .bottom
        )

        /// HUD / live preview thumbnails: dark teal → deep indigo → dark
        /// magenta, drawn diagonally.
        static let hudPreview = LinearGradient(
            colors: [Color(red: 0x1A / 255.0, green: 0x2E / 255.0, blue: 0x2E / 255.0),
                     Color(red: 0x1E / 255.0, green: 0x19 / 255.0, blue: 0x3B / 255.0),
                     Color(red: 0x32 / 255.0, green: 0x1A / 255.0, blue: 0x32 / 255.0)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
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
        static let sidebarWidth: CGFloat = 280

        /// Measure for running prose — a page subtitle, a paragraph of
        /// explanation. Cards themselves are not capped: they fill the window,
        /// so full screen looks deliberate rather than centred in a column.
        static let proseColumn: CGFloat = 680

        /// Height of the transparent title bar. Tall enough to clear the
        /// traffic lights, which the window draws over the glass.
        static let titleBar: CGFloat = 48

        /// Minimum hit target for anything clickable.
        static let hitTarget: CGFloat = 44

        /// Painted size of a nav gradient tile and row icon chips.
        static let rowIcon: CGFloat = 30

        /// Painted size of a card or page heading chip. Tall enough to sit
        /// beside the title and one-line subtitle together.
        static let headingIcon: CGFloat = 42

        /// Height for compact controls that sit inside a row which already
        /// meets `hitTarget`, such as paired buttons on a single line.
        static let control: CGFloat = 32

        /// Painted height of a keyboard key chip. Glyph keys (⌘, P) and word
        /// keys (Space, Fn) share this so labels sit on one baseline.
        static let keycap: CGFloat = 20

        /// Painted height of a navigation row. It also meets the pointer and
        /// accessibility hit target without needing invisible overflow.
        static let navRow: CGFloat = 44

        /// Icon slot in a navigation row. The glyph is drawn at
        /// `Typography.navIcon`; the slot keeps every label on one baseline
        /// regardless of how wide its symbol is.
        static let navIcon: CGFloat = 24

        /// Painted height of a settings row. The airy reference rhythm:
        /// rows are ~45% taller than the hit-target floor.
        static let row: CGFloat = 64

        /// Vertical gap between cards in a screen's content stack.
        static let contentGap: CGFloat = 16
    }

    /// Type is one family in several weights — the system face, plus the
    /// system monospace for anything the user could retype: shortcuts, model
    /// identifiers, error rates, licence keys.
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
        /// below that is the least legible type an app can ship.
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
        static let navIcon = Font.system(size: 15, weight: .medium)
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

    /// Corner radii. Window 12, cards/preview thumbs 14/12, chips & icon
    /// tiles 8, pills fully rounded.
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 8
        static let large: CGFloat = 14
        static let bar: CGFloat = 10
        static let window: CGFloat = 12
        static let barControl: CGFloat = 8

        /// Fully rounded — the toolbar cluster and status pills.
        static let pill: CGFloat = 999
    }
}
