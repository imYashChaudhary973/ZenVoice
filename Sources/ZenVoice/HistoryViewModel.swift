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
import ZenVoiceStorage

@MainActor
final class HistoryViewModel: ObservableObject {
    enum Scope: String, CaseIterable, Identifiable {
        case all = "All"
        case recovery = "Recovery Inbox"

        var id: String { rawValue }
    }

    @Published private(set) var records: [DictationRecord] = []
    @Published var searchText = ""
    @Published var scope: Scope = .all
    @Published private(set) var historyEnabled: Bool
    @Published private(set) var hasMadeHistoryChoice: Bool
    @Published private(set) var retainsFailedAudio: Bool
    @Published private(set) var privateModeEnabled: Bool
    @Published var errorMessage: String?

    private let preferences: HistoryPreferences
    private let vaultProvider: () async throws -> DictationVault
    private let retryRecord: (DictationRecord) async -> Result<Void, Error>
    private let privacyChanged: () -> Void

    init(
        preferences: HistoryPreferences,
        vaultProvider: @escaping () async throws -> DictationVault,
        retryRecord: @escaping
            (DictationRecord) async -> Result<Void, Error>,
        privacyChanged: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.vaultProvider = vaultProvider
        self.retryRecord = retryRecord
        self.privacyChanged = privacyChanged
        historyEnabled = preferences.isHistoryEnabled
        hasMadeHistoryChoice = preferences.hasMadeHistoryChoice
        retainsFailedAudio = preferences.retainsFailedAudio
        privateModeEnabled = preferences.isPrivateModeEnabled
        refresh()
    }

    var filteredRecords: [DictationRecord] {
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else {
            return scopedRecords
        }
        return scopedRecords.filter { record in
            record.finalTranscript?
                .localizedCaseInsensitiveContains(query) == true
                || record.targetAppName?
                    .localizedCaseInsensitiveContains(query) == true
        }
    }

    var recoveryRecords: [DictationRecord] {
        records.filter {
            $0.status == .failed || $0.isPartial
        }
    }

    var standardRecords: [DictationRecord] {
        records.filter {
            $0.status != .failed && !$0.isPartial
        }
    }

    var scopedRecords: [DictationRecord] {
        scope == .recovery ? recoveryRecords : standardRecords
    }

    var recoveryCount: Int {
        recoveryRecords.count
    }

    var savedTranscriptCount: Int {
        records.lazy.filter { $0.finalTranscript != nil }.count
    }

    var recoveryAudioCount: Int {
        records.lazy.filter { $0.recoveryAudioURL != nil }.count
    }

    func refresh() {
        Task { await refreshNow() }
    }

    private func refreshNow() async {
        guard historyEnabled || preferences.hasEverEnabledHistory else {
            records = []
            return
        }
        do {
            records = try await vaultProvider().recent(limit: 500)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func enableHistory() {
        Task { await enableHistoryNow() }
    }

    private func enableHistoryNow() async {
        do {
            _ = try await vaultProvider()
            preferences.isHistoryEnabled = true
            historyEnabled = true
            hasMadeHistoryChoice = true
            errorMessage = nil
            privacyChanged()
            await refreshNow()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func declineHistory() {
        preferences.isHistoryEnabled = false
        historyEnabled = false
        preferences.hasMadeHistoryChoice = true
        hasMadeHistoryChoice = true
        privacyChanged()
    }

    func setHistoryEnabled(_ enabled: Bool) {
        if enabled {
            enableHistory()
        } else {
            preferences.isHistoryEnabled = false
            historyEnabled = false
            hasMadeHistoryChoice = true
            privacyChanged()
        }
    }

    func setRetainsFailedAudio(_ enabled: Bool) {
        Task { await setRetainsFailedAudioNow(enabled) }
    }

    private func setRetainsFailedAudioNow(_ enabled: Bool) async {
        if !enabled {
            do {
                _ = try await vaultProvider().deleteAllRecoveryAudio()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        preferences.retainsFailedAudio = enabled
        retainsFailedAudio = enabled
        errorMessage = nil
        await refreshNow()
    }

    func setPrivateModeEnabled(_ enabled: Bool) {
        preferences.isPrivateModeEnabled = enabled
        privateModeEnabled = enabled
        privacyChanged()
    }

    func copy(_ record: DictationRecord) {
        guard let transcript = record.finalTranscript else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    func retry(_ record: DictationRecord) {
        Task { await retryNow(record) }
    }

    private func retryNow(_ record: DictationRecord) async {
        switch await retryRecord(record) {
        case .success:
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ record: DictationRecord) {
        Task { await deleteNow(record) }
    }

    private func deleteNow(_ record: DictationRecord) async {
        do {
            try await vaultProvider().deleteRecord(id: record.id)
            records.removeAll { $0.id == record.id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setCategory(
        _ category: DictationCategory,
        for record: DictationRecord
    ) {
        Task { await setCategoryNow(category, for: record) }
    }

    private func setCategoryNow(
        _ category: DictationCategory,
        for record: DictationRecord
    ) async {
        do {
            try await vaultProvider().updateCategory(
                id: record.id,
                category: category
            )
            await refreshNow()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func spellingSuggestions(
        for record: DictationRecord
    ) async -> [CorrectionSuggestion] {
        guard let transcript = record.finalTranscript else {
            return []
        }
        do {
            return try await vaultProvider().correctionSuggestions(
                in: transcript,
                activeScope: correctionScope(for: record)
            )
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func addSpellingCorrection(
        source: String,
        replacement: String,
        for record: DictationRecord
    ) async -> Bool {
        let source = source.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let transcript = record.finalTranscript,
              !source.isEmpty,
              transcript.localizedCaseInsensitiveContains(source) else {
            errorMessage =
                "The incorrect spelling must appear in this transcript."
            return false
        }
        do {
            try await vaultProvider().addCorrectionRule(
                source: source,
                replacement: replacement,
                languageScope: correctionScope(for: record)
            )
            errorMessage = nil
            return true
        } catch DictationVaultError.invalidRecord {
            errorMessage =
                "Use two different non-empty spellings. This spelling may already have a rule."
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteAll(in scope: Scope) {
        Task { await deleteAllNow(in: scope) }
    }

    private func deleteAllNow(in scope: Scope) async {
        let recordsToDelete =
            scope == .recovery ? recoveryRecords : standardRecords
        let ids = recordsToDelete.map(\.id)
        guard !ids.isEmpty else {
            return
        }
        do {
            _ = try await vaultProvider().deleteRecords(ids: ids)
            let deletedIDs = Set(ids)
            records.removeAll { deletedIDs.contains($0.id) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAll() {
        Task { await deleteAllNow() }
    }

    private func deleteAllNow() async {
        do {
            try await vaultProvider().deleteAll()
            records = []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAllRecoveryAudio() {
        Task { await deleteAllRecoveryAudioNow() }
    }

    private func deleteAllRecoveryAudioNow() async {
        do {
            _ = try await vaultProvider().deleteAllRecoveryAudio()
            await refreshNow()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func correctionScope(
        for record: DictationRecord
    ) -> CorrectionLanguageScope {
        let profile = LanguageProfile.historyRetryProfile(
            languageCode: record.language,
            modelID: record.modelID
        )
        return profile == .hinglish ? .hinglish : .all
    }
}
