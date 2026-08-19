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
import UserNotifications
import ZenVoiceCore
import ZenVoiceStorage

@MainActor
final class AgenticModeCoordinator {
    private let state: AppState
    private let planner: GoalPlanner
    private let vault: DictationVault
    private var approvalWindowController: AgenticApprovalWindowController?
    private var approvalContinuation:
        CheckedContinuation<ApprovalResponse, Never>?
    private var approvalToken: UUID?
    private var currentGoalID: UUID?
    private var clearStatusTask: Task<Void, Never>?

    private lazy var orchestrator: GoalOrchestrator = {
        let executors: [GoalAgent: any GoalExecutor] = [
            .codex: ProcessGoalExecutor(agent: .codex),
            .claude: ProcessGoalExecutor(agent: .claude),
            .shell: ProcessGoalExecutor(agent: .shell),
            .shortcut: ProcessGoalExecutor(agent: .shortcut),
            .notification: UserNotificationGoalExecutor(),
        ]
        return GoalOrchestrator(
            store: vault,
            executors: executors,
            approvalHandler: { [weak self] plan, version, stepNumber in
                guard let self else {
                    return .decision(
                        ApprovalDecision(
                            planID: plan.id,
                            planSHA256: GoalPlanDigest.sha256(plan),
                            planVersion: version,
                            action: .cancelled
                        )
                    )
                }
                return await self.requestApproval(
                    plan: plan,
                    version: version,
                    stepNumber: stepNumber
                )
            },
            statusHandler: { [weak self] event in
                await self?.apply(event)
            }
        )
    }()

    init(state: AppState, vault: DictationVault) {
        self.state = state
        self.vault = vault
        planner = GoalPlanner(model: FoundationModelsGoalPlanningModel())
    }

    func recoverAfterRelaunch() {
        Task { await orchestrator.recoverAfterRelaunch() }
    }

    /// Returns immediately; planning and any later execution stay asynchronous.
    func handleTranscript(
        _ transcript: String,
        fallbackToText: @escaping @MainActor () -> Void
    ) {
        let command = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if command == "stop" || command == "cancel"
            || command == "stop goal" || command == "cancel goal"
        {
            cancelActiveGoal()
            return
        }

        let planningID = UUID()
        clearStatusTask?.cancel()
        state.agenticGoalTitle = "Planning spoken goal"
        state.agenticStatusEvent = GoalStatusEvent(
            goalID: planningID,
            sequence: 1,
            event: .goalStarted,
            message: "Building a local plan…"
        )
        state.isAgenticGoalActive = true

        Task { [weak self] in
            guard let self else { return }
            let result = await planner.plan(transcript: transcript)
            switch result {
            case .plan(let plan, _):
                do {
                    state.agenticGoalTitle = plan.title
                    currentGoalID = try await orchestrator.submit(plan)
                } catch {
                    state.isAgenticGoalActive = false
                    state.agenticStatusEvent = GoalStatusEvent(
                        goalID: planningID,
                        sequence: 2,
                        event: .failed,
                        message: error.localizedDescription
                    )
                    scheduleStatusClear()
                    fallbackToText()
                }
            case .notGoal:
                state.isAgenticGoalActive = false
                state.agenticGoalTitle = nil
                state.agenticStatusEvent = nil
                fallbackToText()
            }
        }
    }

    func cancelActiveGoal() {
        if approvalContinuation != nil,
           let plan = approvalWindowController
        {
            plan.close()
        }
        Task { await orchestrator.cancelActiveGoal() }
    }

    private func requestApproval(
        plan: GoalPlan,
        version: Int,
        stepNumber: Int?
    ) async -> ApprovalResponse {
        await withCheckedContinuation { continuation in
            let token = UUID()
            approvalToken = token
            approvalContinuation = continuation
            let controller = AgenticApprovalWindowController(
                plan: plan,
                planVersion: version,
                stepNumber: stepNumber,
                onResponse: { [weak self] response in
                    self?.resolveApproval(token: token, response: response)
                },
                onClosed: { [weak self] in
                    self?.resolveApproval(
                        token: token,
                        response: .decision(
                            ApprovalDecision(
                                planID: plan.id,
                                planSHA256: GoalPlanDigest.sha256(plan),
                                planVersion: version,
                                action: .cancelled
                            )
                        )
                    )
                }
            )
            approvalWindowController = controller
            controller.present()
        }
    }

    private func resolveApproval(
        token: UUID,
        response: ApprovalResponse
    ) {
        guard approvalToken == token,
              let continuation = approvalContinuation
        else {
            return
        }
        approvalToken = nil
        approvalContinuation = nil
        approvalWindowController?.close()
        approvalWindowController = nil
        continuation.resume(returning: response)
    }

    private func apply(_ event: GoalStatusEvent) {
        clearStatusTask?.cancel()
        currentGoalID = event.goalID
        state.agenticStatusEvent = event
        switch event.event {
        case .succeeded, .failed, .cancelled, .interrupted:
            state.isAgenticGoalActive = false
            scheduleStatusClear()
        default:
            state.isAgenticGoalActive = true
        }
    }

    private func scheduleStatusClear() {
        clearStatusTask?.cancel()
        clearStatusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self else { return }
            state.agenticStatusEvent = nil
            state.agenticGoalTitle = nil
        }
    }
}

private actor UserNotificationGoalExecutor: GoalExecutor {
    func run(
        step: GoalStep,
        output: @escaping @Sendable (ExecutorOutput) async -> Void
    ) async -> ExecutorOutcome {
        do {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            }
            let content = UNMutableNotificationContent()
            content.title = "ZenVoice goal complete"
            content.body = step.command
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            try await center.add(request)
            await output(
                ExecutorOutput(
                    channel: .stdout,
                    text: "Notification delivered."
                )
            )
            return ExecutorOutcome(
                exitStatus: 0,
                summary: "Notification delivered."
            )
        } catch {
            return ExecutorOutcome(
                exitStatus: 1,
                summary: "Notification failed: \(error.localizedDescription)"
            )
        }
    }

    func cancel() async {}
}
