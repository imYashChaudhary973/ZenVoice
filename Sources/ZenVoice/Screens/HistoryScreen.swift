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
import ZenVoiceCore
import ZenVoiceStorage

struct HistoryScreen: View {
    @ObservedObject var viewModel: HistoryViewModel
    @State private var confirmsDeleteAll = false
    @State private var spellingRecord: DictationRecord?
    @State private var spellingSuggestions: [CorrectionSuggestion] = []

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            if !viewModel.hasMadeHistoryChoice {
                consentCard
            } else {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                    ZenTabStrip(
                        items: [
                            .init(tab: HistoryViewModel.Scope.all,
                                  title: "All dictations"),
                            .init(tab: HistoryViewModel.Scope.recovery,
                                  title: "Recovery Inbox",
                                  badge: viewModel.recoveryCount)
                        ],
                        selection: $viewModel.scope
                    )

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: ZenDesign.Spacing.sm) {
                            ZenSearchField(
                                placeholder: "Search transcripts or apps…",
                                text: $viewModel.searchText
                            )
                            .frame(maxWidth: .infinity)
                            deleteAllButton
                        }
                        VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                            ZenSearchField(
                                placeholder: "Search transcripts or apps…",
                                text: $viewModel.searchText
                            )
                            HStack {
                                Spacer()
                                deleteAllButton
                            }
                        }
                    }

                    if let error = viewModel.errorMessage {
                        ZenBanner(
                            kind: .danger,
                            icon: "exclamationmark.triangle",
                            text: error
                        )
                    }

                    if viewModel.filteredRecords.isEmpty {
                        emptyState
                    } else {
                        recordGroups
                    }

                    if viewModel.scope == .recovery {
                        ZenBanner(
                            kind: .info,
                            icon: "info.circle",
                            text:
                                "Temporary audio is deleted after every attempt — recovery keeps encrypted text partials, and audio only if you allowed it in Privacy."
                        )
                    }
                }
            }
        }
        .alert(
            deleteConfirmationTitle,
            isPresented: $confirmsDeleteAll
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                viewModel.deleteAll(in: viewModel.scope)
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
        .sheet(item: $spellingRecord) { record in
            SpellingCorrectionSheet(
                record: record,
                scope: viewModel.correctionScope(for: record),
                suggestions: spellingSuggestions,
                save: { source, replacement in
                    let saved = await viewModel.addSpellingCorrection(
                        source: source,
                        replacement: replacement,
                        for: record
                    )
                    if saved {
                        spellingRecord = nil
                    }
                    return saved
                },
                cancel: {
                    spellingRecord = nil
                }
            )
        }
    }

    private var deleteConfirmationTitle: String {
        switch viewModel.scope {
        case .all:
            return "Delete all dictations?"
        case .recovery:
            return "Delete the Recovery Inbox?"
        }
    }

    private var deleteConfirmationMessage: String {
        switch viewModel.scope {
        case .all:
            return
                "This permanently deletes \(viewModel.standardRecords.count) saved dictations. Recovery Inbox items are kept."
        case .recovery:
            return
                "This permanently deletes \(viewModel.recoveryRecords.count) Recovery Inbox items and any retained recovery audio. Saved dictations are kept."
        }
    }

    private var recordGroups: some View {
        ForEach(groupedRecords, id: \.title) { group in
            ZenSection(title: group.title) {
                LazyVStack(spacing: ZenDesign.Spacing.xs) {
                    ForEach(group.records) { record in
                        HistoryRecordRow(
                            record: record,
                            copy: { viewModel.copy(record) },
                            retry: { viewModel.retry(record) },
                            correctSpelling: {
                                Task { @MainActor in
                                    spellingSuggestions = await viewModel
                                        .spellingSuggestions(for: record)
                                    spellingRecord = record
                                }
                            },
                            setCategory: {
                                viewModel.setCategory($0, for: record)
                            },
                            delete: { viewModel.delete(record) }
                        )
                    }
                }
            }
        }
    }

    private var deleteAllButton: some View {
        Button("Delete All") {
            confirmsDeleteAll = true
        }
        .buttonStyle(
            ZenDestructiveButtonStyle(
                minWidth: 100,
                height: ZenDesign.Layout.hitTarget
            )
        )
        .disabled(viewModel.scopedRecords.isEmpty)
        .frame(minHeight: ZenDesign.Layout.hitTarget)
    }

    private var consentCard: some View {
        ZenPanel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 15) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .frame(width: 46, height: 46)
                        .background {
                            RoundedRectangle(
                                cornerRadius: 12, style: .continuous
                            )
                            .fill(ZenDesign.Semantic.surfaceRaised)
                        }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Keep a private local history?")
                            .font(ZenDesign.Typography.sectionTitle)
                            .foregroundStyle(
                                ZenDesign.Semantic.textPrimary
                            )
                        Text(
                            "ZenVoice can save encrypted transcripts so an interrupted paste never loses your words."
                        )
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ConsentFact(
                        icon: "key.fill",
                        text: "Transcript text is encrypted with a Keychain-protected key."
                    )
                    ConsentFact(
                        icon: "internaldrive",
                        text: "History stays on this Mac and is never synced."
                    )
                    ConsentFact(
                        icon: "waveform.slash",
                        text: "Successful audio is deleted after transcription."
                    )
                }

                HStack {
                    Button("Not Now") {
                        viewModel.declineHistory()
                    }
                    .buttonStyle(ZenSecondaryButtonStyle())
                    Spacer()
                    Button("Enable Local History") {
                        viewModel.enableHistory()
                    }
                    .buttonStyle(ZenPrimaryButtonStyle())
                }
            }
            .padding(ZenDesign.Spacing.md)
        }
    }

    private var emptyState: some View {
        ZenPanel {
            VStack(spacing: ZenDesign.Spacing.xs) {
                Image(
                    systemName: viewModel.scope == .recovery
                        ? "checkmark.circle" : "text.badge.checkmark"
                )
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                Text(
                    viewModel.scope == .recovery
                        ? "Recovery Inbox is empty"
                        : viewModel.historyEnabled
                            ? "Your next dictation will appear here"
                            : "History saving is paused"
                )
                .font(ZenDesign.Typography.sectionTitle)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
                Text(
                    viewModel.scope == .recovery
                        ? "When a dictation fails, anything usable lands here with Copy, Retry, and Delete."
                        : viewModel.historyEnabled
                            ? "Place the cursor anywhere, press your shortcut, and speak."
                            : "Existing records remain local until you delete them."
                )
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ZenDesign.Spacing.xxl)
        }
    }

    private var groupedRecords:
        [(title: String, records: [ZenVoiceStorage.DictationRecord])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: viewModel.filteredRecords) { record in
            calendar.startOfDay(for: record.startedAt)
        }
        return groups.keys.sorted(by: >).map { date in
            let title: String
            if calendar.isDateInToday(date) {
                title = "Today"
            } else if calendar.isDateInYesterday(date) {
                title = "Yesterday"
            } else {
                title = date.formatted(
                    .dateTime.weekday(.wide).month(.abbreviated).day()
                )
            }
            return (
                title: title,
                records: groups[date, default: []].sorted {
                    $0.startedAt > $1.startedAt
                }
            )
        }
    }
}

private struct SpellingCorrectionSheet: View {
    let record: DictationRecord
    let scope: CorrectionLanguageScope
    let suggestions: [CorrectionSuggestion]
    let save: (String, String) async -> Bool
    let cancel: () -> Void

    @State private var source = ""
    @State private var replacement = ""
    @State private var dismissedSuggestionIDs = Set<String>()
    @State private var showsSaveError = false

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Correct spelling")
                        .font(ZenDesign.Typography.pageTitle)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(
                        "Approve only the spelling you want ZenVoice to remember."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
                Spacer()
                ZenBadge(text: scope.displayName, kind: .neutral)
            }

            ZenPanel {
                Text(record.finalTranscript ?? "")
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(ZenDesign.Spacing.md)
            }

            if !visibleSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Possible matches")
                        .font(ZenDesign.Typography.captionStrong)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    ForEach(visibleSuggestions) { suggestion in
                        HStack(spacing: ZenDesign.Spacing.xs) {
                            Text("“\(suggestion.source)”")
                                .foregroundStyle(
                                    ZenDesign.Semantic.textSecondary
                                )
                            Image(systemName: "arrow.right")
                                .foregroundStyle(
                                    ZenDesign.Semantic.textTertiary
                                )
                            Text(suggestion.replacement)
                                .font(ZenDesign.Typography.bodyStrong)
                            Spacer()
                            Button("Accept") {
                                Task { @MainActor in
                                    showsSaveError = !(await save(
                                        suggestion.source,
                                        suggestion.replacement
                                    ))
                                }
                            }
                            .buttonStyle(ZenSecondaryButtonStyle())
                            ZenIconButton(
                                systemImage: "xmark",
                                label:
                                    "Dismiss suggestion \(suggestion.source)"
                            ) {
                                dismissedSuggestionIDs.insert(
                                    suggestion.id
                                )
                            }
                        }
                        .font(ZenDesign.Typography.body)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: ZenDesign.Spacing.xs) {
                spellingField(
                    title: "Incorrect spelling",
                    placeholder: "bild",
                    text: $source
                )
                Image(systemName: "arrow.right")
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .padding(.bottom, 9)
                spellingField(
                    title: "Preferred spelling",
                    placeholder: "build",
                    text: $replacement
                )
            }

            if showsSaveError {
                Text(
                    "This rule could not be saved. Check that the incorrect spelling appears in the transcript and does not already have a rule."
                )
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.danger)
            }

            HStack {
                Button("Cancel", action: cancel)
                    .buttonStyle(ZenSecondaryButtonStyle())
                Spacer()
                Button("Save correction") {
                    Task { @MainActor in
                        showsSaveError = !(await save(source, replacement))
                    }
                }
                .buttonStyle(ZenPrimaryButtonStyle())
                .disabled(
                    source.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                        || replacement.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
            }
        }
        .padding(ZenDesign.Spacing.lg)
        .frame(width: 560)
    }

    private var visibleSuggestions: [CorrectionSuggestion] {
        suggestions.filter {
            !dismissedSuggestionIDs.contains($0.id)
        }
    }

    private func spellingField(
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct HistoryRecordRow: View {
    let record: ZenVoiceStorage.DictationRecord
    let copy: () -> Void
    let retry: () -> Void
    let correctSpelling: () -> Void
    let setCategory: (DictationCategory) -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(iconTint.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: ZenDesign.Spacing.xs) {
                    Text(record.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    if let appName = record.targetAppName {
                        Text(appName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                ZenDesign.Semantic.textSecondary
                            )
                    }
                    if record.isPartial {
                        ZenBadge(text: "Partial", kind: .warn)
                    }
                    Text(record.category.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }

                Text(transcript)
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(
                        record.status == .failed
                            ? ZenDesign.Semantic.textSecondary
                            : ZenDesign.Semantic.textPrimary
                    )
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if record.finalTranscript != nil {
                    Text(
                        "\(record.wordCount) words · "
                            + "\(Int(record.wordsPerMinute.rounded())) wpm"
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
            }

            Spacer(minLength: 10)

            HStack(spacing: 7) {
                if record.status == .failed,
                   record.recoveryAudioURL != nil {
                    Button("Retry", action: retry)
                        .buttonStyle(ZenSecondaryButtonStyle())
                }

                if record.finalTranscript != nil {
                    Button("Copy", action: copy)
                        .buttonStyle(
                            ZenSecondaryButtonStyle(minWidth: 72)
                        )
                }

                Menu {
                    if record.finalTranscript != nil {
                        Button(
                            "Correct spelling…",
                            systemImage: "textformat.abc"
                        ) {
                            correctSpelling()
                        }
                    }
                    Menu("Category") {
                        ForEach(DictationCategory.allCases) { category in
                            Button {
                                setCategory(category)
                            } label: {
                                if record.category == category {
                                    Label(
                                        category.displayName,
                                        systemImage: "checkmark"
                                    )
                                } else {
                                    Text(category.displayName)
                                }
                            }
                        }
                    }
                    Button("Delete", role: .destructive, action: delete)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 26, height: 26)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More actions for this dictation")
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
                .strokeBorder(ZenDesign.Semantic.border)
            }
        }
    }

    private var transcript: String {
        if let transcript = record.finalTranscript {
            return transcript
        }
        return record.errorMessage ?? "This dictation did not finish."
    }

    private var icon: String {
        switch record.status {
        case .failed:
            return "exclamationmark.arrow.triangle.2.circlepath"
        case .inserted:
            return "checkmark"
        case .copiedOnly:
            return "doc.on.doc"
        default:
            return "waveform"
        }
    }

    private var iconTint: Color {
        record.status == .failed
            ? ZenDesign.Semantic.danger
            : ZenDesign.Semantic.textSecondary
    }
}

private extension DictationCategory {
    var icon: String {
        switch self {
        case .documents: "doc.text"
        case .email: "envelope"
        case .workMessages: "person.2"
        case .personalMessages: "message"
        case .aiPrompts: "sparkles"
        case .notes: "note.text"
        case .development: "chevron.left.forwardslash.chevron.right"
        case .other: "square.grid.2x2"
        }
    }
}

private struct ConsentFact: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ZenDesign.Semantic.success)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
        }
    }
}
