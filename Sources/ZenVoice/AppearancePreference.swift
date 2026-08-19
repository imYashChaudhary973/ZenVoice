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

/// The v3 redesign is dark-only. This type is retained as a thin wrapper so
/// existing `@AppStorage` call sites compile and any stored legacy value
/// resolves to dark.
enum ZenAppearance: String, CaseIterable, Identifiable {
    case dark

    static let storageKey = "zenvoice.appearance"

    var id: String { rawValue }

    static func resolved(_ raw: String) -> ZenAppearance {
        ZenAppearance(rawValue: raw) ?? .dark
    }

    var colorScheme: ColorScheme { .dark }

    var title: String { "Dark" }

    var systemImage: String { "moon" }
}
