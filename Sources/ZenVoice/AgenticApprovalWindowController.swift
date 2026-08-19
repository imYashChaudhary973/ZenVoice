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

import AppKit
import SwiftUI
import ZenVoiceCore

@MainActor
final class AgenticApprovalWindowController: NSWindowController,
    NSWindowDelegate
{
    private let onClosed: () -> Void

    init(
        plan: GoalPlan,
        planVersion: Int,
        stepNumber: Int?,
        onResponse: @escaping (ApprovalResponse) -> Void,
        onClosed: @escaping () -> Void
    ) {
        self.onClosed = onClosed
        let content = AgenticApprovalView(
            plan: plan,
            planVersion: planVersion,
            stepNumber: stepNumber,
            onResponse: onResponse
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 610),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = stepNumber == nil
            ? "Review Agentic Goal"
            : "Approve High-Risk Step"
        window.minSize = NSSize(width: 620, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentViewController = NSHostingController(rootView: content)
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClosed()
    }
}

private struct AgenticApprovalView: View {
    let plan: GoalPlan
    let planVersion: Int
    let stepNumber: Int?
    let onResponse: (ApprovalResponse) -> Void

    @State private var isEditing = false
    @State private var draftSteps: [GoalStep]

    init(
        plan: GoalPlan,
        planVersion: Int,
        stepNumber: Int?,
        onResponse: @escaping (ApprovalResponse) -> Void
    ) {
        self.plan = plan
        self.planVersion = planVersion
        self.stepNumber = stepNumber
        self.onResponse = onResponse
        _draftSteps = State(initialValue: plan.steps)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(ZenDesign.Semantic.border)
            ScrollView {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                    if stepNumber == nil {
                        Text("Spoken goal")
                            .font(ZenDesign.Typography.captionStrong)
                            .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        Text(plan.transcript)
                            .font(ZenDesign.Typography.body)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            .textSelection(.enabled)
                    }

                    ForEach(displayedIndices, id: \.self) { index in
                        stepCard(index: index)
                    }
                }
                .padding(ZenDesign.Spacing.lg)
            }
            Divider().overlay(ZenDesign.Semantic.border)
            actions
        }
        .frame(minWidth: 620, minHeight: 480)
        .background(ZenDesign.Semantic.canvas)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: ZenDesign.Spacing.md) {
            Image(systemName: stepNumber == nil ? "checklist" : "exclamationmark.shield.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(
                    stepNumber == nil
                        ? ZenDesign.Semantic.accent
                        : ZenDesign.Semantic.warn
                )
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(stepNumber == nil ? plan.title : "Review step \(stepNumber!)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(
                    stepNumber == nil
                        ? "Nothing runs until you approve these exact steps."
                        : "This step is high risk and is never approved by a previous plan decision."
                )
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
            }
            Spacer()
            Text("PLAN v\(planVersion)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
        }
        .padding(ZenDesign.Spacing.lg)
    }

    private var displayedIndices: [Int] {
        if let stepNumber,
           let index = draftSteps.firstIndex(where: { $0.number == stepNumber }) {
            return [index]
        }
        return Array(draftSteps.indices)
    }

    private func stepCard(index: Int) -> some View {
        let step = draftSteps[index]
        return VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
            HStack(spacing: ZenDesign.Spacing.sm) {
                Text("\(step.number)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(ZenDesign.Semantic.canvas)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(ZenDesign.Semantic.textPrimary))
                Text(step.agent.displayName)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Spacer()
                riskBadge(step.computedRisk)
            }

            if isEditing {
                TextField(
                    "Visible description",
                    text: $draftSteps[index].description
                )
                .textFieldStyle(.roundedBorder)
                TextEditor(text: $draftSteps[index].command)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 72)
                    .padding(6)
                    .background(ZenDesign.Semantic.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                TextField(
                    "Working directory",
                    text: Binding(
                        get: { draftSteps[index].workingDirectory ?? "" },
                        set: {
                            draftSteps[index].workingDirectory = $0.isEmpty
                                ? nil
                                : $0
                        }
                    )
                )
                .textFieldStyle(.roundedBorder)
            } else {
                Text(step.description)
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(step.command)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .textSelection(.enabled)
                    .padding(ZenDesign.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ZenDesign.Semantic.surfaceSunken)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if let directory = step.workingDirectory {
                    Label(directory, systemImage: "folder")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .textSelection(.enabled)
                }
                if !step.dependsOn.isEmpty {
                    Text("Depends on: \(step.dependsOn.map(String.init).joined(separator: ", "))")
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
            }
        }
        .padding(ZenDesign.Spacing.md)
        .background(ZenDesign.Semantic.surface)
        .clipShape(RoundedRectangle(cornerRadius: ZenDesign.Radius.large))
        .overlay {
            RoundedRectangle(cornerRadius: ZenDesign.Radius.large)
                .strokeBorder(ZenDesign.Semantic.border, lineWidth: 1)
        }
    }

    private var actions: some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            Button("Reject") {
                onResponse(.decision(decision(action: .rejected)))
            }
            .buttonStyle(ZenSecondaryButtonStyle())
            .keyboardShortcut(.cancelAction)

            if stepNumber == nil {
                Button(isEditing ? "Cancel edit" : "Edit Plan") {
                    if isEditing {
                        draftSteps = plan.steps
                    }
                    isEditing.toggle()
                }
                .buttonStyle(ZenSecondaryButtonStyle())
            }

            Spacer()

            if isEditing {
                Button("Review changes") {
                    var edited = plan
                    edited.steps = draftSteps
                    onResponse(.edited(edited))
                }
                .buttonStyle(ZenPrimaryButtonStyle())
                .disabled(draftSteps.contains {
                    $0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                })
            } else if let stepNumber {
                Button("Approve this step") {
                    onResponse(
                        .decision(
                            decision(
                                action: .approved,
                                mode: .perStep,
                                covered: [stepNumber]
                            )
                        )
                    )
                }
                .buttonStyle(ZenPrimaryButtonStyle())
            } else {
                Button("Step by step") {
                    onResponse(
                        .decision(
                            decision(
                                action: .approved,
                                mode: .perStep,
                                covered: firstStepByStepCoverage
                            )
                        )
                    )
                }
                .buttonStyle(ZenSecondaryButtonStyle())

                Button(primaryApprovalTitle) {
                    onResponse(
                        .decision(
                            decision(
                                action: .approved,
                                mode: primaryApprovalMode,
                                covered: primaryCoveredSteps
                            )
                        )
                    )
                }
                .buttonStyle(ZenPrimaryButtonStyle())
            }
        }
        .padding(ZenDesign.Spacing.md)
        .background(ZenDesign.Semantic.surface)
    }

    private var firstStepByStepCoverage: [Int] {
        guard let first = plan.steps.first, first.computedRisk != .high else {
            return []
        }
        return [first.number]
    }

    private var primaryCoveredSteps: [Int] {
        guard let firstHigh = plan.steps.firstIndex(where: {
            $0.computedRisk == .high
        }) else {
            return plan.steps.map(\.number)
        }
        return plan.steps.prefix(firstHigh).map(\.number)
    }

    private var primaryApprovalMode: ApprovalMode {
        plan.steps.contains(where: { $0.computedRisk == .high })
            ? .upToNextHighRisk
            : .all
    }

    private var primaryApprovalTitle: String {
        if let firstHigh = plan.steps.first(where: { $0.computedRisk == .high }) {
            return firstHigh.number == 1
                ? "Continue to high-risk review"
                : "Run until step \(firstHigh.number)"
        }
        return "Approve all steps"
    }

    private func decision(
        action: ApprovalAction,
        mode: ApprovalMode? = nil,
        covered: [Int] = []
    ) -> ApprovalDecision {
        ApprovalDecision(
            planID: plan.id,
            planSHA256: GoalPlanDigest.sha256(plan),
            planVersion: planVersion,
            action: action,
            mode: mode,
            coveredStepNumbers: covered
        )
    }

    private func riskBadge(_ risk: RiskLevel) -> some View {
        Text(risk.rawValue.uppercased())
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(riskColor(risk))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(riskColor(risk).opacity(0.12))
            .clipShape(Capsule())
    }

    private func riskColor(_ risk: RiskLevel) -> Color {
        switch risk {
        case .low:
            return ZenDesign.Semantic.success
        case .medium:
            return ZenDesign.Semantic.warn
        case .high:
            return ZenDesign.Semantic.danger
        }
    }
}
