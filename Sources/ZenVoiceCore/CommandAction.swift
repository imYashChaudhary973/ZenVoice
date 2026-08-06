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

/// A voice command parsed from a transcript.
///
/// The parser returns these values; nothing in `ZenVoiceCore` executes them.
/// Execution wiring (Shortcuts, NSWorkspace, AppleEvents, shell) is intentionally
/// out of scope for this module and will be handled by the app layer in later
/// phases.
public enum CommandAction: Equatable, Sendable, Codable {
    case none
    case launchApp(bundleID: String)
    case runShortcut(name: String)
    case systemAction(CommandModeSystemAction)
    case appleScript(String)
    case shellScript(String)
}

/// System-level actions that do not need a third-party identifier.
///
/// The string raw value is stable so a persisted manifest remains valid across
// app updates.
public enum CommandModeSystemAction: String, Equatable, Sendable, Codable,
    CaseIterable {
    case copyLastTranscript
    case pasteLastDictation
    case showPreferences
    case lockScreen
    case searchSelectedText

    public var displayName: String {
        switch self {
        case .copyLastTranscript:
            return "Copy last transcript"
        case .pasteLastDictation:
            return "Paste last dictation"
        case .showPreferences:
            return "Open ZenVoice settings"
        case .lockScreen:
            return "Lock screen"
        case .searchSelectedText:
            return "Search selected text"
        }
    }
}
