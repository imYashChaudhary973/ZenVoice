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


import CryptoKit
import Foundation

/// Types that cross the device boundary unchanged.
///
/// The Mac orchestrator, the encrypted task store, and the iPhone
/// companion all speak exactly these shapes; `ZenVoiceLink` frames carry
/// them verbatim rather than defining a second schema. Everything here is
/// pure Foundation so the companion can compile it for iOS.


/// Timestamps in the envelope are microsecond-precise, and every serializer
/// preserves exactly that.
///
/// `Date()` carries sub-microsecond precision that no decimal encoding round-
/// trips: a plan reloaded from the vault, or an event that crossed the link,
/// then compares unequal to the one still in memory even though both print the
/// same instant. Since an `ApprovalDecision` is bound to plan bytes, "nearly
/// the same" is not good enough, so the envelope quantizes on the way in and
/// encodes whole microseconds on the way out.
public enum AgenticTimestamp {
    public static func now() -> Date {
        quantized(Date())
    }

    public static func quantized(_ date: Date) -> Date {
        Date(timeIntervalSince1970: Double(microseconds(date)) / 1_000_000)
    }

    public static func microseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
    }

    public static let encoding: JSONEncoder.DateEncodingStrategy = .custom {
        date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(microseconds(date))
    }

    public static let decoding: JSONDecoder.DateDecodingStrategy = .custom {
        decoder in
        let microseconds = try decoder.singleValueContainer().decode(Int64.self)
        return Date(timeIntervalSince1970: Double(microseconds) / 1_000_000)
    }
}

public enum GoalState: String, Codable, Sendable, CaseIterable {
    case idle
    case planning
    case awaitingApproval
    case running
    case succeeded
    case failed
    case cancelled
    case interrupted

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled, .interrupted:
            return true
        default:
            return false
        }
    }
}

public enum StepState: String, Codable, Sendable {
    case pending
    case running
    case awaitingApproval
    case succeeded
    case failed
    case skipped
    case cancelled
}

public enum GoalEventType: String, Codable, Sendable {
    case goalStarted = "goal.started"
    case planEdited = "goal.plan_edited"
    case awaitingApproval = "goal.awaiting_approval"
    case approved = "goal.approved"
    case stepStarted = "step.started"
    case stepOutput = "step.output"
    case stepSucceeded = "step.succeeded"
    case stepFailed = "step.failed"
    case stepApprovalRequired = "goal.step_approval_required"
    case cancelling = "goal.cancelling"
    case cancelled = "goal.cancelled"
    case failed = "goal.failed"
    case interrupted = "goal.interrupted"
    case notification = "goal.notification"
    case succeeded = "goal.succeeded"
}

public struct GoalStatusEvent: Codable, Equatable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let goalID: UUID
    public let sequence: Int
    public let emittedAt: Date
    public let event: GoalEventType
    public let step: Int?
    public let message: String

    public var id: String { "\(goalID.uuidString)-\(sequence)" }

    public init(
        schemaVersion: Int = 1,
        goalID: UUID,
        sequence: Int,
        emittedAt: Date = AgenticTimestamp.now(),
        event: GoalEventType,
        step: Int? = nil,
        message: String
    ) {
        self.schemaVersion = schemaVersion
        self.goalID = goalID
        self.sequence = sequence
        self.emittedAt = AgenticTimestamp.quantized(emittedAt)
        self.event = event
        self.step = step
        self.message = message
    }
}

public enum ApprovalMode: String, Codable, Sendable, CaseIterable {
    case all
    case upToNextHighRisk
    case perStep
}

public enum ApprovalAction: String, Codable, Sendable {
    case approved
    case rejected
    case cancelled
}

public struct ApprovalDecision: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let planID: UUID
    public let planSHA256: String
    public let planVersion: Int
    public let action: ApprovalAction
    public let mode: ApprovalMode?
    public let coveredStepNumbers: [Int]
    public let decidedAt: Date

    public init(
        id: UUID = UUID(),
        planID: UUID,
        planSHA256: String,
        planVersion: Int,
        action: ApprovalAction,
        mode: ApprovalMode? = nil,
        coveredStepNumbers: [Int] = [],
        decidedAt: Date = AgenticTimestamp.now()
    ) {
        self.id = id
        self.planID = planID
        self.planSHA256 = planSHA256
        self.planVersion = planVersion
        self.action = action
        self.mode = mode
        self.coveredStepNumbers = coveredStepNumbers
        self.decidedAt = AgenticTimestamp.quantized(decidedAt)
    }
}

public struct GoalStepRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { number }
    public let number: Int
    public var state: StepState
    public var startedAt: Date?
    public var completedAt: Date?
    public var exitStatus: Int32?
    public var summary: String?
    public var retainedOutput: String

    public init(number: Int, state: StepState = .pending) {
        self.number = number
        self.state = state
        self.retainedOutput = ""
    }
}

public struct AgenticTaskRecord: Codable, Equatable, Sendable, Identifiable {
    public static let schemaVersion = 1

    public let id: UUID
    public var state: GoalState
    public var planVersions: [GoalPlan]
    public var decisions: [ApprovalDecision]
    public var steps: [GoalStepRecord]
    public var events: [GoalStatusEvent]
    public let createdAt: Date
    public var updatedAt: Date

    public var plan: GoalPlan { planVersions[planVersions.count - 1] }

    public init(
        id: UUID = UUID(),
        plan: GoalPlan,
        state: GoalState = .awaitingApproval,
        createdAt: Date = AgenticTimestamp.now()
    ) {
        self.id = id
        self.state = state
        self.planVersions = [plan]
        self.decisions = []
        self.steps = plan.steps.map { GoalStepRecord(number: $0.number) }
        self.events = []
        self.createdAt = AgenticTimestamp.quantized(createdAt)
        self.updatedAt = AgenticTimestamp.quantized(createdAt)
    }
}

public enum SecretRedactor {
    private static let patterns = [
        #"AKIA[0-9A-Z]{16}"#,
        #"\bsk-[A-Za-z0-9_-]{16,}\b"#,
        #"\bBearer\s+[A-Za-z0-9._~+/=-]{12,}"#,
        #"(?i)\b(?:api[_-]?key|token|secret|password)\s*[:=]\s*[^\s,;]+"#,
    ]

    public static func redact(_ text: String) -> String {
        var result = text
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "[REDACTED]"
            )
        }
        return result
    }
}

/// Canonical hash of a plan, used to bind an approval to the exact bytes the
/// user saw. Sorted keys and whole-microsecond dates make the hash independent
/// of who computed it: the Mac, the vault after a reload, or the phone
/// checking what it was shown.
public enum GoalPlanDigest {
    public static func sha256(_ plan: GoalPlan) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = AgenticTimestamp.encoding
        let data = (try? encoder.encode(plan)) ?? Data()
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
