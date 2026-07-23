import AppKit
import Combine
import Foundation
import ZenVoiceCore

struct RunningApplicationOption: Identifiable, Equatable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}

@MainActor
final class ApplicationProfileViewModel: ObservableObject {
    @Published private(set) var profiles: [ApplicationProfile] = []
    @Published private(set) var runningApplications:
        [RunningApplicationOption] = []
    @Published var selectedApplicationID: String?
    @Published var errorMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        profiles = ApplicationProfilePreferences.load()
            .sorted {
                $0.applicationName.localizedCaseInsensitiveCompare(
                    $1.applicationName
                ) == .orderedAscending
            }
        var seen = Set<String>()
        runningApplications = NSWorkspace.shared.runningApplications
            .compactMap { application in
                guard application.activationPolicy == .regular,
                      let bundleIdentifier =
                        application.bundleIdentifier,
                      bundleIdentifier != Bundle.main.bundleIdentifier,
                      seen.insert(bundleIdentifier).inserted else {
                    return nil
                }
                return RunningApplicationOption(
                    bundleIdentifier: bundleIdentifier,
                    name:
                        application.localizedName
                        ?? bundleIdentifier
                )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }
        if selectedApplicationID == nil {
            selectedApplicationID = runningApplications.first?.id
        }
    }

    func addSelectedApplication(
        languageProfile: LanguageProfile,
        refinementMode: InstantRefineMode
    ) {
        guard let selectedApplicationID,
              let application = runningApplications.first(where: {
                  $0.id == selectedApplicationID
              }) else {
            errorMessage =
                "Open the target app, then refresh the running-app list."
            return
        }
        let profile = ApplicationProfile(
            bundleIdentifier: application.bundleIdentifier,
            applicationName: application.name,
            languageProfile: languageProfile,
            refinementMode: refinementMode,
            voiceCommandsEnabled:
                LocalVoiceCommandPreferences.isEnabled()
        )
        ApplicationProfilePreferences.save(profile)
        errorMessage = nil
        refresh()
    }

    func setLanguage(
        _ languageProfile: LanguageProfile,
        for profile: ApplicationProfile
    ) {
        var updated = profile
        updated.languageProfile = languageProfile
        save(updated)
    }

    func setRefinementMode(
        _ mode: InstantRefineMode,
        for profile: ApplicationProfile
    ) {
        var updated = profile
        updated.refinementMode = mode
        save(updated)
    }

    func setVoiceCommandsEnabled(
        _ enabled: Bool,
        for profile: ApplicationProfile
    ) {
        var updated = profile
        updated.voiceCommandsEnabled = enabled
        save(updated)
    }

    func remove(_ profile: ApplicationProfile) {
        ApplicationProfilePreferences.remove(
            bundleIdentifier: profile.bundleIdentifier
        )
        refresh()
    }

    private func save(_ profile: ApplicationProfile) {
        ApplicationProfilePreferences.save(profile)
        errorMessage = nil
        refresh()
    }
}
