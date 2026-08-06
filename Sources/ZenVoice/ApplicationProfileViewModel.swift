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

    func setPreferredEngineID(
        _ engineID: String?,
        for profile: ApplicationProfile
    ) {
        var updated = profile
        updated.preferredEngineID = engineID
        save(updated)
    }

    func setPreferredOutputMode(
        _ outputMode: TranscriptionOutputMode?,
        for profile: ApplicationProfile
    ) {
        var updated = profile
        updated.preferredOutputMode = outputMode
        save(updated)
    }

    func setZenIntelligenceMode(
        _ mode: ZenIntelligenceMode?,
        for profile: ApplicationProfile
    ) {
        var updated = profile
        updated.zenIntelligenceMode = mode
        save(updated)
    }

    func setCommandSetID(
        _ commandSetID: String?,
        for profile: ApplicationProfile
    ) {
        var updated = profile
        updated.commandSetID = commandSetID
        save(updated)
    }

    func setWriteModeDefault(
        _ mode: WriteModeSubMode?,
        for profile: ApplicationProfile
    ) {
        var updated = profile
        updated.writeModeDefault = mode
        save(updated)
    }

    func setCustomPromptHints(
        _ hints: [String],
        for profile: ApplicationProfile
    ) {
        var updated = profile
        updated.customPromptHints = hints
            .map { NextDictationContext.sanitized($0) }
            .filter { !$0.isEmpty }
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
