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

/// A transcription agent that can execute a plan step.
///
/// The set is deliberately small and fixed in v2; unknown agents are rejected
/// by the validator rather than silently treated as shell.
public enum GoalAgent: String, Codable, Equatable, Sendable, CaseIterable {
    case codex
    case claude
    case shell
    case shortcut
    case notification

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .shell: return "Shell"
        case .shortcut: return "Shortcuts"
        case .notification: return "Notification"
        }
    }
}

/// Computed risk of a step, derived from the command surface by the validator.
///
/// The planner may propose a `plannedRisk`, but it is advisory only;
/// `PlanValidator` overwrites `computedRisk`.
public enum RiskLevel: String, Codable, Equatable, Sendable, Comparable {
    case low
    case medium
    case high

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        let order: [RiskLevel] = [.low, .medium, .high]
        guard let li = order.firstIndex(of: lhs),
              let ri = order.firstIndex(of: rhs) else { return false }
        return li < ri
    }
}

/// A planner's suggestion for how the approval gate should initially present
/// the plan. Distinct from `ApprovalAction`, which records what the user did.
public enum PlanApprovalProposal: String, Codable, Equatable, Sendable {
    case proposeAll
    case proposeUpToNextHigh
    case proposePerStep
}

/// One validated (or to-be-validated) step of a multi-step goal.
public struct GoalStep: Codable, Equatable, Sendable {
    public var number: Int
    public var agent: GoalAgent
    public var command: String
    public var description: String
    public var workingDirectory: String?
    public var dependsOn: [Int]
    public var plannedRisk: RiskLevel
    public var computedRisk: RiskLevel
    public var timeoutSeconds: Int

    public init(
        number: Int,
        agent: GoalAgent,
        command: String,
        description: String,
        workingDirectory: String? = nil,
        dependsOn: [Int] = [],
        plannedRisk: RiskLevel = .low,
        computedRisk: RiskLevel = .low,
        timeoutSeconds: Int = 600
    ) {
        self.number = number
        self.agent = agent
        self.command = command
        self.description = description
        self.workingDirectory = workingDirectory
        self.dependsOn = dependsOn
        self.plannedRisk = plannedRisk
        self.computedRisk = computedRisk
        self.timeoutSeconds = timeoutSeconds
    }
}

/// A parsed, versioned multi-step goal produced by the planner tiers.
///
/// The planner is untrusted input: every field is re-validated before any
/// step executes. See `PlanValidator`.
public struct GoalPlan: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: UUID
    public var title: String
    public var proposedApprovalMode: PlanApprovalProposal
    public var createdAt: Date
    public var transcript: String
    public var steps: [GoalStep]

    public init(
        schemaVersion: Int = 1,
        id: UUID = UUID(),
        title: String,
        proposedApprovalMode: PlanApprovalProposal = .proposeUpToNextHigh,
        createdAt: Date = AgenticTimestamp.now(),
        transcript: String,
        steps: [GoalStep]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.proposedApprovalMode = proposedApprovalMode
        self.createdAt = AgenticTimestamp.quantized(createdAt)
        self.transcript = transcript
        self.steps = steps
    }
}
