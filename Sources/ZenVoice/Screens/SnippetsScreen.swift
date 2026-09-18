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

/// Snippets: named voice shortcuts that insert text while dictating.
struct SnippetsScreen: View {
    @ObservedObject var viewModel: SnippetsViewModel

    /// The snippet being added or edited; nil hides the editor sheet.
    @State private var editingSnippet: VoiceSnippet?

    var body: some View {
        ZenScreen(
            icon: "text.append",
            title: "Snippets",
            subtitle: "Say a trigger, insert the text."
        ) {
            VStack(alignment: .leading, spacing: ZenDesign.Layout.contentGap) {
                snippetList
                Text(
                    "Say a trigger while dictating and ZenVoice inserts the "
                        + "expansion instead: scheduling links, addresses, "
                        + "sign-offs. Triggers tolerate small transcription "
                        + "differences."
                )
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                SnippetTryIt(viewModel: viewModel)
            }
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditor(
                initial: snippet,
                isNew: viewModel.snippets.allSatisfy { $0.id != snippet.id },
                onSave: { updated in
                    if viewModel.snippets.contains(where: {
                        $0.id == updated.id
                    }) {
                        viewModel.update(updated)
                    } else {
                        viewModel.add(
                            name: updated.name,
                            trigger: updated.trigger,
                            content: updated.content
                        )
                    }
                    editingSnippet = nil
                },
                onCancel: { editingSnippet = nil }
            )
        }
    }

    private var snippetList: some View {
        ZenSection(title: "Voice Snippets") {
            ZenPanel(padding: ZenDesign.Spacing.md) {
                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.snippets.isEmpty {
                        Text(
                            "No snippets yet. Add one and say its trigger "
                                + "while dictating."
                        )
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .padding(.bottom, ZenDesign.Spacing.sm)
                    } else {
                        ForEach(
                            Array(viewModel.snippets.enumerated()),
                            id: \.element
                        ) { index, snippet in
                            if index > 0 {
                                ZenPanelDivider()
                                    .padding(.vertical, ZenDesign.Spacing.xxs)
                            }
                            snippetRow(snippet)
                        }
                    }

                    addSnippetButton
                        .padding(.top, ZenDesign.Spacing.sm)
                }
            }
        }
    }

    private var addSnippetButton: some View {
        Button {
            editingSnippet = VoiceSnippet(
                name: "",
                trigger: "",
                content: "",
                enabled: true
            )
        } label: {
            HStack(spacing: ZenDesign.Spacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.accent)
                Text("Add Snippet")
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
            }
            .padding(.horizontal, ZenDesign.Spacing.sm)
            .frame(minHeight: 32)
            .background {
                Capsule().fill(ZenDesign.Component.shortcutBackground)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add Snippet")
    }

    private func snippetRow(_ snippet: VoiceSnippet) -> some View {
        HStack(alignment: .top, spacing: ZenDesign.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name)
                    .font(ZenDesign.Typography.bodyStrong)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .lineLimit(1)
                Text("\u{201C}\(snippet.trigger)\u{201D}")
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.accent)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(preview(snippet.content))
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: ZenDesign.Spacing.xs) {
                ZenIconButton(
                    systemImage: "pencil",
                    label: "Edit \(snippet.name)"
                ) {
                    editingSnippet = snippet
                }
                ZenIconButton(
                    systemImage: "trash",
                    label: "Delete \(snippet.name)",
                    isDanger: true
                ) {
                    viewModel.delete(snippet)
                }
                ZenSwitch(
                    isOn: Binding(
                        get: { snippet.enabled },
                        set: { viewModel.setEnabled(snippet, enabled: $0) }
                    ),
                    label: "\(snippet.name) enabled"
                )
            }
        }
        .padding(.vertical, ZenDesign.Spacing.xs)
        .accessibilityElement(children: .contain)
    }

    /// First line of the content, with an ↵ marker when more lines follow.
    private func preview(_ content: String) -> String {
        let lines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
        let first = lines.first.map(String.init) ?? ""
        return lines.count > 1 ? first + " ⏎" : first
    }
}

/// Add / edit form: name, spoken trigger, and the multi-line expansion.
private struct SnippetEditor: View {
    let initial: VoiceSnippet
    let isNew: Bool
    let onSave: (VoiceSnippet) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var trigger = ""
    @State private var content = ""
    @FocusState private var nameFocused: Bool

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !trigger.trimmingCharacters(in: .whitespaces).isEmpty
            && !content.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
            Text(isNew ? "Add Snippet" : "Edit Snippet")
                .font(ZenDesign.Typography.sectionTitle)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)

            VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
                Text("Name")
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                ZenTextInput(placeholder: "Scheduling link", text: $name)
            }

            VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
                Text("Spoken trigger")
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                ZenTextInput(
                    placeholder: "insert my scheduling link",
                    text: $trigger
                )
            }

            ZenTextArea(
                label: "Content",
                text: $content,
                hint: "Inserted exactly as written, line breaks included.",
                minHeight: 90
            )

            HStack(spacing: ZenDesign.Spacing.sm) {
                Spacer(minLength: 0)
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(ZenSecondaryButtonStyle())

                Button("Save") {
                    var updated = initial
                    updated.name = name.trimmingCharacters(in: .whitespaces)
                    updated.trigger = trigger.trimmingCharacters(
                        in: .whitespaces
                    )
                    updated.content = content
                    onSave(updated)
                }
                .buttonStyle(ZenPrimaryButtonStyle())
                .disabled(!isValid)
            }
        }
        .padding(ZenDesign.Spacing.lg)
        .onAppear {
            name = initial.name
            trigger = initial.trigger
            content = initial.content
            nameFocused = isNew
        }
    }
}

/// TRY IT: type what you would say; the matched expansion appears below.
private struct SnippetTryIt: View {
    @ObservedObject var viewModel: SnippetsViewModel

    var body: some View {
        ZenSection(title: "Try It") {
            ZenPanel(padding: ZenDesign.Spacing.md) {
                HStack(alignment: .top, spacing: ZenDesign.Spacing.md) {
                    VStack(alignment: .leading, spacing: ZenDesign.Spacing.xxs) {
                        Text("Test a phrase")
                            .font(ZenDesign.Typography.bodyStrong)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Text(
                            "Type what you would say and see which snippet "
                                + "would fire."
                        )
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: ZenDesign.Spacing.md)

                    ZenTextInput(
                        placeholder: "insert my scheduling link",
                        text: $viewModel.testPhrase
                    )
                    .frame(minWidth: 240)
                }

                HStack(spacing: ZenDesign.Spacing.xs) {
                    if let match = viewModel.testMatch {
                        Text(match.snippet.name)
                            .font(ZenDesign.Typography.captionStrong)
                            .foregroundStyle(ZenDesign.Semantic.accent)
                        Text("→")
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        Text(match.expansion)
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                            .textSelection(.enabled)
                    } else if !viewModel.testPhrase
                        .trimmingCharacters(in: .whitespaces)
                        .isEmpty {
                        Text("No snippet matches.")
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    } else {
                        Text("The result appears here.")
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    }
                }
                .padding(.top, ZenDesign.Spacing.xs)
            }
        }
    }
}
