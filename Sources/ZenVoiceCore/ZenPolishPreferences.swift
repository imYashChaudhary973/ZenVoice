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

import Foundation

/// Whether the Smart formatting rung uses the ZenPolish model when it is
/// installed. Falls back to Apple's on-device model when disabled or when
/// the download is absent.
public enum ZenPolishPreferences {
    public static let preferenceKey = "ZenVoice.zenPolishEnabled"

    public static func load(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        defaults.object(forKey: preferenceKey) == nil
            ? true
            : defaults.bool(forKey: preferenceKey)
    }

    public static func save(
        _ enabled: Bool,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(enabled, forKey: preferenceKey)
    }
}
