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

struct MeetingsScreen: View {
    @ObservedObject var viewModel: MeetingViewModel
    @ObservedObject var cloudAIViewModel: CloudAIViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xxl) {
            recorderSection
            listSection
        }
        .onAppear { viewModel.refreshList() }
    }

    private var recorderSection: some View {
        ZenSection(
            title: "Meeting",
            caption:
                "Records on this Mac. Tell everyone on the call. The dictation hotkey does not start a meeting."
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                    Toggle(
                        "Auto-record detected meetings",
                        isOn: $viewModel.autoRecordEnabled
                    )
                    .font(ZenDesign.Typography.body)
                    .tint(ZenDesign.Semantic.accentFill)

                    if let pending = viewModel.pendingDetection,
                       !viewModel.isSessionActive {
                        HStack {
                            Text(pending.title)
                                .font(ZenDesign.Typography.bodyStrong)
                                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                                .lineLimit(2)
                            Spacer()
                            controlButton("Start notes") {
                                viewModel.start(title: pending.title)
                            }
                        }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text(viewModel.elapsedLabel)
                            .font(ZenDesign.Typography.display)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            .monospacedDigit()
                            .accessibilityLabel(
                                "Elapsed \(viewModel.elapsedLabel)"
                            )
                        Spacer()
                        Text(statusTitle)
                            .font(ZenDesign.Typography.captionStrong)
                            .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    }

                    HStack(spacing: ZenDesign.Spacing.sm) {
                        if viewModel.isSummarizing {
                            ProgressView()
                                .controlSize(.small)
                            Text("Summarizing…")
                                .font(ZenDesign.Typography.bodyStrong)
                                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        } else if viewModel.isTranscribing {
                            ProgressView()
                                .controlSize(.small)
                            Text("Transcribing…")
                                .font(ZenDesign.Typography.bodyStrong)
                                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        } else if !viewModel.isSessionActive {
                            controlButton("Start") { viewModel.start() }
                        } else if viewModel.isRecording {
                            controlButton("Pause", action: viewModel.pause)
                            controlButton("Stop", action: viewModel.stop)
                        } else if viewModel.isPaused {
                            controlButton("Resume", action: viewModel.resume)
                            controlButton("Stop", action: viewModel.stop)
                        }

                        if cloudAIViewModel.configuration.isEnabled,
                           viewModel.originalTranscript != nil,
                           viewModel.summary == nil,
                           !viewModel.isSummarizing {
                            controlButton(
                                "Recap",
                                action: viewModel.summarize
                            )
                            .disabled(
                                !cloudAIViewModel.isReady
                                    || !viewModel.canSummarize
                            )
                        }
                    }

                    if viewModel.themCaptureFailed {
                        Text(
                            "Them (system audio) is off. Grant Screen Recording to capture the other side of the call."
                        )
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: ZenDesign.Spacing.sm) {
                        TextField("You", text: $viewModel.youName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { viewModel.saveSpeakerNames() }
                        TextField("Them", text: $viewModel.themName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { viewModel.saveSpeakerNames() }
                        controlButton("Apply names", action: viewModel.saveSpeakerNames)
                            .disabled(viewModel.originalTranscript == nil)
                    }

                    HStack(spacing: ZenDesign.Spacing.sm) {
                        TextField(
                            "Search meetings",
                            text: $viewModel.searchQuery
                        )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { viewModel.searchMeetings() }
                        controlButton("Search", action: viewModel.searchMeetings)
                    }
                    if !viewModel.searchHits.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.searchHits, id: \.id) { hit in
                                Button(hit.snippet) {
                                    viewModel.open(hit.id)
                                }
                                .buttonStyle(.plain)
                                .font(ZenDesign.Typography.caption)
                                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                            }
                        }
                    }

                    if let original = viewModel.displayedTranscript,
                       !original.isEmpty {
                        HStack(alignment: .top, spacing: ZenDesign.Spacing.md) {
                            transcriptColumn(
                                title: "Original transcript",
                                text: original
                            )
                            if let summary = viewModel.summary,
                               !summary.isEmpty {
                                transcriptColumn(
                                    title: "Recap",
                                    text: summary
                                )
                            }
                        }
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var listSection: some View {
        ZenSection(
            title: "Meetings",
            caption: "Separate from dictation History. Audio stays on this Mac."
        ) {
            if viewModel.meetings.isEmpty {
                ZenPanel {
                    Text("No meetings yet.")
                        .font(ZenDesign.Typography.body)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .padding(ZenDesign.Spacing.md)
                }
            } else {
                VStack(spacing: ZenDesign.Spacing.sm) {
                    ForEach(viewModel.meetings) { meeting in
                        MeetingRow(
                            meeting: meeting,
                            isOpen: viewModel.openedID == meeting.id,
                            canRetry: viewModel.canRetry(meeting),
                            canCopy: meeting.originalTranscriptCiphertext != nil,
                            canDelete: viewModel.canDelete(meeting),
                            open: { viewModel.open(meeting.id) },
                            copy: { viewModel.copyOriginal(id: meeting.id) },
                            retry: { viewModel.retry(id: meeting.id) },
                            delete: { viewModel.delete(meeting.id) }
                        )
                    }
                }
            }
        }
    }

    private var statusTitle: String {
        if viewModel.isTranscribing { return "Transcribing…" }
        switch viewModel.record?.status {
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .incomplete: return "Incomplete"
        case .transcribing: return "Transcribing…"
        case .failed: return "Failed"
        case .complete: return "Saved"
        case .completeAtCap: return "Saved at 90:00"
        case .none: return "Idle"
        }
    }

    private func controlButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(ZenSecondaryButtonStyle())
            .frame(minHeight: 44)
    }

    private func transcriptColumn(
        title: String,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
            Text(title)
                .font(ZenDesign.Typography.captionStrong)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
            Text(text)
                .font(ZenDesign.Typography.body)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MeetingRow: View {
    let meeting: MeetingStore.Record
    let isOpen: Bool
    let canRetry: Bool
    let canCopy: Bool
    let canDelete: Bool
    let open: () -> Void
    let copy: () -> Void
    let retry: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: ZenDesign.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.displayTitle)
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    HStack(spacing: ZenDesign.Spacing.sm) {
                        Text(
                            MeetingViewModel.formatElapsed(
                                meeting.elapsedSeconds
                            )
                        )
                        Text(meeting.engineID ?? "—")
                        Text(listStatusTitle)
                    }
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
                Spacer(minLength: 8)
                if isOpen {
                    ZenBadge(text: "Open", kind: .accent)
                }
            }

            HStack(spacing: ZenDesign.Spacing.sm) {
                Button("Open", action: open)
                    .buttonStyle(ZenSecondaryButtonStyle())
                    .frame(minHeight: 44)
                if canCopy {
                    Button("Copy original", action: copy)
                        .buttonStyle(ZenSecondaryButtonStyle())
                        .frame(minHeight: 44)
                }
                if canRetry {
                    Button("Retry transcribe", action: retry)
                        .buttonStyle(ZenSecondaryButtonStyle())
                        .frame(minHeight: 44)
                }
                if canDelete {
                    ZenHoldToDeleteButton(
                        label: "Delete",
                        minWidth: 108,
                        action: delete
                    )
                }
            }
        }
        .padding(ZenDesign.Spacing.md)
        .background {
            RoundedRectangle(
                cornerRadius: ZenDesign.Radius.medium,
                style: .continuous
            )
            .fill(ZenDesign.Semantic.surface)
            .overlay {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.medium,
                    style: .continuous
                )
                .strokeBorder(
                    isOpen
                        ? ZenDesign.Semantic.accent
                        : ZenDesign.Semantic.border
                )
            }
        }
    }

    private var listStatusTitle: String {
        switch meeting.listStatus {
        case .recording: return "Recording"
        case .transcribed: return "Transcribed"
        case .summarized: return "Recapped"
        case .failed: return "Failed"
        }
    }
}
