import Combine
import Foundation
import ZenVoiceStorage

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var snapshot = LocalInsightsSnapshot.empty
    @Published var errorMessage: String?

    private let vaultProvider: () throws -> DictationVault

    init(vaultProvider: @escaping () throws -> DictationVault) {
        self.vaultProvider = vaultProvider
        refresh()
    }

    func refresh() {
        do {
            snapshot = try vaultProvider().insights()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
