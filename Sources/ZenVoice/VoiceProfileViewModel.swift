import Combine
import Foundation
import ZenVoiceStorage

@MainActor
final class VoiceProfileViewModel: ObservableObject {
    @Published private(set) var snapshot = VoiceProfileSnapshot.empty
    @Published var errorMessage: String?

    private let vaultProvider: () throws -> DictationVault

    init(vaultProvider: @escaping () throws -> DictationVault) {
        self.vaultProvider = vaultProvider
        refresh()
    }

    func refresh() {
        do {
            snapshot = try vaultProvider().voiceProfile()
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
}
