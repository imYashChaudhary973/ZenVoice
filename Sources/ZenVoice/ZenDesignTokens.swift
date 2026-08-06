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

/// ZenVoice design tokens — indigo and violet on deep navy.
///
/// The palette is intentionally simple: one background family, one surface
/// family, one accent family, and one text family. Light mode is derived from
/// the same tokens by lightening the canvas and darkening the text, rather
/// than maintaining a separate hand-tuned theme.
enum ZenDesign {
    enum Primitive {
        // Base navy background. Never pure black.
        static let base = Color(nsColor: NSColor(red: 0.043, green: 0.059, blue: 0.102, alpha: 1))
        static let base900 = Color(nsColor: NSColor(red: 0.075, green: 0.098, blue: 0.165, alpha: 1))
        static let base800 = Color(nsColor: NSColor(red: 0.106, green: 0.137, blue: 0.227, alpha: 1))

        // Surfaces float above the base.
        static let surface = Color(nsColor: NSColor(red: 0.075, green: 0.102, blue: 0.169, alpha: 1))
        static let surfaceRaised = Color(nsColor: NSColor(red: 0.106, green: 0.141, blue: 0.220, alpha: 1))
        static let surfaceSunken = Color(nsColor: NSColor(red: 0.055, green: 0.078, blue: 0.133, alpha: 1))

        // Indigo-violet accent family.
        static let accent = Color(nsColor: NSColor(red: 0.427, green: 0.369, blue: 0.973, alpha: 1))
        static let accentGlow = Color(nsColor: NSColor(red: 0.545, green: 0.486, blue: 1.000, alpha: 1))
        static let accentMuted = Color(nsColor: NSColor(red: 0.427, green: 0.369, blue: 0.973, alpha: 0.18))

        // Text.
        static let text = Color(nsColor: NSColor(red: 0.910, green: 0.922, blue: 0.961, alpha: 1))
        static let muted = Color(nsColor: NSColor(red: 0.596, green: 0.635, blue: 0.722, alpha: 1))
        static let subtle = Color(nsColor: NSColor(red: 0.467, green: 0.510, blue: 0.600, alpha: 1))

        // Functional colours.
        static let success = Color(nsColor: NSColor(red: 0.357, green: 0.820, blue: 0.529, alpha: 1))
        static let warn = Color(nsColor: NSColor(red: 0.937, green: 0.722, blue: 0.357, alpha: 1))
        static let danger = Color(nsColor: NSColor(red: 0.937, green: 0.416, blue: 0.416, alpha: 1))

        static let white = Color.white
        static let black = Color.black
    }

    enum Semantic {
        static let canvas = adaptive(
            light: NSColor(red: 0.957, green: 0.961, blue: 0.973, alpha: 1),
            dark: NSColor(red: 0.043, green: 0.059, blue: 0.102, alpha: 1)
        )
        static let sidebar = adaptive(
            light: NSColor(red: 0.945, green: 0.949, blue: 0.961, alpha: 1),
            dark: NSColor(red: 0.035, green: 0.051, blue: 0.086, alpha: 1)
        )
        static let surface = adaptive(
            light: NSColor(red: 0.969, green: 0.973, blue: 0.980, alpha: 1),
            dark: NSColor(red: 0.075, green: 0.102, blue: 0.169, alpha: 1)
        )
        static let surfaceRaised = adaptive(
            light: NSColor(red: 0.937, green: 0.941, blue: 0.953, alpha: 1),
            dark: NSColor(red: 0.106, green: 0.141, blue: 0.220, alpha: 1)
        )
        static let surfaceSunken = adaptive(
            light: NSColor(red: 0.906, green: 0.914, blue: 0.929, alpha: 1),
            dark: NSColor(red: 0.055, green: 0.078, blue: 0.133, alpha: 1)
        )
        static let border = adaptive(
            light: NSColor(red: 0.106, green: 0.137, blue: 0.227, alpha: 0.10),
            dark: NSColor(red: 0.427, green: 0.486, blue: 0.620, alpha: 0.14)
        )
        static let borderStrong = adaptive(
            light: NSColor(red: 0.106, green: 0.137, blue: 0.227, alpha: 0.18),
            dark: NSColor(red: 0.427, green: 0.486, blue: 0.620, alpha: 0.24)
        )
        static let textPrimary = adaptive(
            light: NSColor(red: 0.063, green: 0.082, blue: 0.141, alpha: 1),
            dark: NSColor(red: 0.910, green: 0.922, blue: 0.961, alpha: 1)
        )
        static let textSecondary = adaptive(
            light: NSColor(red: 0.365, green: 0.404, blue: 0.486, alpha: 1),
            dark: NSColor(red: 0.596, green: 0.635, blue: 0.722, alpha: 1)
        )
        static let textTertiary = adaptive(
            light: NSColor(red: 0.494, green: 0.533, blue: 0.612, alpha: 1),
            dark: NSColor(red: 0.467, green: 0.510, blue: 0.600, alpha: 1)
        )
        static let accent = adaptive(
            light: NSColor(red: 0.396, green: 0.333, blue: 0.937, alpha: 1),
            dark: NSColor(red: 0.427, green: 0.369, blue: 0.973, alpha: 1)
        )
        static let accentStrong = adaptive(
            light: NSColor(red: 0.333, green: 0.271, blue: 0.855, alpha: 1),
            dark: NSColor(red: 0.545, green: 0.486, blue: 1.000, alpha: 1)
        )
        static let accentMuted = adaptive(
            light: NSColor(red: 0.396, green: 0.333, blue: 0.937, alpha: 0.12),
            dark: NSColor(red: 0.427, green: 0.369, blue: 0.973, alpha: 0.18)
        )
        static let success = adaptive(
            light: NSColor(red: 0.231, green: 0.604, blue: 0.357, alpha: 1),
            dark: NSColor(red: 0.357, green: 0.820, blue: 0.529, alpha: 1)
        )
        static let successMuted = adaptive(
            light: NSColor(red: 0.231, green: 0.604, blue: 0.357, alpha: 0.10),
            dark: NSColor(red: 0.357, green: 0.820, blue: 0.529, alpha: 0.14)
        )
        static let danger = adaptive(
            light: NSColor(red: 0.808, green: 0.259, blue: 0.259, alpha: 1),
            dark: NSColor(red: 0.937, green: 0.416, blue: 0.416, alpha: 1)
        )
        static let dangerMuted = adaptive(
            light: NSColor(red: 0.808, green: 0.259, blue: 0.259, alpha: 0.10),
            dark: NSColor(red: 0.937, green: 0.416, blue: 0.416, alpha: 0.14)
        )
        static let warn = adaptive(
            light: NSColor(red: 0.718, green: 0.510, blue: 0.165, alpha: 1),
            dark: NSColor(red: 0.937, green: 0.722, blue: 0.357, alpha: 1)
        )
        static let warnMuted = adaptive(
            light: NSColor(red: 0.718, green: 0.510, blue: 0.165, alpha: 0.10),
            dark: NSColor(red: 0.937, green: 0.722, blue: 0.357, alpha: 0.14)
        )
        static let textOnAccent = adaptive(
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
        static let shortcutBackground = Semantic.surfaceRaised
        static let focusRing = Semantic.accent.opacity(0.40)
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

    enum Typography {
        static let display = Font.system(size: 34, weight: .bold)
        static let pageTitle = Font.system(size: 22, weight: .bold)
        static let pageContext = Font.system(size: 12, weight: .semibold)
        static let sectionTitle = Font.system(size: 11, weight: .semibold)
        static let body = Font.system(size: 13)
        static let bodyStrong = Font.system(size: 13, weight: .semibold)
        static let caption = Font.system(size: 11.5)
        static let captionStrong = Font.system(size: 11.5, weight: .semibold)
        static let button = Font.system(size: 13, weight: .semibold)
        static let metric = Font.system(size: 28, weight: .bold)
        static let metricCaption = Font.system(size: 11, weight: .medium)
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

    /// Corner radii. Cards are intentionally softer than inputs; the ZenBar
    /// floats above the desktop and gets the largest radius of all.
    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
        static let bar: CGFloat = 9
        static let barControl: CGFloat = 6
    }
}
