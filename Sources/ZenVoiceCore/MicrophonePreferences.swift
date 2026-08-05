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

public enum MicrophonePreferences {
    public static let preferenceKey = "ZenVoice.selectedMicrophoneUID"

    public static func selectedDeviceUID(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> String? {
        defaults.string(forKey: preferenceKey)
    }

    public static func save(
        deviceUID: String?,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        if let deviceUID {
            defaults.set(deviceUID, forKey: preferenceKey)
        } else {
            defaults.removeObject(forKey: preferenceKey)
        }
    }
}
