import SwiftUI
import ZenVoiceCore
import ZenVoiceStorage

private struct ZenFAQ: Identifiable {
    let id: Int
    let question: String
    let answer: String
    let tags: String
}

struct HelpScreen: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var onboardingViewModel: OnboardingViewModel
    let openShortcuts: () -> Void

    @State private var searchText = ""
    @State private var expandedFAQs: Set<Int> = []

    private static let faqs: [ZenFAQ] = [
        ZenFAQ(
            id: 1,
            question: "Does my voice ever leave this Mac?",
            answer:
                "No. Recording, transcription, refinement, history, and insights all run locally. ZenVoice has no accounts, no analytics, and no cloud transcription service. The only network use is downloading models you explicitly request — each one checksum-verified.",
            tags: "privacy cloud offline network"
        ),
        ZenFAQ(
            id: 2,
            question: "How do I start dictating?",
            answer:
                "Place the cursor in any text field and press your dictation shortcut. Speak while ZenBar shows the waveform, then press the shortcut again — the text is inserted where your cursor is. You can also enable hold-to-dictate in Shortcuts.",
            tags: "start dictate shortcut begin how"
        ),
        ZenFAQ(
            id: 3,
            question: "What is Private Dictation?",
            answer:
                "Use the private dictation shortcut to dictate without saving anything: no history entry, no insights, no recovery audio.",
            tags: "private incognito secret history"
        ),
        ZenFAQ(
            id: 4,
            question: "Why does ZenVoice need Accessibility permission?",
            answer:
                "macOS requires it to type the finished text into the active app. Without it, ZenVoice still works — the transcript is copied to your clipboard instead, and you paste manually.",
            tags: "accessibility permission paste insert"
        ),
        ZenFAQ(
            id: 5,
            question: "What happens if transcription fails mid-sentence?",
            answer:
                "Anything usable lands in the Recovery Inbox (History → Recovery) with Copy, Retry, and Delete actions. Temporary audio is deleted after every attempt either way.",
            tags: "fail crash recovery partial lost"
        ),
        ZenFAQ(
            id: 6,
            question: "How does Hinglish mode work?",
            answer:
                "With the verified Hinglish Apex model installed, the Hinglish profile writes Hindi-English speech in Latin script the way you'd type it. Other multilingual models are not offered for Hinglish because they lose code-switched English words.",
            tags: "hinglish hindi language apex latin"
        ),
        ZenFAQ(
            id: 7,
            question: "What does Instant Refine actually change?",
            answer:
                "Clean removes fillers, repeated words, and spoken restarts — never meaning. Agent Prompt formats your speech as a structured prompt. Both options run entirely on this Mac.",
            tags: "refine clean agent rewrite grammar"
        ),
        ZenFAQ(
            id: 8,
            question: "Which model should I download?",
            answer:
                "Open Models — ZenVoice measures this Mac and marks a recommendation. Fast favors latency, Balanced is the best accuracy per second for most machines, High Accuracy is the multilingual pick.",
            tags: "model download recommend fast balanced accuracy"
        ),
        ZenFAQ(
            id: 9,
            question: "Can I correct a word it keeps getting wrong?",
            answer:
                "Yes. Voice Profile → correction rules: add \"what I said → what I meant\". Rules are encrypted and deletable one by one, independent of History.",
            tags: "correction wrong word fix rules dictionary"
        ),
        ZenFAQ(
            id: 10,
            question: "How do I delete everything?",
            answer:
                "Privacy shows a live inventory of everything stored — encrypted transcripts, recovery audio, correction rules, downloaded models — each with its own delete control. There is no hidden data.",
            tags: "delete erase remove data reset"
        )
    ]

    private var filteredFAQs: [ZenFAQ] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else { return Self.faqs }
        return Self.faqs.filter {
            $0.question.lowercased().contains(query)
                || $0.answer.lowercased().contains(query)
                || $0.tags.contains(query)
        }
    }

    var body: some View {
        ZenScreen(
            title: "Help & FAQ",
            subtitle: "Short answers, no tickets."
        ) {
            quickActions
            cheatSheet
            faqCard
            aboutCard
        }
    }

    private var quickActions: some View {
        ZenPanel(padding: ZenDesign.Spacing.lg) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .frame(width: 34, height: 34)
                    .background {
                        RoundedRectangle(
                            cornerRadius: ZenDesign.Radius.small,
                            style: .continuous
                        )
                        .fill(ZenDesign.Semantic.surfaceRaised)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Replay the setup guide")
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(
                        "The same steps you saw on first launch — permissions, shortcut, language, model."
                    )
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                }
                Spacer()
                Button("Replay") {
                    onboardingViewModel.show()
                }
                .buttonStyle(ZenSecondaryButtonStyle())
            }
        }
    }

    private var cheatSheet: some View {
        ZenPanel(padding: ZenDesign.Spacing.lg) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Shortcut cheat-sheet")
                    .font(ZenDesign.Typography.sectionTitle)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .padding(.bottom, 10)

                cheatRow(
                    "Start / stop dictation",
                    viewModel.currentShortcut.displayName
                )
                Divider().overlay(ZenDesign.Semantic.border)
                cheatRow(
                    "Private dictation",
                    viewModel.privateModeShortcut.displayName
                )
                Divider().overlay(ZenDesign.Semantic.border)
                cheatRow(
                    "Paste latest dictation",
                    viewModel.pasteLastShortcut.displayName
                )
                Divider().overlay(ZenDesign.Semantic.border)

                HStack {
                    Text("Change any of these")
                        .font(ZenDesign.Typography.body)
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    Spacer()
                    Button("Open Shortcuts") {
                        openShortcuts()
                    }
                    .buttonStyle(.plain)
                    .font(ZenDesign.Typography.captionStrong)
                    .foregroundStyle(ZenDesign.Semantic.accent)
                }
                .frame(minHeight: 40)
            }
        }
    }

    private func cheatRow(_ title: String, _ combo: String) -> some View {
        HStack {
            Text(title)
                .font(ZenDesign.Typography.body)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
            Spacer()
            ZenKbdGroup(combo: combo)
        }
        .frame(minHeight: 40)
    }

    private var faqCard: some View {
        ZenPanel(padding: ZenDesign.Spacing.lg) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Frequently asked")
                        .font(ZenDesign.Typography.sectionTitle)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Spacer()
                    Text("\(filteredFAQs.count) of \(Self.faqs.count)")
                        .font(ZenDesign.Typography.monoSmall)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }

                ZenSearchField(
                    placeholder:
                        "Search answers — try “private”, “model”, “hinglish”…",
                    text: $searchText
                )

                if filteredFAQs.isEmpty {
                    VStack(spacing: 6) {
                        Text("No answer found")
                            .font(ZenDesign.Typography.bodyStrong)
                            .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        Text("Try a different word — or read the documentation in the repository.")
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(filteredFAQs) { faq in
                            if faq.id != filteredFAQs.first?.id {
                                Divider().overlay(ZenDesign.Semantic.border)
                            }
                            faqRow(faq)
                        }
                    }
                }
            }
        }
    }

    private func faqRow(_ faq: ZenFAQ) -> some View {
        let isExpanded = expandedFAQs.contains(faq.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpanded {
                    expandedFAQs.remove(faq.id)
                } else {
                    expandedFAQs.insert(faq.id)
                }
            } label: {
                HStack {
                    Text(faq.question)
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(faq.question)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                Text(faq.answer)
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                    .frame(maxWidth: 560, alignment: .leading)
            }
        }
    }

    private var aboutCard: some View {
        ZenPanel(padding: ZenDesign.Spacing.lg) {
            HStack(spacing: 12) {
                ZenBrandMark(size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ZenVoice")
                        .font(ZenDesign.Typography.bodyStrong)
                        .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    Text(aboutDetail)
                        .font(ZenDesign.Typography.monoSmall)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var aboutDetail: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        return "Version \(version ?? "dev") · macOS 14+ · Apple Silicon · local-first"
    }
}
