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
import ZenVoiceCore

actor AgenticCheckStore: GoalRecordPersisting {
    private var records: [UUID: AgenticTaskRecord] = [:]

    func saveAgenticTask(_ record: AgenticTaskRecord) async throws {
        records[record.id] = record
    }

    func loadActiveAgenticTasks() async throws -> [AgenticTaskRecord] {
        records.values.filter { !$0.state.isTerminal }
    }

    func record(_ id: UUID) -> AgenticTaskRecord? {
        records[id]
    }
}

enum AgenticCheckBehavior: Sendable {
    case success(String)
    case failure
    case slow
}

actor AgenticCheckExecutor: GoalExecutor {
    private let behavior: AgenticCheckBehavior
    private var cancellationRequested = false

    init(_ behavior: AgenticCheckBehavior) {
        self.behavior = behavior
    }

    func run(
        step: GoalStep,
        output: @escaping @Sendable (ExecutorOutput) async -> Void
    ) async -> ExecutorOutcome {
        switch behavior {
        case .success(let text):
            await output(ExecutorOutput(channel: .stdout, text: text))
            return ExecutorOutcome(exitStatus: 0, summary: "done")
        case .failure:
            return ExecutorOutcome(exitStatus: 1, summary: "expected failure")
        case .slow:
            for _ in 0..<100 {
                if cancellationRequested {
                    return ExecutorOutcome(
                        exitStatus: 15,
                        summary: "cancelled",
                        cancelled: true
                    )
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return ExecutorOutcome(exitStatus: 0, summary: "finished")
        }
    }

    func cancel() async {
        cancellationRequested = true
    }
}

@Sendable
func agenticDecision(
    plan: GoalPlan,
    version: Int,
    stepNumber: Int?
) -> ApprovalResponse {
    let covered: [Int]
    let mode: ApprovalMode
    if let stepNumber {
        covered = [stepNumber]
        mode = .perStep
    } else if let firstHigh = plan.steps.firstIndex(where: {
        $0.computedRisk == .high
    }) {
        covered = plan.steps.prefix(firstHigh).map(\.number)
        mode = .upToNextHighRisk
    } else {
        covered = plan.steps.map(\.number)
        mode = .all
    }
    return .decision(
        ApprovalDecision(
            planID: plan.id,
            planSHA256: GoalPlanDigest.sha256(plan),
            planVersion: version,
            action: .approved,
            mode: mode,
            coveredStepNumbers: covered
        )
    )
}

func waitForAgenticRecord(
    _ id: UUID,
    in store: AgenticCheckStore,
    matching predicate: @escaping (AgenticTaskRecord) -> Bool
) async -> AgenticTaskRecord? {
    for _ in 0..<300 {
        if let record = await store.record(id), predicate(record) {
            return record
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return nil
}

func runAgenticPreferenceChecks() {
    let defaults = UserDefaults(
        suiteName: "com.zenvoice.app.agentic-checks"
    )!
    defaults.removePersistentDomain(
        forName: "com.zenvoice.app.agentic-checks"
    )

    guard !AgenticModePreferences.isEnabled(defaults: defaults),
          !AgenticModePreferences.isEffectivelyEnabled(defaults: defaults)
    else {
        failEngineCheck("Agentic Mode was not off by default")
    }

    AgenticModePreferences.setEnabled(true, defaults: defaults)
    guard AgenticModePreferences.isEffectivelyEnabled(defaults: defaults),
          CommandModePreferences.isEnabled(defaults: defaults) else {
        failEngineCheck("enabling Agentic Mode did not enable Command Mode")
    }

    // Command Mode is the gate the agentic path extends: switching it off must
    // neutralise Agentic Mode without needing a second write anywhere.
    CommandModePreferences.setEnabled(false, defaults: defaults)
    guard !AgenticModePreferences.isEffectivelyEnabled(defaults: defaults) else {
        failEngineCheck("Agentic Mode stayed live after Command Mode was off")
    }

    guard !AgenticApprovalPreferences.remembersLowRisk(defaults: defaults) else {
        failEngineCheck("low-risk approval memory was not off by default")
    }
    let lowRiskStep = GoalStep(
        number: 1,
        agent: .shell,
        command: "git status",
        description: "Status",
        plannedRisk: .low,
        computedRisk: .low
    )
    AgenticApprovalPreferences.remember(lowRiskStep, defaults: defaults)
    guard !AgenticApprovalPreferences.isRemembered(
        lowRiskStep,
        defaults: defaults
    ) else {
        failEngineCheck("a step was remembered while the memory switch was off")
    }

    AgenticApprovalPreferences.setRemembersLowRisk(true, defaults: defaults)
    AgenticApprovalPreferences.remember(lowRiskStep, defaults: defaults)
    guard AgenticApprovalPreferences.isRemembered(
        lowRiskStep,
        defaults: defaults
    ) else {
        failEngineCheck("an approved low-risk step was not remembered")
    }

    var editedStep = lowRiskStep
    editedStep.command = "git status --short"
    guard !AgenticApprovalPreferences.isRemembered(
        editedStep,
        defaults: defaults
    ) else {
        failEngineCheck("a changed command reused a remembered approval")
    }

    let highRiskStep = GoalStep(
        number: 1,
        agent: .shell,
        command: "git push origin main",
        description: "Push",
        plannedRisk: .high,
        computedRisk: .high
    )
    AgenticApprovalPreferences.remember(highRiskStep, defaults: defaults)
    guard !AgenticApprovalPreferences.isRemembered(
        highRiskStep,
        defaults: defaults
    ) else {
        failEngineCheck("a high-risk step was remembered")
    }

    defaults.removePersistentDomain(
        forName: "com.zenvoice.app.agentic-checks"
    )
    print("ZenVoiceCoreChecks: agentic preferences passed")
}

func runAgenticChecks() async {
    runAgenticPreferenceChecks()

    let plannerResult = await GoalPlanner().plan(
        transcript: "Open Codex in the ZenVoice project, run core checks, fix obvious failures, and notify me when done"
    )
    guard case .plan(let deterministicPlan, let source) = plannerResult,
          source == "deterministic",
          deterministicPlan.steps.count == 3,
          deterministicPlan.steps.map(\.agent) == [.codex, .codex, .notification],
          deterministicPlan.steps[2].dependsOn == [2]
    else {
        failEngineCheck("deterministic agentic planner did not build the expected plan")
    }

    let redacted = SecretRedactor.redact(
        "Authorization: Bearer abcdefghijklmnopqrstuvwxyz and sk-abcdefghijklmnop"
    )
    guard !redacted.contains("abcdefghijklmnopqrstuvwxyz"),
          !redacted.contains("sk-abcdefghijklmnop") else {
        failEngineCheck("agentic output secret redaction failed")
    }

    let allowedRoot = URL(fileURLWithPath: "/tmp/zenvoice-agentic-root")
    let strictValidator = PlanValidator(allowedRoot: allowedRoot)
    do {
        _ = try strictValidator.validate(
            GoalPlan(
                title: "Prefix escape",
                transcript: "test prefix containment",
                steps: [
                    GoalStep(
                        number: 1,
                        agent: .shell,
                        command: "pwd",
                        description: "Read directory",
                        workingDirectory: "/tmp/zenvoice-agentic-root-escape"
                    ),
                ]
            )
        )
        failEngineCheck("path-prefix sibling escaped the agentic allowed root")
    } catch PlanValidationError.workingDirectoryNotAllowed { }
    catch {
        failEngineCheck("unexpected path policy error: \(error)")
    }

    let successStore = AgenticCheckStore()
    let successExecutor = AgenticCheckExecutor(
        .success("token=super-secret-value\ncompleted")
    )
    let successOrchestrator = GoalOrchestrator(
        validator: strictValidator,
        store: successStore,
        executors: [
            .codex: successExecutor,
            .notification: AgenticCheckExecutor(.success("notified")),
        ],
        approvalHandler: agenticDecision,
        statusHandler: { _ in }
    )
    let successPlan = GoalPlan(
        title: "Check and notify",
        transcript: "run checks and notify me",
        steps: [
            GoalStep(
                number: 1,
                agent: .codex,
                command: "Run focused checks.",
                description: "Run focused checks",
                workingDirectory: allowedRoot.path,
                plannedRisk: .medium
            ),
            GoalStep(
                number: 2,
                agent: .notification,
                command: "Checks completed",
                description: "Notify",
                dependsOn: [1]
            ),
        ]
    )
    let successID: UUID
    do {
        successID = try await successOrchestrator.submit(successPlan)
    } catch {
        failEngineCheck("agentic success plan could not be submitted: \(error)")
    }
    guard let successRecord = await waitForAgenticRecord(
        successID,
        in: successStore,
        matching: { $0.state == .succeeded }
    ) else {
        failEngineCheck("agentic success plan did not reach succeeded")
    }
    guard successRecord.steps.map(\.state) == [.succeeded, .succeeded],
          successRecord.events.map(\.sequence)
            == successRecord.events.map(\.sequence).sorted(),
          successRecord.steps[0].retainedOutput.contains("[REDACTED]"),
          !successRecord.steps[0].retainedOutput.contains("super-secret-value")
    else {
        failEngineCheck("agentic success record lost ordering or redaction")
    }

    let highStore = AgenticCheckStore()
    let approvalCounter = AgenticApprovalCounter()
    let highOrchestrator = GoalOrchestrator(
        validator: strictValidator,
        store: highStore,
        executors: [
            .codex: AgenticCheckExecutor(.success("deployed")),
        ],
        approvalHandler: { plan, version, stepNumber in
            await approvalCounter.increment()
            return agenticDecision(
                plan: plan,
                version: version,
                stepNumber: stepNumber
            )
        },
        statusHandler: { _ in }
    )
    let highPlan = GoalPlan(
        title: "Push",
        transcript: "push to production",
        steps: [
            GoalStep(
                number: 1,
                agent: .codex,
                command: "Push the reviewed change to production.",
                description: "Push change",
                workingDirectory: allowedRoot.path,
                plannedRisk: .high
            ),
        ]
    )
    let highID: UUID
    do {
        highID = try await highOrchestrator.submit(highPlan)
    } catch {
        failEngineCheck("high-risk plan could not be submitted: \(error)")
    }
    guard await waitForAgenticRecord(
        highID,
        in: highStore,
        matching: { $0.state == .succeeded }
    ) != nil,
          await approvalCounter.value() == 2
    else {
        failEngineCheck("high-risk step did not require a separate approval")
    }

    let failureStore = AgenticCheckStore()
    let failureOrchestrator = GoalOrchestrator(
        validator: strictValidator,
        store: failureStore,
        executors: [
            .codex: AgenticCheckExecutor(.failure),
            .notification: AgenticCheckExecutor(.success("should not run")),
        ],
        approvalHandler: agenticDecision,
        statusHandler: { _ in }
    )
    let failureID: UUID
    do {
        failureID = try await failureOrchestrator.submit(successPlan)
    } catch {
        failEngineCheck("failure plan could not be submitted: \(error)")
    }
    guard let failureRecord = await waitForAgenticRecord(
        failureID,
        in: failureStore,
        matching: { $0.state == .failed }
    ), failureRecord.steps.map(\.state) == [.failed, .skipped]
    else {
        failEngineCheck("agentic failure did not halt and skip dependents")
    }

    let cancelStore = AgenticCheckStore()
    let slowExecutor = AgenticCheckExecutor(.slow)
    let cancelOrchestrator = GoalOrchestrator(
        validator: strictValidator,
        store: cancelStore,
        executors: [.codex: slowExecutor],
        approvalHandler: agenticDecision,
        statusHandler: { _ in }
    )
    let cancelID: UUID
    do {
        cancelID = try await cancelOrchestrator.submit(
            GoalPlan(
                title: "Slow",
                transcript: "run a slow check",
                steps: [
                    GoalStep(
                        number: 1,
                        agent: .codex,
                        command: "Run the slow check.",
                        description: "Slow check",
                        workingDirectory: allowedRoot.path,
                        plannedRisk: .medium
                    ),
                ]
            )
        )
    } catch {
        failEngineCheck("cancel plan could not be submitted: \(error)")
    }
    guard await waitForAgenticRecord(
        cancelID,
        in: cancelStore,
        matching: { $0.steps.first?.state == .running }
    ) != nil else {
        failEngineCheck("cancel plan never began running")
    }
    await cancelOrchestrator.cancel(goalID: cancelID)
    guard let cancelled = await waitForAgenticRecord(
        cancelID,
        in: cancelStore,
        matching: { $0.state == .cancelled }
    ), cancelled.events.contains(where: { $0.event == .cancelling }),
       cancelled.events.last?.event == .cancelled
    else {
        failEngineCheck("agentic cancellation was not visible and terminal")
    }

    print("ZenVoiceCoreChecks: agentic orchestration passed")

    await runProcessExecutorChecks()
}

/// Exercises the real `Process` adapter. Only the `shell` agent is used: the
/// Codex and Claude adapters share this code path, and running them here would
/// spend the user's model quota to learn nothing extra about the executor.
func runProcessExecutorChecks() async {
    let executor = ProcessGoalExecutor(agent: .shell)
    let collector = AgenticOutputCollector()
    let echoOutcome = await executor.run(
        step: GoalStep(
            number: 1,
            agent: .shell,
            command: "echo agentic-executor-live",
            description: "Echo",
            workingDirectory: FileManager.default.temporaryDirectory.path,
            timeoutSeconds: 30
        )
    ) { chunk in
        await collector.append(chunk.text)
    }
    guard echoOutcome.succeeded,
          echoOutcome.exitStatus == 0,
          await collector.text().contains("agentic-executor-live")
    else {
        failEngineCheck("real shell step did not succeed and stream output")
    }

    let failOutcome = await executor.run(
        step: GoalStep(
            number: 1,
            agent: .shell,
            command: "exit 3",
            description: "Fail",
            workingDirectory: FileManager.default.temporaryDirectory.path,
            timeoutSeconds: 30
        )
    ) { _ in }
    guard !failOutcome.succeeded, failOutcome.exitStatus == 3 else {
        failEngineCheck("non-zero shell exit was not reported as failure")
    }

    let timeoutStart = Date()
    let timeoutOutcome = await executor.run(
        step: GoalStep(
            number: 1,
            agent: .shell,
            command: "sleep 30",
            description: "Sleep",
            workingDirectory: FileManager.default.temporaryDirectory.path,
            timeoutSeconds: 1
        )
    ) { _ in }
    let timeoutElapsed = Date().timeIntervalSince(timeoutStart)
    guard timeoutOutcome.timedOut,
          !timeoutOutcome.succeeded,
          timeoutElapsed < 10
    else {
        failEngineCheck(
            "shell step timeout was not enforced (elapsed \(timeoutElapsed)s)"
        )
    }

    let cancelExecutor = ProcessGoalExecutor(agent: .shell)
    let cancelStep = GoalStep(
        number: 1,
        agent: .shell,
        command: "sleep 30 & wait",
        description: "Sleep with child",
        workingDirectory: FileManager.default.temporaryDirectory.path,
        timeoutSeconds: 120
    )
    let cancelStart = Date()
    async let cancelOutcome = cancelExecutor.run(step: cancelStep) { _ in }
    try? await Task.sleep(for: .milliseconds(400))
    await cancelExecutor.cancel()
    let resolvedCancel = await cancelOutcome
    let cancelElapsed = Date().timeIntervalSince(cancelStart)
    guard resolvedCancel.cancelled,
          !resolvedCancel.succeeded,
          cancelElapsed < 10
    else {
        failEngineCheck(
            "cancelling a running shell step did not stop it promptly "
            + "(elapsed \(cancelElapsed)s)"
        )
    }

    let missingAgent = await ProcessGoalExecutor(agent: .codex).run(
        step: GoalStep(
            number: 1,
            agent: .shell,
            command: "echo mismatch",
            description: "Mismatch",
            timeoutSeconds: 30
        )
    ) { _ in }
    guard !missingAgent.succeeded, missingAgent.exitStatus == 64 else {
        failEngineCheck("executor accepted a step for a different agent")
    }

    print("ZenVoiceCoreChecks: agentic process executor passed")
}

actor AgenticOutputCollector {
    private var buffer = ""

    func append(_ text: String) {
        buffer += text
    }

    func text() -> String {
        buffer
    }
}

actor AgenticApprovalCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}
