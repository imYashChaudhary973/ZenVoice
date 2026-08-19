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

public enum GoalOrchestratorError: LocalizedError {
    case missingExecutor(GoalAgent)
    case invalidApproval
    case persistence(String)

    public var errorDescription: String? {
        switch self {
        case .missingExecutor(let agent):
            return "No executor is available for \(agent.displayName)."
        case .invalidApproval:
            return "The approval did not match the exact plan shown."
        case .persistence(let reason):
            return "The encrypted goal record could not be saved: \(reason)"
        }
    }
}

/// Serial, fail-closed execution of approved multi-step goals.
public actor GoalOrchestrator {
    public static let maxRetainedOutputBytes = 5 * 1024 * 1024
    public static let maxEvents = 500

    public typealias ApprovalHandler = @Sendable (
        _ plan: GoalPlan,
        _ planVersion: Int,
        _ stepNumber: Int?
    ) async -> ApprovalResponse
    public typealias StatusHandler = @Sendable (GoalStatusEvent) async -> Void

    private let validator: PlanValidator
    private let store: any GoalRecordPersisting
    private let executors: [GoalAgent: any GoalExecutor]
    private let approvalHandler: ApprovalHandler
    private let statusHandler: StatusHandler

    private var records: [UUID: AgenticTaskRecord] = [:]
    private var queue: [UUID] = []
    private var activeGoalID: UUID?
    private var cancelledGoalIDs = Set<UUID>()
    private var persistenceFailures: [UUID: String] = [:]

    public init(
        validator: PlanValidator = PlanValidator(),
        store: any GoalRecordPersisting,
        executors: [GoalAgent: any GoalExecutor],
        approvalHandler: @escaping ApprovalHandler,
        statusHandler: @escaping StatusHandler
    ) {
        self.validator = validator
        self.store = store
        self.executors = executors
        self.approvalHandler = approvalHandler
        self.statusHandler = statusHandler
    }

    @discardableResult
    public func submit(_ proposedPlan: GoalPlan) async throws -> UUID {
        let plan = try validator.validate(proposedPlan)
        var record = AgenticTaskRecord(plan: plan)
        appendEvent(
            .goalStarted,
            message: "Plan ready: \(plan.title)",
            to: &record
        )
        appendEvent(
            .awaitingApproval,
            message: "Waiting for plan approval.",
            to: &record
        )
        try await persist(record)
        records[record.id] = record
        queue.append(record.id)
        Task { await self.drainQueue() }
        return record.id
    }

    public func cancelActiveGoal() async {
        guard let goalID = activeGoalID ?? queue.first else { return }
        await cancel(goalID: goalID)
    }

    public func cancel(goalID: UUID) async {
        guard var record = records[goalID], !record.state.isTerminal else {
            return
        }
        cancelledGoalIDs.insert(goalID)
        appendEvent(
            .cancelling,
            message: "Cancel pressed; stopping active work.",
            to: &record
        )
        records[goalID] = record
        await statusHandler(record.events[record.events.count - 1])
        try? await persist(record)

        if activeGoalID == goalID,
           let runningStep = record.steps.first(where: { $0.state == .running }),
           let planStep = record.plan.steps.first(where: {
               $0.number == runningStep.number
           }),
           let executor = executors[planStep.agent]
        {
            await executor.cancel()
        } else {
            queue.removeAll(where: { $0 == goalID })
            await finishCancelled(goalID: goalID)
        }
    }

    /// Relaunch never resumes a process. Non-terminal records become
    /// interrupted and remain available for a fresh user-approved rerun.
    public func recoverAfterRelaunch() async {
        guard let active = try? await store.loadActiveAgenticTasks() else {
            return
        }
        for var record in active {
            for index in record.steps.indices
            where record.steps[index].state == .running
                || record.steps[index].state == .awaitingApproval
            {
                record.steps[index].state = .cancelled
                record.steps[index].completedAt = Date()
            }
            record.state = .interrupted
            appendEvent(
                .interrupted,
                message: "Previous run was interrupted; nothing was relaunched.",
                to: &record
            )
            records[record.id] = record
            try? await persist(record)
            if let event = record.events.last {
                await statusHandler(event)
            }
        }
    }

    public func record(for goalID: UUID) -> AgenticTaskRecord? {
        records[goalID]
    }


    private func drainQueue() async {
        guard activeGoalID == nil else { return }
        while !queue.isEmpty {
            let goalID = queue.removeFirst()
            guard records[goalID]?.state.isTerminal == false else { continue }
            activeGoalID = goalID
            await run(goalID: goalID)
            activeGoalID = nil
        }
    }

    private func run(goalID: UUID) async {
        guard await obtainPlanApproval(goalID: goalID),
              var record = records[goalID]
        else {
            return
        }

        if cancelledGoalIDs.contains(goalID) {
            await finishCancelled(goalID: goalID)
            return
        }
        record.state = .running
        record.updatedAt = Date()
        records[goalID] = record
        guard (try? await persist(record)) != nil else {
            await failPersistence(goalID: goalID)
            return
        }

        let plan = record.plan
        let initiallyCovered = Set(
            record.decisions
                .filter { $0.action == .approved }
                .flatMap(\.coveredStepNumbers)
        )

        for step in plan.steps {
            if cancelledGoalIDs.contains(goalID) {
                await finishCancelled(goalID: goalID)
                return
            }
            guard dependenciesSucceeded(for: step, goalID: goalID) else {
                await markSkipped(step: step, goalID: goalID)
                continue
            }

            let needsStepApproval = step.computedRisk == .high
                || !initiallyCovered.contains(step.number)
            if needsStepApproval,
               !AgenticApprovalPreferences.isRemembered(step)
            {
                let approved = await obtainStepApproval(
                    step: step,
                    goalID: goalID
                )
                if !approved {
                    if cancelledGoalIDs.contains(goalID) {
                        await finishCancelled(goalID: goalID)
                    } else {
                        await fail(
                            goalID: goalID,
                            message: "Step \(step.number) was not approved."
                        )
                    }
                    return
                }
            }

            guard let executor = executors[step.agent] else {
                await fail(
                    goalID: goalID,
                    message: GoalOrchestratorError
                        .missingExecutor(step.agent)
                        .localizedDescription
                )
                return
            }
            await markStepRunning(step: step, goalID: goalID)
            let outcome = await executor.run(step: step) { [weak self] chunk in
                await self?.appendOutput(
                    chunk,
                    stepNumber: step.number,
                    goalID: goalID
                )
            }

            if let persistenceFailure = persistenceFailures[goalID] {
                await fail(
                    goalID: goalID,
                    message: GoalOrchestratorError
                        .persistence(persistenceFailure)
                        .localizedDescription
                )
                return
            }
            if cancelledGoalIDs.contains(goalID) || outcome.cancelled {
                await finishCancelled(goalID: goalID)
                return
            }
            guard outcome.succeeded else {
                await markStepFailed(step: step, outcome: outcome, goalID: goalID)
                await skipRemaining(after: step.number, goalID: goalID)
                await fail(goalID: goalID, message: outcome.summary)
                return
            }
            await markStepSucceeded(step: step, outcome: outcome, goalID: goalID)
        }

        guard var completed = records[goalID] else { return }
        completed.state = .succeeded
        appendEvent(
            .succeeded,
            message: "Goal completed.",
            to: &completed
        )
        records[goalID] = completed
        try? await persistAndPublish(completed)
    }

    private func obtainPlanApproval(goalID: UUID) async -> Bool {
        while var record = records[goalID] {
            if cancelledGoalIDs.contains(goalID) { return false }
            let plan = record.plan
            let version = record.planVersions.count
            let response = await approvalHandler(plan, version, nil)
            switch response {
            case .edited(let edited):
                do {
                    let validated = try validator.validate(edited)
                    record.planVersions.append(validated)
                    record.steps = validated.steps.map {
                        GoalStepRecord(number: $0.number)
                    }
                    appendEvent(
                        .planEdited,
                        message: "Edited plan v\(record.planVersions.count) is ready for review.",
                        to: &record
                    )
                    appendEvent(
                        .awaitingApproval,
                        message: "Waiting for edited plan approval.",
                        to: &record
                    )
                    records[goalID] = record
                    guard (try? await persistAndPublish(record)) != nil else {
                        await failPersistence(goalID: goalID)
                        return false
                    }
                } catch {
                    await fail(
                        goalID: goalID,
                        message: PlanValidator.fallbackReason(
                            for: error as? PlanValidationError
                                ?? .unsupportedSchemaVersion(edited.schemaVersion)
                        )
                    )
                    return false
                }
            case .decision(let decision):
                guard decisionMatches(
                    decision,
                    plan: plan,
                    version: version,
                    stepNumber: nil
                ) else {
                    await fail(
                        goalID: goalID,
                        message: GoalOrchestratorError.invalidApproval.localizedDescription
                    )
                    return false
                }
                record.decisions.append(decision)
                if decision.action != .approved {
                    records[goalID] = record
                    await finishCancelled(goalID: goalID)
                    return false
                }
                rememberCoveredLowRiskSteps(
                    decision.coveredStepNumbers,
                    in: plan
                )
                appendEvent(
                    .approved,
                    message: "Approved plan v\(version).",
                    to: &record
                )
                records[goalID] = record
                guard (try? await persistAndPublish(record)) != nil else {
                    await failPersistence(goalID: goalID)
                    return false
                }
                return true
            }
        }
        return false
    }

    private func obtainStepApproval(step: GoalStep, goalID: UUID) async -> Bool {
        guard var record = records[goalID] else { return false }
        record.steps[index(of: step.number, in: record)].state = .awaitingApproval
        appendEvent(
            .stepApprovalRequired,
            step: step.number,
            message: "Step \(step.number) requires approval.",
            to: &record
        )
        records[goalID] = record
        try? await persistAndPublish(record)

        let response = await approvalHandler(
            record.plan,
            record.planVersions.count,
            step.number
        )
        guard case .decision(let decision) = response,
              decisionMatches(
                decision,
                plan: record.plan,
                version: record.planVersions.count,
                stepNumber: step.number
              )
        else {
            return false
        }
        record.decisions.append(decision)
        records[goalID] = record
        guard decision.action == .approved else { return false }
        if step.computedRisk == .low {
            AgenticApprovalPreferences.remember(step)
        }
        try? await persist(record)
        return true
    }

    private func decisionMatches(
        _ decision: ApprovalDecision,
        plan: GoalPlan,
        version: Int,
        stepNumber: Int?
    ) -> Bool {
        guard decision.planID == plan.id,
              decision.planSHA256 == GoalPlanDigest.sha256(plan),
              decision.planVersion == version
        else {
            return false
        }
        if let stepNumber {
            return decision.coveredStepNumbers == [stepNumber]
                && decision.mode == .perStep
        }
        guard decision.action == .approved else { return true }
        let highIndex = plan.steps.firstIndex(where: {
            $0.computedRisk == .high
        })
        let expected: [Int]
        switch decision.mode {
        case .all:
            guard highIndex == nil else { return false }
            expected = plan.steps.map(\.number)
        case .upToNextHighRisk:
            expected = plan.steps.prefix(highIndex ?? plan.steps.count)
                .map(\.number)
        case .perStep:
            if let first = plan.steps.first, first.computedRisk != .high {
                expected = [first.number]
            } else {
                expected = []
            }
        case nil:
            return false
        }
        return decision.coveredStepNumbers == expected
    }

    private func dependenciesSucceeded(for step: GoalStep, goalID: UUID) -> Bool {
        guard let record = records[goalID] else { return false }
        return step.dependsOn.allSatisfy { dependency in
            record.steps.first(where: { $0.number == dependency })?.state
                == .succeeded
        }
    }

    private func markStepRunning(step: GoalStep, goalID: UUID) async {
        guard var record = records[goalID] else { return }
        let index = index(of: step.number, in: record)
        record.steps[index].state = .running
        record.steps[index].startedAt = Date()
        appendEvent(
            .stepStarted,
            step: step.number,
            message: "Running \(step.agent.displayName): \(step.description)",
            to: &record
        )
        records[goalID] = record
        try? await persistAndPublish(record)
    }

    private func appendOutput(
        _ chunk: ExecutorOutput,
        stepNumber: Int,
        goalID: UUID
    ) async {
        guard var record = records[goalID] else { return }
        let redacted = SecretRedactor.redact(chunk.text)
        let index = index(of: stepNumber, in: record)
        let combined = record.steps[index].retainedOutput + redacted
        record.steps[index].retainedOutput = Self.cappedOutput(combined)
        let preview = Self.cappedOutput(redacted, maxBytes: 8 * 1024)
        appendEvent(
            .stepOutput,
            step: stepNumber,
            message: preview,
            to: &record
        )
        records[goalID] = record
        if let event = record.events.last {
            await statusHandler(event)
        }
        do {
            try await persist(record)
        } catch {
            persistenceFailures[goalID] = error.localizedDescription
            if let step = record.plan.steps.first(where: {
                $0.number == stepNumber
            }), let executor = executors[step.agent] {
                await executor.cancel()
            }
        }
    }

    private func markStepSucceeded(
        step: GoalStep,
        outcome: ExecutorOutcome,
        goalID: UUID
    ) async {
        guard var record = records[goalID] else { return }
        let index = index(of: step.number, in: record)
        record.steps[index].state = .succeeded
        record.steps[index].completedAt = Date()
        record.steps[index].exitStatus = outcome.exitStatus
        record.steps[index].summary = outcome.summary
        appendEvent(
            .stepSucceeded,
            step: step.number,
            message: outcome.summary,
            to: &record
        )
        records[goalID] = record
        try? await persistAndPublish(record)
    }

    private func markStepFailed(
        step: GoalStep,
        outcome: ExecutorOutcome,
        goalID: UUID
    ) async {
        guard var record = records[goalID] else { return }
        let index = index(of: step.number, in: record)
        record.steps[index].state = .failed
        record.steps[index].completedAt = Date()
        record.steps[index].exitStatus = outcome.exitStatus
        record.steps[index].summary = outcome.summary
        appendEvent(
            .stepFailed,
            step: step.number,
            message: outcome.summary,
            to: &record
        )
        records[goalID] = record
        try? await persistAndPublish(record)
    }

    private func markSkipped(step: GoalStep, goalID: UUID) async {
        guard var record = records[goalID] else { return }
        let index = index(of: step.number, in: record)
        record.steps[index].state = .skipped
        record.steps[index].completedAt = Date()
        record.steps[index].summary = "Dependency did not succeed."
        records[goalID] = record
        try? await persist(record)
    }

    private func skipRemaining(after number: Int, goalID: UUID) async {
        guard var record = records[goalID] else { return }
        for index in record.steps.indices
        where record.steps[index].number > number
            && record.steps[index].state == .pending
        {
            record.steps[index].state = .skipped
            record.steps[index].completedAt = Date()
            record.steps[index].summary = "Skipped after an earlier failure."
        }
        records[goalID] = record
        try? await persist(record)
    }

    private func fail(goalID: UUID, message: String) async {
        guard var record = records[goalID], !record.state.isTerminal else { return }
        record.state = .failed
        appendEvent(.failed, message: message, to: &record)
        records[goalID] = record
        try? await persistAndPublish(record)
    }

    private func failPersistence(goalID: UUID) async {
        await fail(
            goalID: goalID,
            message: "Encrypted persistence failed; execution stopped."
        )
    }

    private func finishCancelled(goalID: UUID) async {
        guard var record = records[goalID], !record.state.isTerminal else { return }
        for index in record.steps.indices
        where record.steps[index].state == .running
            || record.steps[index].state == .awaitingApproval
            || record.steps[index].state == .pending
        {
            record.steps[index].state = record.steps[index].state == .pending
                ? .skipped
                : .cancelled
            record.steps[index].completedAt = Date()
        }
        record.state = .cancelled
        appendEvent(.cancelled, message: "Goal cancelled.", to: &record)
        records[goalID] = record
        try? await persistAndPublish(record)
    }

    private func rememberCoveredLowRiskSteps(
        _ numbers: [Int],
        in plan: GoalPlan
    ) {
        for step in plan.steps
        where numbers.contains(step.number) && step.computedRisk == .low {
            AgenticApprovalPreferences.remember(step)
        }
    }

    private func index(of stepNumber: Int, in record: AgenticTaskRecord) -> Int {
        record.steps.firstIndex(where: { $0.number == stepNumber })!
    }

    private func appendEvent(
        _ type: GoalEventType,
        step: Int? = nil,
        message: String,
        to record: inout AgenticTaskRecord
    ) {
        let event = GoalStatusEvent(
            goalID: record.id,
            sequence: (record.events.last?.sequence ?? 0) + 1,
            event: type,
            step: step,
            message: SecretRedactor.redact(message)
        )
        record.events.append(event)
        if record.events.count > Self.maxEvents {
            record.events.removeFirst(record.events.count - Self.maxEvents)
        }
        record.updatedAt = event.emittedAt
    }

    private func persistAndPublish(_ record: AgenticTaskRecord) async throws {
        try await persist(record)
        if let event = record.events.last {
            await statusHandler(event)
        }
    }

    private func persist(_ record: AgenticTaskRecord) async throws {
        try await store.saveAgenticTask(record)
    }

    private static func cappedOutput(
        _ text: String,
        maxBytes: Int = maxRetainedOutputBytes
    ) -> String {
        let data = Data(text.utf8)
        guard data.count > maxBytes else { return text }
        return String(decoding: data.suffix(maxBytes), as: UTF8.self)
    }
}

public enum AgenticApprovalPreferences {
    public static let rememberLowRiskKey =
        "ZenVoice.agenticMode.rememberLowRiskApprovals"
    private static let rememberedPrefix =
        "ZenVoice.agenticMode.rememberedLowRisk."

    public static func remembersLowRisk(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        defaults.bool(forKey: rememberLowRiskKey)
    }

    public static func setRemembersLowRisk(
        _ enabled: Bool,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(enabled, forKey: rememberLowRiskKey)
    }

    public static func isRemembered(
        _ step: GoalStep,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        guard step.computedRisk == .low, remembersLowRisk(defaults: defaults) else {
            return false
        }
        return defaults.bool(forKey: rememberedPrefix + digest(step))
    }

    public static func remember(
        _ step: GoalStep,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        guard step.computedRisk == .low, remembersLowRisk(defaults: defaults) else {
            return
        }
        defaults.set(true, forKey: rememberedPrefix + digest(step))
    }

    private static func digest(_ step: GoalStep) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(step)) ?? Data()
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
