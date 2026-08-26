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

struct LecturesScreen: View {
    @ObservedObject var viewModel: LectureViewModel
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
            title: "Lecture",
            caption: "Records on this Mac. The dictation hotkey does not start a lecture."
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(viewModel.elapsedLabel)
                            .font(ZenDesign.Typography.display)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            .monospacedDigit()
                            .accessibilityLabel("Elapsed \(viewModel.elapsedLabel)")
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
                            controlButton("Start", action: viewModel.start)
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
                                "Summarize",
                                action: viewModel.summarize
                            )
                            .disabled(
                                !cloudAIViewModel.isReady
                                    || !viewModel.canSummarize
                            )
                        }
                    }

                    if let original = viewModel.originalTranscript,
                       !original.isEmpty {
                        HStack(alignment: .top, spacing: ZenDesign.Spacing.md) {
                            transcriptColumn(
                                title: "Original transcript",
                                text: original
                            )
                            if let summary = viewModel.summary,
                               !summary.isEmpty {
                                transcriptColumn(
                                    title: "Summary",
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
            title: "Lectures",
            caption: "Separate from dictation History. Audio stays on this Mac."
        ) {
            if viewModel.lectures.isEmpty {
                ZenPanel {
                    Text("No lectures yet.")
                        .font(ZenDesign.Typography.body)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .padding(ZenDesign.Spacing.md)
                }
            } else {
                VStack(spacing: ZenDesign.Spacing.sm) {
                    ForEach(viewModel.lectures) { lecture in
                        LectureRow(
                            lecture: lecture,
                            isOpen: viewModel.openedID == lecture.id,
                            canRetry: viewModel.canRetry(lecture),
                            canCopy: lecture.originalTranscriptCiphertext != nil,
                            canDelete: viewModel.canDelete(lecture),
                            open: { viewModel.open(lecture.id) },
                            copy: { viewModel.copyOriginal(id: lecture.id) },
                            retry: { viewModel.retry(id: lecture.id) },
                            delete: { viewModel.delete(lecture.id) }
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

    private func controlButton(_ title: String, action: @escaping () -> Void) -> some View {
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

private struct LectureRow: View {
    let lecture: LectureStore.Record
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
                    Text(lecture.displayTitle)
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    HStack(spacing: ZenDesign.Spacing.sm) {
                        Text(LectureViewModel.formatElapsed(lecture.elapsedSeconds))
                        Text(lecture.engineID ?? "—")
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
                    ZenHoldToDeleteButton(label: "Delete", minWidth: 108, action: delete)
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
        switch lecture.listStatus {
        case .recording: return "Recording"
        case .transcribed: return "Transcribed"
        case .summarized: return "Summarized"
        case .failed: return "Failed"
        }
    }
}
