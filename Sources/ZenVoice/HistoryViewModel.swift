import AppKit
import Combine
import Foundation
import ZenVoiceStorage

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var records: [DictationRecord] = []
    @Published var searchText = ""
    @Published private(set) var historyEnabled: Bool
    @Published private(set) var hasMadeHistoryChoice: Bool
    @Published private(set) var retainsFailedAudio: Bool
    @Published private(set) var privateModeEnabled: Bool
    @Published var errorMessage: String?

    private let preferences: HistoryPreferences
    private let vaultProvider: () throws -> DictationVault
    private let pasteRecord: (DictationRecord) -> Void
    private let retryRecord: (DictationRecord) -> Result<Void, Error>

    init(
        preferences: HistoryPreferences,
        vaultProvider: @escaping () throws -> DictationVault,
        pasteRecord: @escaping (DictationRecord) -> Void,
        retryRecord: @escaping
            (DictationRecord) -> Result<Void, Error>
    ) {
        self.preferences = preferences
        self.vaultProvider = vaultProvider
        self.pasteRecord = pasteRecord
        self.retryRecord = retryRecord
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
            return records
        }
        return records.filter { record in
            record.finalTranscript?
                .localizedCaseInsensitiveContains(query) == true
                || record.targetAppName?
                    .localizedCaseInsensitiveContains(query) == true
        }
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
    }

    func setHistoryEnabled(_ enabled: Bool) {
        if enabled {
            enableHistory()
        } else {
            preferences.isHistoryEnabled = false
            historyEnabled = false
            hasMadeHistoryChoice = true
        }
    }

    func setRetainsFailedAudio(_ enabled: Bool) {
        preferences.retainsFailedAudio = enabled
        retainsFailedAudio = enabled
    }

    func setPrivateModeEnabled(_ enabled: Bool) {
        preferences.isPrivateModeEnabled = enabled
        privateModeEnabled = enabled
    }

    func copy(_ record: DictationRecord) {
        guard let transcript = record.finalTranscript else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    func paste(_ record: DictationRecord) {
        guard record.finalTranscript != nil else {
            return
        }
        pasteRecord(record)
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
