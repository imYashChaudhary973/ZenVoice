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

/// Why a plan was rejected by the validator.
///
/// The cases are intentionally broad enough to surface to the user without
/// exposing secret-shaped content.
public enum PlanValidationError: LocalizedError, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case missingTitle
    case emptyPlan
    case stepNumberOutOfRange(Int)
    case duplicateStepNumber(Int)
    case nonContiguousStepNumbers
    case agentNotWhitelisted(String)
    case emptyCommand(step: Int)
    case invalidDependency(step: Int, dependency: Int)
    case orphanedNotificationStep(step: Int)
    case workingDirectoryNotAllowed(step: Int, path: String)
    case secretDetected(field: String)
    case timeoutOutOfRange(step: Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Plan schema version \(version) is not supported."
        case .missingTitle:
            return "Plan has no title."
        case .emptyPlan:
            return "Plan contains no steps."
        case .stepNumberOutOfRange(let step):
            return "Step \(step) is outside the allowed 1–12 range."
        case .duplicateStepNumber(let step):
            return "Step number \(step) appears more than once."
        case .nonContiguousStepNumbers:
            return "Step numbers must be contiguous 1…n."
        case .agentNotWhitelisted(let agent):
            return "Unknown agent '\(agent)'."
        case .emptyCommand(let step):
            return "Step \(step) has an empty command."
        case .invalidDependency(let step, let dependency):
            return "Step \(step) depends on step \(dependency), which is not an earlier step in this plan."
        case .orphanedNotificationStep(let step):
            return "Notification step \(step) must depend on at least one step or be the only step."
        case .workingDirectoryNotAllowed(let step, let path):
            return "Step \(step) working directory '\(path)' is outside the allowed root."
        case .secretDetected(let field):
            return "Plan contains a secret-shaped value in '\(field)'."
        case .timeoutOutOfRange(let step):
            return "Step \(step) timeout is outside the allowed 1–7200 s range."
        }
    }
}

/// Validates and re-risks plans produced by the planner tiers.
///
/// The validator is deterministic, local, and testable. It never touches the
/// network or spawns processes. On success it returns a copy of the plan with
/// `computedRisk` overwritten; on failure it returns a typed error and a
/// one-line reason suitable for the fail-toward-text fallback.
public struct PlanValidator: Sendable {
    /// Maximum steps allowed in a plan.
    public static let maxSteps = 12

    /// Default allowed working-directory root.
    private let allowedRoot: URL

    /// Creates a validator with the given allowed working-directory root.
    ///
    /// The default is `~/Developer` as pinned in the design doc (U5). Tests
    /// pass a temporary directory.
    public init(allowedRoot: URL? = nil) {
        if let allowedRoot {
            self.allowedRoot = allowedRoot
                .standardizedFileURL
                .resolvingSymlinksInPath()
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.allowedRoot = home
                .appendingPathComponent("Developer", isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
        }
    }

    /// Validates the plan and returns a copy with computed risks set.
    public func validate(_ plan: GoalPlan) throws -> GoalPlan {
        guard plan.schemaVersion == 1 else {
            throw PlanValidationError.unsupportedSchemaVersion(plan.schemaVersion)
        }
        guard !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlanValidationError.missingTitle
        }
        guard !plan.steps.isEmpty else {
            throw PlanValidationError.emptyPlan
        }
        guard plan.steps.count <= Self.maxSteps else {
            throw PlanValidationError.stepNumberOutOfRange(plan.steps.count)
        }

        var validated = plan
        try validateStepNumbers(steps: validated.steps)
        try validateAgents(steps: validated.steps)
        try validateCommands(steps: validated.steps)
        try validateTimeouts(steps: validated.steps)
        try validateSecrets(plan: validated)
        try validateWorkingDirectories(steps: validated.steps)
        try validateDependencies(steps: validated.steps)
        validated.steps = validated.steps.map { step in
            var copy = step
            copy.computedRisk = Self.recomputedRisk(for: step, allowedRoot: allowedRoot)
            return copy
        }
        return validated
    }

    /// A human-readable fallback reason for a rejected plan.
    public static func fallbackReason(for error: PlanValidationError) -> String {
        "ZenVoice could not turn that command into a safe plan: "
            + (error.errorDescription ?? "validation failed")
    }

    // MARK: - Schema gates

    private func validateStepNumbers(steps: [GoalStep]) throws {
        var seen = Set<Int>()
        for step in steps {
            guard step.number >= 1, step.number <= Self.maxSteps else {
                throw PlanValidationError.stepNumberOutOfRange(step.number)
            }
            guard !seen.contains(step.number) else {
                throw PlanValidationError.duplicateStepNumber(step.number)
            }
            seen.insert(step.number)
        }
        let sorted = steps.map(\.number).sorted()
        for (index, number) in sorted.enumerated() {
            guard number == index + 1 else {
                throw PlanValidationError.nonContiguousStepNumbers
            }
        }
    }

    private func validateAgents(steps: [GoalStep]) throws {
        for step in steps {
            guard GoalAgent(rawValue: step.agent.rawValue) != nil else {
                throw PlanValidationError.agentNotWhitelisted(step.agent.rawValue)
            }
        }
    }

    private func validateCommands(steps: [GoalStep]) throws {
        for step in steps {
            guard !step.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PlanValidationError.emptyCommand(step: step.number)
            }
        }
    }

    private func validateTimeouts(steps: [GoalStep]) throws {
        for step in steps {
            guard step.timeoutSeconds >= 1, step.timeoutSeconds <= 7200 else {
                throw PlanValidationError.timeoutOutOfRange(step: step.number)
            }
        }
    }

    // MARK: - Secret scan

    private func validateSecrets(plan: GoalPlan) throws {
        let candidates: [(String, String)] = [
            ("title", plan.title),
            ("transcript", plan.transcript),
        ] + plan.steps.enumerated().flatMap { index, step in
            [
                ("step \(index + 1) command", step.command),
                ("step \(index + 1) description", step.description),
                ("step \(index + 1) workingDirectory", step.workingDirectory ?? ""),
            ]
        }
        for (field, value) in candidates {
            guard !value.isEmpty else { continue }
            if Self.containsSecretShape(value) {
                throw PlanValidationError.secretDetected(field: field)
            }
        }
    }

    static func containsSecretShape(_ text: String) -> Bool {
        // AWS access key ID
        if text.range(of: #"\bAKIA[0-9A-Z]{16}\b"#, options: .regularExpression) != nil {
            return true
        }
        // OpenAI / common sk- keys
        if text.range(of: #"\bsk-[a-zA-Z0-9]{20,}"#, options: .regularExpression) != nil {
            return true
        }
        // key= / token= / api_key= assignments (best-effort)
        if text.range(
            of: #"(?i)(api[_-]?key|token|secret|password)\s*[:=]\s*[^\s'\"]{8,}"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        // Long base64 or hex runs (32+ chars)
        if text.range(
            of: #"\b[a-zA-Z0-9+/]{40,}={0,2}\b|\b[0-9a-fA-F]{32,}\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        return false
    }

    // MARK: - Path policy

    private func validateWorkingDirectories(steps: [GoalStep]) throws {
        for step in steps {
            guard let raw = step.workingDirectory else { continue }
            let standardized = URL(
                fileURLWithPath: Self.expandTilde(raw),
                isDirectory: true
            ).standardizedFileURL.resolvingSymlinksInPath()
            guard Self.isContained(standardized, by: allowedRoot) else {
                throw PlanValidationError.workingDirectoryNotAllowed(
                    step: step.number,
                    path: raw
                )
            }
        }
    }

    static func expandTilde(_ path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == "~" { return home }
        return home + path.dropFirst()
    }

    private static func isContained(_ url: URL, by root: URL) -> Bool {
        let candidate = url.standardizedFileURL.pathComponents
        let allowed = root.standardizedFileURL.pathComponents
        return candidate.count >= allowed.count
            && candidate.prefix(allowed.count).elementsEqual(allowed)
    }

    // MARK: - Dependency lint

    /// The orchestrator executes steps in array order, and step numbers are
    /// contiguous, so a dependency on a *later* step is unsatisfiable: the
    /// earlier step would be skipped for a dependency that has not run yet.
    /// The planner prompt already requires earlier-numbered dependencies;
    /// this rejects edited or model-produced plans that violate it instead of
    /// silently skipping steps.
    private func validateDependencies(steps: [GoalStep]) throws {
        let numbers = Set(steps.map(\.number))
        for step in steps {
            for dependency in step.dependsOn {
                guard numbers.contains(dependency),
                      dependency < step.number else {
                    throw PlanValidationError.invalidDependency(
                        step: step.number,
                        dependency: dependency
                    )
                }
            }
        }
        // A cycle needs at least one forward edge, so the rule above makes
        // circular dependencies structurally impossible rather than merely
        // detected.

        for step in steps where step.agent == .notification {
            let onlyStep = steps.count == 1
            let hasDependency = !step.dependsOn.isEmpty
            guard onlyStep || hasDependency else {
                throw PlanValidationError.orphanedNotificationStep(step: step.number)
            }
        }
    }

    // MARK: - Risk recomputation

    /// Recomputes risk from the command surface. The planner's `plannedRisk`
    /// is ignored.
    public static func recomputedRisk(for step: GoalStep, allowedRoot: URL) -> RiskLevel {
        switch step.agent {
        case .notification:
            return .low
        case .shortcut:
            return .medium
        case .codex, .claude:
            return mediumOrHigherIfDangerous(step.command)
        case .shell:
            return shellRisk(step.command, workingDirectory: step.workingDirectory, allowedRoot: allowedRoot)
        }
    }

    private static func shellRisk(
        _ command: String,
        workingDirectory: String?,
        allowedRoot: URL
    ) -> RiskLevel {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // App launch is visible but non-destructive, matching v1's "open app" phrase.
        if lower == "open -a" || lower.hasPrefix("open -a ") {
            return .low
        }

        // A read-only classification is only available to commands with no
        // shell control surface at all. Any separator (`;`, `&&`, `|`), any
        // substitution (`$`, backtick), or any redirection (`<`, `>`) can turn
        // a read-only prefix into a write or an execution of something else,
        // so "ls; rm -rf x" and "cat f > g" must never classify as low.
        let hasControlSurface = trimmed.contains(where: { character in
            ";|&<>`$".contains(character) || character.isNewline
        })

        // Known read-only / report-only prefixes, matched on whole words so
        // "pwdx" is not "pwd".
        let readOnlyPrefixes = [
            "ls ", "ls\t", "cat ", "cat\t", "pwd", "echo ", "echo\t",
            "find ", "find\t", "grep ", "grep\t", "git status", "git log",
            "git diff", "git branch", "git show", "git remote -v",
        ]
        let isReadOnlyPrefix = readOnlyPrefixes.contains { prefix in
            guard lower.hasPrefix(prefix) else { return false }
            return prefix.last == " "
                || prefix.last == "\t"
                || lower.count == prefix.count
        }
        if isReadOnlyPrefix, !hasControlSurface {
            return .low
        }

        // High-risk surface indicators.
        let highPatterns = [
            #"\brm\b"#, #"\bsudo\b"#, #"\bmkfs\b"#, #"\bdd\b"#,
            #"\bcurl\b"#, #"\bwget\b"#, #"\bgit\s+push\b"#,
            #"\bdeploy\b"#, #"\bfirebase\b"#, #"\bvercel\b"#, #"\baws\b"#,
            #"\bssh\b"#, #"\bscp\b"#, #"\bsftp\b"#,
        ]
        for pattern in highPatterns {
            if lower.range(of: pattern, options: .regularExpression) != nil {
                return .high
            }
        }

        if let raw = workingDirectory {
            let standardized = URL(
                fileURLWithPath: expandTilde(raw),
                isDirectory: true
            ).standardizedFileURL.resolvingSymlinksInPath()
            if !isContained(standardized, by: allowedRoot) {
                return .high
            }
        }

        // Default: file-editing agents, builds, test runs.
        return .medium
    }

    private static func mediumOrHigherIfDangerous(_ command: String) -> RiskLevel {
        let lower = command.lowercased()
        let highMarkers = [
            "git push", "deploy", "curl", "wget", "rm ", "sudo", "api key",
            "token", "secret", "password", "production", "prod",
        ]
        for marker in highMarkers {
            if lower.contains(marker) { return .high }
        }
        return .medium
    }
}
