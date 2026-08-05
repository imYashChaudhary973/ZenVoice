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

import Combine
import Foundation
import ZenVoiceStorage

@MainActor
final class VoiceProfileViewModel: ObservableObject {
    @Published private(set) var snapshot = VoiceProfileSnapshot.empty
    @Published private(set) var appliesCorrectionRules: Bool
    @Published private(set) var analyzesHistory: Bool
    @Published var errorMessage: String?

    private let vaultProvider: () throws -> DictationVault
    private let preferences: LocalLearningPreferences

    init(
        preferences: LocalLearningPreferences =
            LocalLearningPreferences(),
        vaultProvider: @escaping () throws -> DictationVault
    ) {
        self.preferences = preferences
        self.vaultProvider = vaultProvider
        appliesCorrectionRules =
            preferences.appliesCorrectionRules
        analyzesHistory = preferences.analyzesHistory
        refresh()
    }

    func refresh() {
        do {
            let vault = try vaultProvider()
            if analyzesHistory {
                snapshot = try vault.voiceProfile()
            } else {
                snapshot = VoiceProfileSnapshot(
                    analyzedDictationCount: 0,
                    topWords: [],
                    catchPhrases: [],
                    correctionRules:
                        try vault.correctionRules(),
                    mostActiveHour: nil
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addRule(
        source: String,
        replacement: String,
        languageScope: CorrectionLanguageScope
    ) -> Bool {
        do {
            try vaultProvider().addCorrectionRule(
                source: source,
                replacement: replacement,
                languageScope: languageScope
            )
            refresh()
            return true
        } catch DictationVaultError.invalidRecord {
            errorMessage =
                "Use two different non-empty phrases. Each heard phrase can have only one rule."
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteRule(_ rule: CorrectionRule) {
        do {
            try vaultProvider().deleteCorrectionRule(id: rule.id)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAppliesCorrectionRules(_ enabled: Bool) {
        preferences.appliesCorrectionRules = enabled
        appliesCorrectionRules = enabled
    }

    func setAnalyzesHistory(_ enabled: Bool) {
        preferences.analyzesHistory = enabled
        analyzesHistory = enabled
        refresh()
    }

    func deleteAllRules() {
        do {
            try vaultProvider().deleteAllCorrectionRules()
            refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
