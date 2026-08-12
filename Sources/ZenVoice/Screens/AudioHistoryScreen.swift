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

import SwiftUI
import ZenVoiceStorage

struct AudioHistoryScreen: View {
    @ObservedObject var viewModel: AudioHistoryViewModel

    /// Offered archive caps, in bytes.
    private static let sizeOptions: [Int64] = [
        512 * 1_024 * 1_024,
        1 * 1_024 * 1_024 * 1_024,
        2 * 1_024 * 1_024 * 1_024,
        5 * 1_024 * 1_024 * 1_024,
        10 * 1_024 * 1_024 * 1_024
    ]

    private static let ageOptions = [7, 14, 30, 90, 365]

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            enableSection
            if viewModel.isEnabled {
                budgetSection
                recordingsSection
            }
            messageSection
        }
        .onAppear { viewModel.refresh() }
        .onDisappear { viewModel.stopPlayback() }
    }

    // MARK: - Enable

    private var enableSection: some View {
        ZenSection(title: "Recording archive") {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    Text(
                        "Archived audio is stored unencrypted in ZenVoice's "
                        + "private Application Support folder, separate from "
                        + "your encrypted transcripts. Private Dictation is "
                        + "never archived."
                    )
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Toggle(
                        "Keep recordings",
                        isOn: Binding(
                            get: { viewModel.isEnabled },
                            set: { viewModel.setEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    // MARK: - Budget

    private var budgetSection: some View {
        ZenSection(
            title: "Budget",
            caption: "\(viewModel.totalSizeDisplayString) of "
                + viewModel.maxSizeDisplayString
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                    ProgressView(value: viewModel.budgetFraction)
                        .progressViewStyle(.linear)
                        .accessibilityLabel(Text("Archive space used"))

                    Picker(
                        "Maximum size",
                        selection: Binding(
                            get: { viewModel.maxSizeBytes },
                            set: { viewModel.setMaxSizeBytes($0) }
                        )
                    ) {
                        ForEach(Self.sizeOptions, id: \.self) { bytes in
                            Text(
                                ByteCountFormatter.string(
                                    fromByteCount: bytes,
                                    countStyle: .binary
                                )
                            )
                            .tag(bytes)
                        }
                    }

                    Picker(
                        "Delete after",
                        selection: Binding(
                            get: { viewModel.maxAgeDays },
                            set: { viewModel.setMaxAgeDays($0) }
                        )
                    ) {
                        ForEach(Self.ageOptions, id: \.self) { days in
                            Text(dayLabel(days)).tag(days)
                        }
                    }

                    Text(
                        "The oldest recordings are removed first when either "
                        + "limit is reached. Cleanup runs at launch and after "
                        + "each dictation."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private func dayLabel(_ days: Int) -> String {
        switch days {
        case 7:
            return "1 week"
        case 14:
            return "2 weeks"
        case 30:
            return "30 days"
        case 90:
            return "90 days"
        case 365:
            return "1 year"
        default:
            return "\(days) days"
        }
    }

    // MARK: - Recordings

    private var recordingsSection: some View {
        ZenSection(
            title: "Recordings",
            caption: viewModel.records.isEmpty
                ? nil
                : "\(viewModel.records.count) stored"
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.records.isEmpty {
                        ZenRow(
                            icon: "recordingtape",
                            title: "No recordings yet",
                            subtitle:
                                "New dictations will be archived from now on."
                        )
                        .padding(ZenDesign.Spacing.md)
                    } else {
                        ForEach(viewModel.records) { record in
                            recordingRow(record)
                            if record.id != viewModel.records.last?.id {
                                ZenPanelDivider()
                            }
                        }
                    }
                }
            }
            if !viewModel.records.isEmpty {
                actionBar
            }
        }
    }

    private func recordingRow(_ record: AudioArchiveRecord) -> some View {
        HStack(spacing: ZenDesign.Spacing.sm) {
            Toggle(
                isOn: Binding(
                    get: { viewModel.selection.contains(record.id) },
                    set: { _ in viewModel.toggleSelection(record.id) }
                )
            ) {
                EmptyView()
            }
            .labelsHidden()
            .accessibilityLabel(Text("Select recording"))

            Button {
                viewModel.togglePlayback(record)
            } label: {
                Image(
                    systemName: viewModel.playingRecordID == record.id
                        ? "stop.fill"
                        : "play.fill"
                )
                .font(.system(size: 11))
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: ZenDesign.Radius.small)
                        .fill(ZenDesign.Semantic.surfaceRaised)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text(
                    viewModel.playingRecordID == record.id
                        ? "Stop playback"
                        : "Play recording"
                )
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(record.targetAppName ?? "Unknown app")
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(1)
                Text(
                    record.startedAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            }

            Spacer()

            Text(durationLabel(record.durationSeconds))
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)

            Text(
                ByteCountFormatter.string(
                    fromByteCount: record.fileSize,
                    countStyle: .binary
                )
            )
            .font(ZenDesign.Typography.caption)
            .foregroundStyle(ZenDesign.Semantic.textTertiary)
            .frame(width: 70, alignment: .trailing)

            Button {
                viewModel.delete(record)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(ZenDesign.Semantic.textTertiary)
            .accessibilityLabel(Text("Delete recording"))
        }
        .padding(.horizontal, ZenDesign.Spacing.md)
        .padding(.vertical, ZenDesign.Spacing.xs)
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
            HStack(spacing: ZenDesign.Spacing.xs) {
                Button("Select all") { viewModel.selectAll() }
                    .buttonStyle(ZenSecondaryButtonStyle())
                Button("Clear") { viewModel.clearSelection() }
                    .buttonStyle(ZenSecondaryButtonStyle())
                    .disabled(viewModel.selection.isEmpty)

                Spacer()

                Button("Delete selected") { viewModel.deleteSelected() }
                    .buttonStyle(ZenDestructiveButtonStyle())
                    .disabled(viewModel.selection.isEmpty)
                Button("Delete all") { viewModel.deleteAll() }
                    .buttonStyle(ZenDestructiveButtonStyle())
                Button(exportButtonTitle) { viewModel.export() }
                    .buttonStyle(ZenPrimaryButtonStyle())
            }

            Toggle(
                "Include transcripts in export",
                isOn: $viewModel.includeTranscriptsInExport
            )
            .toggleStyle(.switch)
            .font(ZenDesign.Typography.caption)

            Text(
                "Exports contain the audio files and a metadata manifest. "
                + "Transcript text is left out unless you turn it on above."
            )
            .font(ZenDesign.Typography.caption)
            .foregroundStyle(ZenDesign.Semantic.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var exportButtonTitle: String {
        viewModel.selection.isEmpty
            ? "Export all…"
            : "Export \(viewModel.selection.count)…"
    }

    // MARK: - Messages

    @ViewBuilder
    private var messageSection: some View {
        if let error = viewModel.errorMessage {
            Text(error)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.danger)
                .fixedSize(horizontal: false, vertical: true)
        } else if let status = viewModel.statusMessage {
            Text(status)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
        }
    }
}
