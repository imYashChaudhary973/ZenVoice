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

/// A type that can execute parsed `CommandAction`s.
///
/// `ZenVoiceCore` defines the actions and parser; the app target provides a
/// concrete executor that bridges to `NSWorkspace`, Accessibility, CoreAudio,
/// and IOKit. Script, shell, and URL execution moved to Agentic Mode's
/// plan-approval pipeline; Command Mode runs built-in actions only.
public protocol CommandModeExecutor: Sendable {
    func execute(_ action: CommandAction) async throws
}

/// Errors that can occur during command execution.
public enum CommandModeExecutionError: LocalizedError {
    case missingBundleID
    case systemActionFailed(CommandModeSystemAction)

    public var errorDescription: String? {
        switch self {
        case .missingBundleID:
            return "The app identifier is missing."
        case .systemActionFailed(let action):
            return "System action '\(action.displayName)' failed."
        }
    }
}
