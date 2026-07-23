import Combine
import Foundation
import ZenVoiceCore

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var isPresented: Bool

    init(showAtLaunch: Bool) {
        isPresented = showAtLaunch
    }

    func show() {
        isPresented = true
    }

    func complete() {
        OnboardingPreferences.complete()
        isPresented = false
    }
}
