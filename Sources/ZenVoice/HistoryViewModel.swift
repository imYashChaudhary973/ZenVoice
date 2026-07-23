import AppKit
import Combine
import Foundation
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
    private let vaultProvider: () throws -> DictationVault
    private let retryRecord: (DictationRecord) -> Result<Void, Error>
    private let privacyChanged: () -> Void

    init(
        preferences: HistoryPreferences,
        vaultProvider: @escaping () throws -> DictationVault,
        retryRecord: @escaping
            (DictationRecord) -> Result<Void, Error>,
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
        let scopedRecords = scope == .recovery
            ? recoveryRecords
            : records
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

    var recoveryCount: Int {
        recoveryRecords.count
    }

    func refresh() {
        guard historyEnabled || preferences.hasEverEnabledHistory else {
            records = []
            return
        }
        do {
            records = try vaultProvider().recent(limit: 500)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func enableHistory() {
        do {
            _ = try vaultProvider()
            preferences.isHistoryEnabled = true
            historyEnabled = true
            hasMadeHistoryChoice = true
            errorMessage = nil
            privacyChanged()
            refresh()
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
        if !enabled {
            do {
                _ = try vaultProvider().deleteAllRecoveryAudio()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        preferences.retainsFailedAudio = enabled
        retainsFailedAudio = enabled
        errorMessage = nil
        refresh()
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
        switch retryRecord(record) {
        case .success:
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ record: DictationRecord) {
        do {
            try vaultProvider().deleteRecord(id: record.id)
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
        do {
            try vaultProvider().updateCategory(
                id: record.id,
                category: category
            )
            refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAll() {
        do {
            try vaultProvider().deleteAll()
            records = []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
