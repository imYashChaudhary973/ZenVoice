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

/// Active mode shown on the ZenBar.
///
/// Dictation is the default behavior. Command Mode interprets the transcript as
/// a voice command. Write Mode either composes at the caret or rewrites the
/// current selection.
public enum ZenBarMode: String, Codable, CaseIterable, Equatable, Sendable {
    case dictation
    case command
    case write

    public var displayName: String {
        switch self {
        case .dictation:
            return "Dictate"
        case .command:
            return "Command"
        case .write:
            return "Write"
        }
    }

    public var icon: String {
        switch self {
        case .dictation:
            return "mic"
        case .command:
            return "command"
        case .write:
            return "pencil"
        }
    }
}
