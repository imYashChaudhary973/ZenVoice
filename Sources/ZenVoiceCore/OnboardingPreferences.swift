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

public enum OnboardingPreferences {
    public static let completionKey =
        "ZenVoice.onboarding.completed.v1"

    public static func shouldPresent(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        if defaults.object(forKey: completionKey) != nil {
            return !defaults.bool(forKey: completionKey)
        }

        let existingInstallKeys = [
            ModelSelectionPreferences.preferenceKey,
            LanguagePreferences.preferenceKey,
            InstantRefinePreferences.preferenceKey,
            "ZenVoice.history.hasEverEnabled",
            "ZenVoice.dictationHotKey"
        ]
        let isExistingInstall = existingInstallKeys.contains {
            defaults.object(forKey: $0) != nil
        }
        if isExistingInstall {
            defaults.set(true, forKey: completionKey)
            return false
        }
        return true
    }

    public static func complete(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(true, forKey: completionKey)
    }

    public static func reset(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(false, forKey: completionKey)
    }
}
