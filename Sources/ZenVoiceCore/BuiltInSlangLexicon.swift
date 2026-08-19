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

/// Curated built-in lexicon containing common Hinglish colloquialisms,
/// code-switching expressions, and developer/modern slang vocabulary.
///
/// This provides zero-configuration accuracy for bilingual speech and
/// industry-specific terminology out of the box.
public enum BuiltInSlangLexicon {
    /// High-frequency Hinglish colloquialisms and loanwords formatted in standard Latin script.
    public static let hinglishWords: [String] = [
        "acha", "achha", "accha", "agar", "alvida", "apna", "apne", "arrey", "aur",
        "baat", "batao", "bhai", "bhaiya", "bilkul", "bohot", "bahut", "bura",
        "chalo", "chahiye", "chhod", "crore",
        "dekh", "dekho", "dhanyavaad", "dil", "dost", "dosti", "dukaan",
        "ekdam", "fayda", "fikr", "gaadi", "ghar",
        "haan", "hoga", "hogi", "hote", "hua", "huye",
        "itna", "jab", "jaldi", "janta", "jawaab", "jugaad",
        "kaam", "kab", "kahan", "kaise", "kal", "karenge", "karna", "karo", "khabar", "khair", "khana", "khushi", "kripya", "kuch", "kya", "kyunki",
        "lao", "lekin", "log",
        "madad", "mahaul", "makan", "mana", "mast", "mat", "matlab", "mera", "meri", "mere", "milte", "mujhse", "mujhe",
        "naam", "nahi", "nahin", "namaste", "naya", "nayi", "nazar",
        "pakka", "parivaar", "pata", "pehla", "phir", "pyaar",
        "raasta", "raat", "rakho", "roko",
        "saaf", "saath", "sab", "sahi", "samajh", "samay", "sawaal", "shanti", "shukriya", "socho", "suno",
        "tab", "tak", "taraf", "tashreef", "taiyari", "teekha", "tension", "theek", "thoda", "tum", "tumhara",
        "umeed", "umar", "upar",
        "waqt", "wajah", "wala", "wali", "wapas",
        "yaar", "yahan", "yehi", "zaroor", "zaroorat", "zindagi", "ziyada"
    ]

    /// Common technical, developer, and modern workflow terminology.
    public static let techAndSlangTerms: [String] = [
        "API", "APIs", "app", "apps", "async", "await", "auth", "backend", "bench", "benchmark", "branch",
        "bug", "build", "CI/CD", "CLI", "cloud", "codebase", "commit", "config", "cron", "CSS", "data",
        "daemon", "database", "deadlock", "debug", "deploy", "diff", "docker", "docs", "DOM", "endpoint",
        "engine", "enum", "env", "ETA", "eval", "fix", "frontend", "FYI", "git", "GitHub", "GPU",
        "harness", "HTML", "HTTP", "HTTPS", "IDE", "iOS", "IPC", "JSON", "k8s", "Kubernetes", "latency",
        "layout", "LGTM", "LLM", "LLMs", "lock", "log", "macOS", "markup", "merge", "metadata", "mock",
        "model", "module", "mutex", "native", "neural", "npm", "NPU", "OAuth", "ONNX", "open-source",
        "ops", "parse", "patch", "payload", "pipeline", "PR", "PRs", "prod", "production", "profiler",
        "proxy", "push", "QA", "query", "queue", "refactor", "regex", "release", "repo", "repository",
        "request", "REST", "retry", "roadmap", "ROI", "runtime", "Rust", "SaaS", "sandbox", "schema",
        "script", "SDK", "semver", "server", "sharding", "socket", "sprint", "SQL", "SQLite", "SSH",
        "stack", "staging", "standup", "state", "struct", "Swift", "SwiftUI", "sync", "syntax", "task",
        "telemetry", "terminal", "test", "token", "throughput", "timeout", "tmux", "trace", "UI", "UI/UX",
        "unit-test", "update", "upstream", "URI", "URL", "UX", "VAD", "vault", "version", "Vite", "VSCode",
        "WAL", "webhook", "webview", "Whisper", "WIP", "workflow", "Xcode", "YAML", "zsh"
    ]

    /// Common misheard acoustic homophones mapped to preferred Hinglish spelling.
    public static let defaultAcousticCorrections: [(misheard: String, replacement: String)] = [
        ("theek hey", "theek hai"),
        ("theek hy", "theek hai"),
        ("mat lab", "matlab"),
        ("acha hey", "acha hai"),
        ("bhai ya", "bhaiya"),
        ("pak ka", "pakka"),
        ("tension mut lo", "tension mat lo"),
        ("tension matlo", "tension mat lo"),
        ("dekh lo na", "dekh lo na"),
        ("samaj gaya", "samajh gaya"),
        ("samjh gaya", "samajh gaya"),
        ("kya bat hai", "kya baat hai"),
        ("kya bath hai", "kya baat hai"),
        ("ek dum", "ekdam"),
        ("pata nahee", "pata nahi"),
        ("shukri ya", "shukriya"),
        ("ju gaad", "jugaad"),
        ("pull request", "PR"),
        ("light gtm", "LGTM"),
        ("cube nettes", "Kubernetes"),
        ("cube net is", "Kubernetes"),
        ("k eight s", "k8s"),
        ("k eights", "k8s")
    ]

    /// Generates a contextual prompt seeding string containing preferred Hinglish and tech vocabulary.
    public static func contextPrompt(for profile: LanguageProfile) -> String {
        if profile.isHinglish {
            return "Hinglish dictation: theek hai, matlab, acha, bhai, kaam, jugaad, pakka, sahi, yaar, tension mat lo, PR, repo, deploy, bug, k8s, LLM, UI/UX, config, prod."
        }
        return "Technical dictation: PR, repo, deploy, bug, k8s, LLM, API, macOS, async, await, SwiftUI, backend, frontend, commit, merge."
    }

    /// Normalizes common colloquial phonetic variations in transcribed text.
    public static func normalizeColloquialPhrases(_ text: String) -> String {
        var result = text
        for (misheard, replacement) in defaultAcousticCorrections {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: misheard) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }
        return result
    }
}
