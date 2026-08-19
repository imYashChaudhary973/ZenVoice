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

public enum AgenticModePreferences {
    public static let enabledKey = "ZenVoice.agenticModeEnabled"

    /// The stored switch. Prefer ``isEffectivelyEnabled(defaults:)`` at every
    /// decision point: Agentic Mode is an extension of Command Mode, and a
    /// stale `true` here must never outlive Command Mode being switched off.
    public static func isEnabled(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    /// Whether a spoken goal may be planned and executed right now.
    public static func isEffectivelyEnabled(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        isEnabled(defaults: defaults)
            && CommandModePreferences.isEnabled(defaults: defaults)
    }

    /// Enabling Agentic Mode enables Command Mode with it: the agentic path is
    /// only reached after the deterministic phrase parser declines, so leaving
    /// Command Mode off would make the switch silently do nothing.
    public static func setEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(enabled, forKey: enabledKey)
        if enabled {
            CommandModePreferences.setEnabled(true, defaults: defaults)
        }
    }
}


public enum ApprovalResponse: Sendable {
    case decision(ApprovalDecision)
    case edited(GoalPlan)
}


public struct ExecutorOutput: Equatable, Sendable {
    public enum Channel: String, Codable, Sendable {
        case stdout
        case stderr
    }

    public let channel: Channel
    public let text: String

    public init(channel: Channel, text: String) {
        self.channel = channel
        self.text = text
    }
}

public struct ExecutorOutcome: Equatable, Sendable {
    public let exitStatus: Int32
    public let summary: String
    public let timedOut: Bool
    public let cancelled: Bool

    public init(
        exitStatus: Int32,
        summary: String,
        timedOut: Bool = false,
        cancelled: Bool = false
    ) {
        self.exitStatus = exitStatus
        self.summary = summary
        self.timedOut = timedOut
        self.cancelled = cancelled
    }

    public var succeeded: Bool { exitStatus == 0 && !timedOut && !cancelled }
}

public protocol GoalExecutor: Sendable {
    func run(
        step: GoalStep,
        output: @escaping @Sendable (ExecutorOutput) async -> Void
    ) async -> ExecutorOutcome
    func cancel() async
}

public protocol GoalRecordPersisting: Sendable {
    func saveAgenticTask(_ record: AgenticTaskRecord) async throws
    func loadActiveAgenticTasks() async throws -> [AgenticTaskRecord]
}

public enum GoalPlannerResult: Sendable {
    case plan(GoalPlan, source: String)
    case notGoal(String)
}

public protocol GoalPlanningModel: Sendable {
    func plan(transcript: String, allowedRoot: URL) async throws -> GoalPlan
}

