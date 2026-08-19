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

public enum FoundationModelsGoalPlannerError: LocalizedError {
    case unavailable(LocalIntelligenceAvailability)
    case invalidResponse
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple's on-device model is unavailable."
        case .invalidResponse:
            return "The on-device planner returned an invalid plan."
        case .timedOut:
            return "The on-device planner timed out."
        }
    }
}

/// Schema-first planner backed by Apple's on-device Foundation Models runtime.
/// Validation and risk recomputation remain separate and authoritative.
public struct FoundationModelsGoalPlanningModel: GoalPlanningModel {
    private let model: any LocalLanguageModel
    private let timeoutNanoseconds: UInt64

    public init(
        model: any LocalLanguageModel = AppleOnDeviceLanguageModel(),
        timeoutSeconds: Double = 8
    ) {
        self.model = model
        timeoutNanoseconds = UInt64(max(timeoutSeconds, 0.1) * 1_000_000_000)
    }

    public func plan(transcript: String, allowedRoot: URL) async throws -> GoalPlan {
        guard model.availability == .available else {
            throw FoundationModelsGoalPlannerError.unavailable(model.availability)
        }
        let response = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await model.generate(
                    prompt: Self.prompt(
                        transcript: transcript,
                        allowedRoot: allowedRoot
                    ),
                    maximumResponseTokens: 2_048
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw FoundationModelsGoalPlannerError.timedOut
            }
            guard let first = try await group.next() else {
                throw FoundationModelsGoalPlannerError.invalidResponse
            }
            group.cancelAll()
            return first
        }
        guard let data = Self.jsonData(from: response) else {
            throw FoundationModelsGoalPlannerError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(GoalPlan.self, from: data)
        } catch {
            throw FoundationModelsGoalPlannerError.invalidResponse
        }
    }

    private static func prompt(transcript: String, allowedRoot: URL) -> String {
        """
        You are ZenVoice Planner. Convert the user's spoken goal into one small,
        ordered JSON plan. Return JSON only. Never execute anything.

        Allowed agents: codex, claude, shell, shortcut, notification.
        Use codex or claude for coding work. Use shell only when the user clearly
        requested an exact shell action. All working directories must be inside:
        \(allowedRoot.path)

        Constraints:
        - schemaVersion is 1.
        - id must be a UUID string.
        - 1 to 12 contiguous numbered steps.
        - timeoutSeconds must be 1 through 7200.
        - dependsOn may only refer to earlier step numbers.
        - notification must depend on prior work unless it is the only step.
        - plannedRisk is advisory: low, medium, or high.
        - computedRisk must be low; ZenVoice overwrites it after parsing.
        - proposedApprovalMode is proposeAll, proposeUpToNextHigh, or proposePerStep.
        - Never include credentials, tokens, or secrets.
        - Ask for clarification in title and return zero steps if the goal is
          ambiguous. Do not invent missing project paths or commands.

        JSON shape:
        {
          "schemaVersion": 1,
          "id": "UUID",
          "title": "short title",
          "proposedApprovalMode": "proposeUpToNextHigh",
          "createdAt": 0,
          "transcript": "original transcript",
          "steps": [{
            "number": 1,
            "agent": "codex",
            "command": "complete instruction",
            "description": "short visible description",
            "workingDirectory": "absolute path",
            "dependsOn": [],
            "timeoutSeconds": 600,
            "computedRisk": "low",
            "plannedRisk": "medium"
          }]
        }

        TRANSCRIPT START
        \(transcript)
        TRANSCRIPT END
        """
    }

    private static func jsonData(from response: String) -> Data? {
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}"),
              start <= end
        else {
            return nil
        }
        return String(response[start...end]).data(using: .utf8)
    }
}
