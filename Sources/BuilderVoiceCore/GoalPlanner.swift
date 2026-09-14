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

/// Three-tier planner: deterministic grammar, optional local model, then text.
public struct GoalPlanner: Sendable {
    private let allowedRoot: URL
    private let model: (any GoalPlanningModel)?

    public init(
        allowedRoot: URL? = nil,
        model: (any GoalPlanningModel)? = nil
    ) {
        self.allowedRoot = (
            allowedRoot
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Developer", isDirectory: true)
        ).standardizedFileURL
        self.model = model
    }

    public func plan(transcript: String) async -> GoalPlannerResult {
        let normalized = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeGoal(normalized) else {
            return .notGoal("The transcript does not look like a multi-step goal.")
        }

        if let plan = deterministicPlan(for: normalized) {
            return .plan(plan, source: "deterministic")
        }

        if let model {
            do {
                let plan = try await model.plan(
                    transcript: normalized,
                    allowedRoot: allowedRoot
                )
                return .plan(plan, source: "on-device model")
            } catch {
                return .notGoal(
                    "On-device planning is unavailable: \(error.localizedDescription)"
                )
            }
        }

        return .notGoal("No deterministic goal matched and no local planner is available.")
    }

    private static func looksLikeGoal(_ transcript: String) -> Bool {
        let words = transcript.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 4 else { return false }
        let lower = transcript.lowercased()
        if lower == "stop" || lower == "cancel" || lower.hasPrefix("stop ") {
            return false
        }
        let verbs = [
            "open ", "run ", "fix ", "build ", "test ", "review ",
            "update ", "use codex", "use claude", "ask codex", "ask claude",
        ]
        return verbs.contains(where: lower.hasPrefix)
            || lower.contains(" and then ")
            || lower.contains(", then ")
            || lower.contains(", and ")
    }

    private func deterministicPlan(for transcript: String) -> GoalPlan? {
        let lower = transcript.lowercased()
        let selectedAgent: GoalAgent = lower.contains("claude") ? .claude : .codex
        let workingDirectory = resolveWorkingDirectory(in: transcript)
        let clauses = splitClauses(transcript)
        var steps: [GoalStep] = []

        for rawClause in clauses {
            let clause = rawClause
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let clauseLower = clause.lowercased()
            guard !clause.isEmpty else { continue }

            if isAgentSetupClause(clauseLower) {
                continue
            }

            if clauseLower.hasPrefix("notify me")
                || clauseLower.hasPrefix("notify when")
            {
                steps.append(
                    GoalStep(
                        number: steps.count + 1,
                        agent: .notification,
                        command: clause,
                        description: "Send completion notification",
                        dependsOn: steps.last.map { [$0.number] } ?? [],
                        plannedRisk: .low,
                        computedRisk: .low
                    )
                )
                continue
            }

            if let appName = standaloneAppName(from: clause) {
                steps.append(
                    GoalStep(
                        number: steps.count + 1,
                        agent: .shell,
                        command: "open -a \(shellQuote(appName))",
                        description: "Open \(appName)",
                        workingDirectory: workingDirectory,
                        dependsOn: steps.last.map { [$0.number] } ?? [],
                        plannedRisk: .low,
                        computedRisk: .low
                    )
                )
                continue
            }

            guard isCodingClause(clauseLower) else { continue }
            let prompt = clause.hasSuffix(".") ? clause : clause + "."
            steps.append(
                GoalStep(
                    number: steps.count + 1,
                    agent: selectedAgent,
                    command: prompt,
                    description: clause,
                    workingDirectory: workingDirectory,
                    dependsOn: steps.last.map { [$0.number] } ?? [],
                    plannedRisk: .medium,
                    computedRisk: .medium
                )
            )
        }

        guard !steps.isEmpty else { return nil }
        if steps.count == 1, steps[0].agent != .notification {
            return nil
        }
        return GoalPlan(
            title: conciseTitle(from: transcript),
            proposedApprovalMode: .proposeUpToNextHigh,
            transcript: transcript,
            steps: steps
        )
    }

    private func splitClauses(_ transcript: String) -> [String] {
        let pattern = #",\s*(?:and\s+|then\s+)?|\s+and\s+(?=(?:run|fix|build|test|review|update|notify|open|ask|use)\b)|\s+and\s+then\s+"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return [transcript]
        }
        let range = NSRange(transcript.startIndex..., in: transcript)
        var result: [String] = []
        var start = transcript.startIndex
        for match in expression.matches(in: transcript, range: range) {
            guard let swiftRange = Range(match.range, in: transcript) else {
                continue
            }
            result.append(String(transcript[start..<swiftRange.lowerBound]))
            start = swiftRange.upperBound
        }
        result.append(String(transcript[start...]))
        return result
    }

    private func resolveWorkingDirectory(in transcript: String) -> String? {
        let pattern = #"(?i)\bin\s+(?:the\s+)?([A-Za-z0-9._ -]+?)\s+project\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: transcript,
                range: NSRange(transcript.startIndex..., in: transcript)
              ),
              let nameRange = Range(match.range(at: 1), in: transcript)
        else {
            return FileManager.default.currentDirectoryPath
                .hasPrefix(allowedRoot.path)
                ? FileManager.default.currentDirectoryPath
                : allowedRoot.path
        }

        let requested = String(transcript[nameRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: allowedRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return allowedRoot.path
        }
        let folded = requested.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        return entries.first { entry in
            entry.lastPathComponent.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ) == folded
        }?.path ?? allowedRoot.path
    }

    private func isAgentSetupClause(_ lower: String) -> Bool {
        (lower.hasPrefix("open codex") || lower.hasPrefix("open claude")
            || lower.hasPrefix("use codex") || lower.hasPrefix("use claude"))
            && lower.contains(" project")
    }

    private func isCodingClause(_ lower: String) -> Bool {
        let verbs = [
            "run ", "fix ", "build ", "test ", "review ", "update ",
            "ask codex", "ask claude", "use codex", "use claude",
        ]
        return verbs.contains(where: lower.hasPrefix)
    }

    private func standaloneAppName(from clause: String) -> String? {
        let lower = clause.lowercased()
        guard lower.hasPrefix("open "), !lower.contains(" project") else {
            return nil
        }
        let app = clause.dropFirst(5)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !app.isEmpty, !app.contains("/") else { return nil }
        return app
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func conciseTitle(from transcript: String) -> String {
        let words = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
        let title = words.prefix(9).joined(separator: " ")
        return words.count > 9 ? title + "…" : title
    }
}
