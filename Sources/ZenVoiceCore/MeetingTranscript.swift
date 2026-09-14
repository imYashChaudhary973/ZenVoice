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

/// Builds the immutable original from You (mic) and Them (system) decodes.
///
/// Channel labels, not identities. Interleaves timed segments when both
/// engines reported them; otherwise stacks the two blocks.
public enum MeetingTranscript {
    public static func merging(
        you: TranscriptionResult,
        them: TranscriptionResult?
    ) -> String {
        let youText = you.finalTranscript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let themText = them?.finalTranscript.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""

        let youSegments = you.segments.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let themSegments = (them?.segments ?? []).filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if !youSegments.isEmpty, !themSegments.isEmpty {
            var turns: [(TimeInterval, String, String)] = []
            turns.reserveCapacity(youSegments.count + themSegments.count)
            for segment in youSegments {
                turns.append((segment.startSeconds, "You", segment.text))
            }
            for segment in themSegments {
                turns.append((segment.startSeconds, "Them", segment.text))
            }
            turns.sort { $0.0 < $1.0 }
            return turns
                .map { "\($0.1): \($0.2.trimmingCharacters(in: .whitespacesAndNewlines))" }
                .joined(separator: "\n")
        }

        if themText.isEmpty {
            return youText
        }
        if youText.isEmpty {
            return "Them:\n\(themText)"
        }
        return "You:\n\(youText)\n\nThem:\n\(themText)"
    }
}
