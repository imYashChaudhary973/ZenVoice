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

/// Resolves model and language changes as one configuration decision.
///
/// A profile screen and a model screen must not independently reject each
/// other's current value. Doing so makes a specialist model impossible to
/// select: the profile waits for the model while the model waits for the
/// profile. This policy computes the complete compatible pair before either
/// preference is changed.
public enum ModelProfileTransition {
    /// Builds a complete runtime candidate before persisting either side of
    /// the model/profile pair.
    ///
    /// Callers should do every operation that can fail inside `prepare`.
    /// Preferences are committed only after it returns successfully.
    public static func prepareAndCommit<Prepared>(
        model: VerifiedModel,
        profile: LanguageProfile,
        defaults: UserDefaults = .standard,
        prepare: () throws -> Prepared
    ) rethrows -> Prepared {
        let prepared = try prepare()
        ModelSelectionPreferences.save(model, defaults: defaults)
        LanguagePreferences.save(profile, defaults: defaults)
        return prepared
    }

    public static func profileForSelecting(
        model: VerifiedModel,
        currentProfile: LanguageProfile
    ) -> LanguageProfile? {
        if currentProfile.isCompatible(with: model.languageCapability) {
            return currentProfile
        }
        switch model.languageCapability {
        case .english:
            return .english
        case .hinglish:
            return .hinglish
        case .multilingual:
            // A multilingual model can serve many profiles, so selecting one
            // must not guess which language should replace Hinglish.
            return nil
        }
    }

    public static func modelForSelecting(
        profile: LanguageProfile,
        currentModel: VerifiedModel?,
        installedModels: [VerifiedModel],
        recommendedModelID: String?
    ) -> VerifiedModel? {
        let installedIDs = Set(installedModels.map(\.id))
        if let currentModel,
           installedIDs.contains(currentModel.id),
           profile.isCompatible(with: currentModel.languageCapability) {
            return currentModel
        }

        let compatible = installedModels.filter {
            profile.isCompatible(with: $0.languageCapability)
        }
        if profile == .hinglish {
            return compatible.first {
                $0.languageCapability == .hinglish
            }
        }
        if let recommendedModelID,
           let recommended = compatible.first(where: {
               $0.id == recommendedModelID
           }) {
            return recommended
        }

        // Prefer offered models. Retired models remain valid for an existing
        // selection, but a new transition should not move a user onto one.
        return compatible.first {
            !VerifiedModelCatalog.isRetired($0)
        } ?? compatible.first
    }

    public static func unavailableMessage(
        for profile: LanguageProfile
    ) -> String {
        if profile == .hinglish {
            return
                "Hinglish requires the verified Hinglish Apex model. "
                + "Download it in Models to continue."
        }
        if profile == .english {
            return
                "English requires an installed English or multilingual "
                + "speech model."
        }
        return
            "\(profile.displayName) requires an installed multilingual "
            + "Whisper model."
    }

    public static func incompatibilityBadge(
        model: VerifiedModel,
        currentProfile: LanguageProfile
    ) -> String? {
        guard !currentProfile.isCompatible(
            with: model.languageCapability
        ) else {
            return nil
        }
        switch model.languageCapability {
        case .english:
            return "English only"
        case .hinglish:
            return "Hinglish only"
        case .multilingual:
            return currentProfile == .hinglish
                ? "Not for Hinglish"
                : "Needs multilingual profile"
        }
    }

    public static func incompatibleSelectionMessage(
        model: VerifiedModel,
        currentProfile: LanguageProfile
    ) -> String {
        if model.languageCapability == .hinglish {
            return
                "\(model.displayName) is available only with the Hinglish "
                + "profile."
        }
        if currentProfile == .hinglish {
            return
                "\(model.displayName) is not designed for Hinglish. "
                + "Choose a different language profile first."
        }
        return
            "\(model.displayName) is not compatible with "
            + "\(currentProfile.displayName)."
    }
}
