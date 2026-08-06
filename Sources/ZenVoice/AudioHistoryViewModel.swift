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

import AVFoundation
import AppKit
import Combine
import Foundation
import ZenVoiceStorage

/// Drives the Audio History screen: the opt-in toggle, budget controls, the
/// list of archived recordings, playback, deletion, and ZIP export.
@MainActor
final class AudioHistoryViewModel: NSObject, ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var records: [AudioArchiveRecord] = []
    @Published private(set) var totalSizeBytes: Int64 = 0
    @Published private(set) var playingRecordID: UUID?
    @Published var selection: Set<UUID> = []
    @Published var includeTranscriptsInExport = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let preferences: AudioHistoryPreferences
    private let vaultProvider: () throws -> DictationVault
    private var player: AVAudioPlayer?

    init(
        preferences: AudioHistoryPreferences = AudioHistoryPreferences(),
        vaultProvider: @escaping () throws -> DictationVault
    ) {
        self.preferences = preferences
        self.vaultProvider = vaultProvider
        isEnabled = preferences.isEnabled
        super.init()
        refresh()
    }

    // MARK: - Preferences

    var maxSizeBytes: Int64 { preferences.maxSizeBytes }
    var maxAgeDays: Int { preferences.maxAgeDays }
    var maxSizeDisplayString: String { preferences.maxSizeDisplayString }

    var totalSizeDisplayString: String {
        ByteCountFormatter.string(
            fromByteCount: totalSizeBytes,
            countStyle: .binary
        )
    }

    /// How full the archive is, 0...1, for a budget meter.
    var budgetFraction: Double {
        guard maxSizeBytes > 0 else { return 0 }
        return min(1, Double(totalSizeBytes) / Double(maxSizeBytes))
    }

    func setEnabled(_ enabled: Bool) {
        preferences.isEnabled = enabled
        isEnabled = enabled
        if !enabled {
            stopPlayback()
        }
        refresh()
    }

    func setMaxSizeBytes(_ bytes: Int64) {
        preferences.maxSizeBytes = bytes
        objectWillChange.send()
        applyBudgets()
    }

    func setMaxAgeDays(_ days: Int) {
        preferences.maxAgeDays = days
        objectWillChange.send()
        applyBudgets()
    }

    // MARK: - Loading

    func refresh() {
        guard isEnabled else {
            records = []
            totalSizeBytes = 0
            selection = []
            return
        }
        do {
            let vault = try vaultProvider()
            records = try vault.audioArchiveRecent()
            totalSizeBytes = try vault.audioArchiveTotalSize()
            // Drop selections whose records are gone.
            let ids = Set(records.map(\.id))
            selection = selection.intersection(ids)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Applies the age and size budgets, then reloads.
    private func applyBudgets() {
        guard isEnabled else { return }
        do {
            let vault = try vaultProvider()
            let cutoff = Calendar.current.date(
                byAdding: .day,
                value: -preferences.maxAgeDays,
                to: Date()
            ) ?? Date.distantPast
            _ = try vault.purgeAudioArchive(olderThan: cutoff)
            _ = try vault.enforceAudioArchiveSizeBudget(
                preferences.maxSizeBytes
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    // MARK: - Playback

    func togglePlayback(_ record: AudioArchiveRecord) {
        if playingRecordID == record.id {
            stopPlayback()
            return
        }
        stopPlayback()
        do {
            let player = try AVAudioPlayer(contentsOf: record.audioURL)
            player.delegate = self
            guard player.play() else {
                errorMessage = "That recording could not be played."
                return
            }
            self.player = player
            playingRecordID = record.id
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playingRecordID = nil
    }

    // MARK: - Selection

    func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    func selectAll() {
        selection = Set(records.map(\.id))
    }

    func clearSelection() {
        selection = []
    }

    // MARK: - Deletion

    func delete(_ record: AudioArchiveRecord) {
        if playingRecordID == record.id {
            stopPlayback()
        }
        do {
            try vaultProvider().deleteAudioArchive(id: record.id)
            selection.remove(record.id)
            statusMessage = "Recording deleted."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func deleteSelected() {
        let targets = records.filter { selection.contains($0.id) }
        guard !targets.isEmpty else { return }
        stopPlayback()
        do {
            let vault = try vaultProvider()
            for record in targets {
                try vault.deleteAudioArchive(id: record.id)
            }
            selection = []
            statusMessage = targets.count == 1
                ? "1 recording deleted."
                : "\(targets.count) recordings deleted."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func deleteAll() {
        stopPlayback()
        do {
            let deleted = try vaultProvider().deleteAllAudioArchives()
            selection = []
            statusMessage = "\(deleted) recordings deleted."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    // MARK: - Export

    /// Exports the current selection — or everything, when nothing is
    /// selected — through a save panel.
    func export() {
        let targets = selection.isEmpty
            ? records
            : records.filter { selection.contains($0.id) }
        guard !targets.isEmpty else {
            errorMessage = AudioArchiveExportError.noRecords
                .localizedDescription
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Audio History"
        panel.nameFieldStringValue = defaultExportFileName()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        do {
            let vault = try vaultProvider()
            try AudioArchiveExporter.export(
                records: targets,
                options: AudioArchiveExportOptions(
                    includeTranscripts: includeTranscriptsInExport
                ),
                to: destination,
                transcriptProvider: { dictationID in
                    try? vault.record(id: dictationID)?.finalTranscript
                }
            )
            statusMessage = targets.count == 1
                ? "Exported 1 recording."
                : "Exported \(targets.count) recordings."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func defaultExportFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "ZenVoice-Audio-\(formatter.string(from: Date())).zip"
    }
}

extension AudioHistoryViewModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in
            self?.stopPlayback()
        }
    }
}
