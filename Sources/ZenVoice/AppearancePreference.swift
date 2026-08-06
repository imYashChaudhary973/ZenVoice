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

import SwiftUI

/// Light, dark, or whatever the Mac is set to.
///
/// The token layer is built entirely on `NSColor(name:)` providers that already
/// resolve per appearance, so following the system costs nothing — it only
/// requires *not* forcing a `preferredColorScheme`. Before this, the stored
/// preference defaulted to `"light"` and was applied unconditionally, so a
/// ZenBar floating over a dark desktop was bright white until the user found
/// the setting.
///
/// Absent key means System. `@AppStorage` writes its default only when the
/// value is set, so an untouched preference is distinguishable from a
/// deliberate `"light"` — the same trick `AppState` uses for
/// `showsStatusMessage`. Anyone who explicitly picked light or dark keeps it.
enum ZenAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "zenvoice.appearance"

    var id: String { rawValue }

    static func resolved(_ raw: String) -> ZenAppearance {
        ZenAppearance(rawValue: raw) ?? .system
    }

    /// `nil` hands the decision back to macOS.
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }
}
