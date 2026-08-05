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

/// ZenVoice v4 design tokens — "Graphite", a cooler devtool utility.
/// Native adaptive colors shared across the interface.
enum ZenDesign {
    enum Primitive {
        static let graphite950 = Color(red: 0.051, green: 0.055, blue: 0.059)
        static let graphite900 = Color(red: 0.071, green: 0.075, blue: 0.082)
        static let graphite850 = Color(red: 0.090, green: 0.094, blue: 0.102)
        static let graphite800 = Color(red: 0.122, green: 0.129, blue: 0.137)
        static let graphite700 = Color(red: 0.176, green: 0.184, blue: 0.196)
        static let graphite600 = Color(red: 0.231, green: 0.239, blue: 0.251)
        static let blue400 = Color(red: 0.510, green: 0.675, blue: 0.898)
        static let blue500 = Color(red: 0.361, green: 0.573, blue: 0.878)
        static let blue600 = Color(red: 0.243, green: 0.475, blue: 0.800)
        static let green400 = Color(red: 0.478, green: 0.737, blue: 0.557)
        static let red400 = Color(red: 0.898, green: 0.510, blue: 0.510)
        static let white = Color.white
    }

    enum Semantic {
        static let canvas = adaptive(
            light: NSColor(red: 0.973, green: 0.973, blue: 0.976, alpha: 1),
            dark: NSColor(red: 0.051, green: 0.055, blue: 0.059, alpha: 1)
        )
        static let sidebar = adaptive(
            light: NSColor(red: 0.957, green: 0.957, blue: 0.961, alpha: 1),
            dark: NSColor(red: 0.039, green: 0.043, blue: 0.047, alpha: 1)
        )
        static let surface = adaptive(
            light: NSColor(red: 0.984, green: 0.984, blue: 0.988, alpha: 1),
            dark: NSColor(red: 0.078, green: 0.082, blue: 0.090, alpha: 1)
        )
        static let surfaceRaised = adaptive(
            light: NSColor(red: 0.933, green: 0.937, blue: 0.945, alpha: 1),
            dark: NSColor(red: 0.114, green: 0.118, blue: 0.125, alpha: 1)
        )
        static let surfaceSunken = adaptive(
            light: NSColor(red: 0.898, green: 0.902, blue: 0.910, alpha: 1),
            dark: NSColor(red: 0.137, green: 0.141, blue: 0.149, alpha: 1)
        )
        static let border = adaptive(
            light: NSColor(white: 0.02, alpha: 0.08),
            dark: NSColor(white: 1.0, alpha: 0.08)
        )
        static let borderStrong = adaptive(
            light: NSColor(white: 0.02, alpha: 0.14),
            dark: NSColor(white: 1.0, alpha: 0.14)
        )
        static let textPrimary = adaptive(
            light: NSColor(red: 0.071, green: 0.078, blue: 0.086, alpha: 1),
            dark: NSColor(red: 0.937, green: 0.941, blue: 0.949, alpha: 1)
        )
        static let textSecondary = adaptive(
            light: NSColor(red: 0.349, green: 0.361, blue: 0.384, alpha: 1),
            dark: NSColor(red: 0.678, green: 0.686, blue: 0.706, alpha: 1)
        )
        static let textTertiary = adaptive(
            light: NSColor(red: 0.459, green: 0.471, blue: 0.498, alpha: 1),
            dark: NSColor(red: 0.529, green: 0.541, blue: 0.565, alpha: 1)
        )
        /// Single accent: a calm electric blue. Reserved for primary action and
        /// the live recording state, mirroring the reference's action chips.
        static let accent = adaptive(
            light: NSColor(red: 0.243, green: 0.475, blue: 0.800, alpha: 1),
            dark: NSColor(red: 0.510, green: 0.675, blue: 0.898, alpha: 1)
        )
        static let accentStrong = adaptive(
            light: NSColor(red: 0.188, green: 0.408, blue: 0.729, alpha: 1),
            dark: NSColor(red: 0.612, green: 0.729, blue: 0.929, alpha: 1)
        )
        static let accentMuted = adaptive(
            light: NSColor(red: 0.243, green: 0.475, blue: 0.800, alpha: 0.10),
            dark: NSColor(red: 0.510, green: 0.675, blue: 0.898, alpha: 0.16)
        )
        static let success = adaptive(
            light: NSColor(red: 0.200, green: 0.510, blue: 0.290, alpha: 1),
            dark: NSColor(red: 0.478, green: 0.737, blue: 0.557, alpha: 1)
        )
        static let successMuted = adaptive(
            light: NSColor(red: 0.200, green: 0.510, blue: 0.290, alpha: 0.10),
            dark: NSColor(red: 0.478, green: 0.737, blue: 0.557, alpha: 0.14)
        )
        static let danger = adaptive(
            light: NSColor(red: 0.741, green: 0.220, blue: 0.220, alpha: 1),
            dark: NSColor(red: 0.898, green: 0.510, blue: 0.510, alpha: 1)
        )
        static let dangerMuted = adaptive(
            light: NSColor(red: 0.741, green: 0.220, blue: 0.220, alpha: 0.10),
            dark: NSColor(red: 0.898, green: 0.510, blue: 0.510, alpha: 0.14)
        )
        static let warn = adaptive(
            light: NSColor(red: 0.600, green: 0.420, blue: 0.090, alpha: 1),
            dark: NSColor(red: 0.820, green: 0.659, blue: 0.349, alpha: 1)
        )
        static let warnMuted = adaptive(
            light: NSColor(red: 0.600, green: 0.420, blue: 0.090, alpha: 0.10),
            dark: NSColor(red: 0.820, green: 0.659, blue: 0.349, alpha: 0.14)
        )
        static let textOnAccent = adaptive(
            light: NSColor(white: 1.0, alpha: 1),
            dark: NSColor(red: 0.031, green: 0.035, blue: 0.043, alpha: 1)
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
        static let selectedNavigation = Semantic.surfaceRaised
        static let shortcutBackground = Semantic.surfaceRaised
        static let focusRing = Semantic.accent.opacity(0.40)
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

    /// Graphite pairs clean system text with a single sans display weight.
    enum Typography {
        static let display = Font.system(size: 30, weight: .semibold)
        static let pageTitle = Font.system(size: 24, weight: .semibold)
        static let pageContext = Font.system(size: 11, weight: .semibold)
        static let sectionTitle = Font.system(size: 10, weight: .semibold)
        static let body = Font.system(size: 13)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let caption = Font.system(size: 11.5)
        static let captionStrong = Font.system(size: 11.5, weight: .semibold)
        static let button = Font.system(size: 13, weight: .semibold)
        static let metric = Font.system(size: 22, weight: .semibold)
            .monospacedDigit()
        static let mono = Font.system(size: 12, design: .monospaced)
        static let monoSmall = Font.system(size: 10.5, design: .monospaced)
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

    /// Ledger corners are tight by intent — panels read as ruled paper rather
    /// than as cards, which is why `small` and `medium` currently coincide.
    /// They are kept as separate names because they mean different things and
    /// will not always agree.
    ///
    /// The ZenBar sits apart from that scale on purpose: it is a floating
    /// overlay against the desktop rather than a panel on the canvas, and it
    /// carries a shadow, so it needs a softer corner than ruled paper does.
    /// These values were previously hardcoded at its call sites.
    enum Radius {
        static let small: CGFloat = 4
        static let medium: CGFloat = 4
        static let large: CGFloat = 10
        static let bar: CGFloat = 9
        static let barControl: CGFloat = 6
    }
}
