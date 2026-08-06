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

/// Persistent approval state for script and URL actions in Command Mode.
///
/// Built-in actions (`LaunchApp`, `RunShortcut`, `SystemAction`) do not need
/// user approval. `RunAppleScript`, `RunShellScript`, and `OpenURL` require an
/// explicit first-run approval stored here.
public enum CommandModeApprovalPreferences {
    public static let approvedActionsKey =
        "ZenVoice.commandMode.approvedActions"

    public static func isApproved(
        _ action: CommandAction,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        guard requiresApproval(action) else { return true }
        let key = approvalKey(for: action)
        return defaults.bool(forKey: key)
    }

    public static func setApproved(
        _ action: CommandAction,
        approved: Bool = true,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        guard requiresApproval(action) else { return }
        let key = approvalKey(for: action)
        defaults.set(approved, forKey: key)
    }

    public static func requiresApproval(_ action: CommandAction) -> Bool {
        switch action {
        case .appleScript, .shellScript, .openURL:
            return true
        default:
            return false
        }
    }

    private static func approvalKey(for action: CommandAction) -> String {
        switch action {
        case .appleScript:
            return approvedActionsKey + ".appleScript"
        case .shellScript:
            return approvedActionsKey + ".shellScript"
        case .openURL(let url):
            return approvedActionsKey + ".openURL." + url.absoluteString
        default:
            return approvedActionsKey + ".unknown"
        }
    }
}

/// A type that can execute parsed `CommandAction`s.
///
/// `ZenVoiceCore` defines the actions and parser; the app target provides a
/// concrete executor that bridges to `NSWorkspace`, `Shortcuts`,
/// Accessibility, and `Process`. Tests use a recording executor.
public protocol CommandModeExecutor: Sendable {
    func execute(_ action: CommandAction) async throws
}

/// A no-op executor suitable for tests and previews.
public actor RecordingCommandModeExecutor: CommandModeExecutor {
    public private(set) var actions: [CommandAction] = []

    public init() {}

    public func execute(_ action: CommandAction) async throws {
        actions.append(action)
    }
}

/// Errors that can occur during command execution.
public enum CommandModeExecutionError: LocalizedError {
    case notApproved
    case missingBundleID
    case shortcutFailed(String)
    case systemActionFailed(CommandModeSystemAction)
    case scriptFailed(String)
    case invalidAction

    public var errorDescription: String? {
        switch self {
        case .notApproved:
            return "This command requires your approval before it can run."
        case .missingBundleID:
            return "The app identifier is missing."
        case .shortcutFailed(let name):
            return "Shortcut '\(name)' could not be run."
        case .systemActionFailed(let action):
            return "System action '\(action.displayName)' failed."
        case .scriptFailed(let reason):
            return "Script failed: \(reason)"
        case .invalidAction:
            return "The command could not be executed."
        }
    }
}
