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

    func addRule(source: String, replacement: String) -> Bool {
        do {
            try vaultProvider().addCorrectionRule(
                source: source,
                replacement: replacement
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
