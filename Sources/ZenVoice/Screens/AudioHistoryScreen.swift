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
    private enum DeleteRequest {
        case recording(AudioArchiveRecord)
        case selected
        case all
    }

    @State private var deleteRequest: DeleteRequest?
    @State private var customSizeText = ""
    @State private var showsCustomSize = false

    private static let gigabyte: Int64 = 1_024 * 1_024 * 1_024
    private static let customSizeSentinel: Int64 = -1
    private static let presetSizes: [Int64] = [
        512 * 1_024 * 1_024,
        1 * gigabyte,
        2 * gigabyte,
        5 * gigabyte,
        10 * gigabyte,
        25 * gigabyte,
        50 * gigabyte,
        100 * gigabyte
    ]
    private static let sizePickerOptions = presetSizes + [customSizeSentinel]

    private static let ageOptions = [7, 14, 30, 90, 365]

    private var usesCustomSize: Bool {
        !Self.presetSizes.contains(viewModel.maxSizeBytes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            ZenBanner(
                kind: .info,
                icon: "info.circle",
                text: "Stored only on this Mac. Recordings never leave your device and are removed by the limits below."
            )
            enableSection
            if viewModel.isEnabled {
                recordingsSection
                budgetSection
            }
            messageSection
        }
        .onAppear {
            viewModel.refresh()
            showsCustomSize = usesCustomSize
            if usesCustomSize {
                customSizeText = customSizeFieldText(viewModel.maxSizeBytes)
            }
        }
        .onDisappear { viewModel.stopPlayback() }
        .alert(
            deleteTitle,
            isPresented: Binding(
                get: { deleteRequest != nil },
                set: { if !$0 { deleteRequest = nil } }
            )
        ) {
            Button("Delete", role: .destructive, action: confirmDelete)
            Button("Cancel", role: .cancel) {
                deleteRequest = nil
            }
        } message: {
            Text(deleteMessage)
        }
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
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                    ProgressView(value: viewModel.budgetFraction)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .accessibilityLabel(Text("Archive space used"))

                    HStack {
                        Text("Maximum size")
                            .font(ZenDesign.Typography.body)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Spacer(minLength: ZenDesign.Spacing.sm)
                        ZenMenuPicker(
                            label: "Maximum size",
                            options: Self.sizePickerOptions,
                            selection: Binding(
                                get: {
                                    (showsCustomSize || usesCustomSize)
                                        ? Self.customSizeSentinel
                                        : viewModel.maxSizeBytes
                                },
                                set: { value in
                                    if value == Self.customSizeSentinel {
                                        showsCustomSize = true
                                        customSizeText = customSizeFieldText(
                                            viewModel.maxSizeBytes
                                        )
                                    } else {
                                        showsCustomSize = false
                                        viewModel.setMaxSizeBytes(value)
                                    }
                                }
                            ),
                            minWidth: 112,
                            compact: true,
                            title: sizeTitle
                        )
                    }

                    if showsCustomSize || usesCustomSize {
                        HStack {
                            Text("Custom size")
                                .font(ZenDesign.Typography.body)
                                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            Spacer(minLength: ZenDesign.Spacing.sm)
                            ZenTextInput(
                                placeholder: "GB",
                                text: $customSizeText,
                                icon: "internaldrive",
                                minWidth: 88
                            )
                            .onSubmit(applyCustomSize)
                            Button("Set") {
                                applyCustomSize()
                            }
                            .buttonStyle(ZenSecondaryButtonStyle())
                            .disabled(customSizeText.isEmpty)
                        }
                    }

                    HStack {
                        Text("Delete after")
                            .font(ZenDesign.Typography.body)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Spacer(minLength: ZenDesign.Spacing.sm)
                        ZenMenuPicker(
                            label: "Delete after",
                            options: Self.ageOptions,
                            selection: Binding(
                                get: { viewModel.maxAgeDays },
                                set: { viewModel.setMaxAgeDays($0) }
                            ),
                            minWidth: 112,
                            compact: true,
                            title: dayLabel
                        )
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

    private func sizeTitle(_ bytes: Int64) -> String {
        if bytes == Self.customSizeSentinel {
            return "Custom"
        }
        return ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .binary
        )
    }

    private func customSizeFieldText(_ bytes: Int64) -> String {
        let gigabytes = Double(bytes) / Double(Self.gigabyte)
        if gigabytes == gigabytes.rounded() {
            return String(Int(gigabytes))
        }
        return String(format: "%.1f", gigabytes)
    }

    private func applyCustomSize() {
        let trimmed = customSizeText
            .lowercased()
            .replacingOccurrences(of: "gb", with: "")
            .replacingOccurrences(of: "g", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gigabytes = Double(trimmed), gigabytes > 0 else {
            return
        }
        let bytes = Int64((gigabytes * Double(Self.gigabyte)).rounded())
        viewModel.setMaxSizeBytes(bytes)
        showsCustomSize = !Self.presetSizes.contains(viewModel.maxSizeBytes)
        customSizeText = customSizeFieldText(viewModel.maxSizeBytes)
    }

    // MARK: - Recordings

    private var recordingsSection: some View {
        ZenSection(
            title: "Recordings",
            caption: viewModel.records.isEmpty
                ? nil
                : "\(viewModel.records.count) stored"
        ) {
            ZenPanel(padding: ZenDesign.Spacing.xs) {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
                    if viewModel.records.isEmpty {
                        ZenRow(
                            icon: "recordingtape",
                            title: "No recordings yet",
                            subtitle:
                                "New dictations will be archived from now on."
                        )
                    } else {
                        ForEach(viewModel.records) { record in
                            recordingRow(record)
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

            ZenIconButton(
                systemImage: viewModel.playingRecordID == record.id
                    ? "stop.fill"
                    : "play.fill",
                label: viewModel.playingRecordID == record.id
                    ? "Stop playback"
                    : "Play recording"
            ) {
                viewModel.togglePlayback(record)
            }

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

            ZenIconButton(
                systemImage: "trash",
                label: "Delete recording",
                isDanger: true
            ) {
                deleteRequest = .recording(record)
            }
        }
        .padding(.horizontal, ZenDesign.Spacing.md)
        .padding(.vertical, ZenDesign.Spacing.sm)
        .background {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.medium,
                style: .continuous
            )
            .fill(ZenDesign.Semantic.surfaceRaised.opacity(0.55))
        }
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ZenDesign.Spacing.xs) {
                    selectionButtons
                    Spacer()
                    destructiveButtons
                    exportButton
                }
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
                    HStack(spacing: ZenDesign.Spacing.xs) {
                        selectionButtons
                    }
                    HStack(spacing: ZenDesign.Spacing.xs) {
                        destructiveButtons
                        Spacer()
                        exportButton
                    }
                }
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
    @ViewBuilder
    private var selectionButtons: some View {
        Button("Select all") { viewModel.selectAll() }
            .buttonStyle(ZenSecondaryButtonStyle())
        Button("Clear") { viewModel.clearSelection() }
            .buttonStyle(ZenSecondaryButtonStyle())
            .disabled(viewModel.selection.isEmpty)
    }

    @ViewBuilder
    private var destructiveButtons: some View {
        Button("Delete selected") {
            deleteRequest = .selected
        }
        .buttonStyle(ZenDestructiveButtonStyle())
        .disabled(viewModel.selection.isEmpty)
        ZenHoldToDeleteButton(label: "Hold to delete all") {
            viewModel.deleteAll()
        }
        .disabled(viewModel.records.isEmpty)
    }

    private var exportButton: some View {
        Button(exportButtonTitle) { viewModel.export() }
            .buttonStyle(ZenPrimaryButtonStyle())
    }

    private var exportButtonTitle: String {
        viewModel.selection.isEmpty
            ? "Export all…"
            : "Export \(viewModel.selection.count)…"
    }

    private var deleteTitle: String {
        switch deleteRequest {
        case .recording:
            return "Delete this recording?"
        case .selected:
            return "Delete selected recordings?"
        case .all:
            return "Delete every recording?"
        case nil:
            return "Delete recordings?"
        }
    }

    private var deleteMessage: String {
        switch deleteRequest {
        case .recording:
            return "The audio file will be permanently removed."
        case .selected:
            return "\(viewModel.selection.count) selected audio files will be permanently removed."
        case .all:
            return "All \(viewModel.records.count) audio files will be permanently removed."
        case nil:
            return ""
        }
    }

    private func confirmDelete() {
        switch deleteRequest {
        case .recording(let record):
            viewModel.delete(record)
        case .selected:
            viewModel.deleteSelected()
        case .all:
            viewModel.deleteAll()
        case nil:
            return
        }
        deleteRequest = nil
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
