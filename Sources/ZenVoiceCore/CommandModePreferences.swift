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

/// Persistent settings for Command Mode.
///
/// Command Mode is disabled by default. When enabled, a parsed transcript can
/// be interpreted as a `CommandAction` by `CommandModeEngine`. This module only
/// stores the boolean and the manifest; execution is handled elsewhere.
public enum CommandModePreferences {
    public static let enabledKey = "ZenVoice.commandModeEnabled"
    public static let manifestKey = "ZenVoice.commandModeManifest"

    public static func isEnabled(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    public static func setEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(enabled, forKey: enabledKey)
    }

    public static func loadManifest(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> CommandManifest? {
        guard let data = defaults.data(forKey: manifestKey) else {
            return nil
        }
        return try? JSONDecoder().decode(
            CommandManifest.self,
            from: data
        )
    }

    public static func saveManifest(
        _ manifest: CommandManifest,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        guard let data = try? JSONEncoder().encode(manifest) else {
            return
        }
        defaults.set(data, forKey: manifestKey)
    }

    public static func clearManifest(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.removeObject(forKey: manifestKey)
    }
}
