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

import AppKit
import SwiftUI
import ZenVoiceCore

/// Drives the dictation-time cloud-enhancement preview.
///
/// The view model is intentionally separate from `CloudAIViewModel` so the
/// dictation flow can enhance an arbitrary transcript without touching the
/// settings screen's "last transcript" state or the clipboard.
@MainActor
final class CloudAIDictationPreviewViewModel: ObservableObject {
    let original: String
    @Published private(set) var enhanced: String?
    @Published private(set) var isEnhancing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var providerName: String

    private let configuration: CloudAIConfiguration
    private let key: String
    private let engine: CloudAIEnhancementEngine
    private var enhancementTask: Task<Void, Never>?

    init(
        original: String,
        keyStore: CloudAIKeyStoring,
        engine: CloudAIEnhancementEngine = CloudAIEnhancementEngine()
    ) {
        self.original = original
        self.configuration = CloudAIPreferences.load()
        self.key = (try? keyStore.loadKey()) ?? ""
        self.engine = engine
        providerName = configuration.provider.displayName
    }

    deinit {
        enhancementTask?.cancel()
    }

    var isReady: Bool {
        configuration.isEnabled
            && !key.isEmpty
            && (try? configuration.resolvedEndpoint()) != nil
    }

    func enhance() {
        guard isReady else {
            errorMessage = CloudAIEnhancementError.missingAPIKey
                .localizedDescription
            return
        }
        enhancementTask?.cancel()
        isEnhancing = true
        errorMessage = nil
        enhanced = nil

        let configuration = configuration
        let key = key
        let engine = engine
        let transcript = original
        enhancementTask = Task { [weak self] in
            do {
                let result = try await engine.enhance(
                    transcript: transcript,
                    configuration: configuration,
                    apiKey: key
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.isEnhancing = false
                    self?.enhanced = result.enhanced
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.isEnhancing = false
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Abandons an in-flight request so the user is never stuck watching a
    /// spinner until the 30-second transport timeout.
    func cancelEnhancement() {
        enhancementTask?.cancel()
        enhancementTask = nil
        isEnhancing = false
    }
}

/// Compact preview window shown after a cloud-rung dictation finishes.
///
/// The original local transcript is on the left, the provider's version is on
/// the right, and the user accepts or discards before anything is inserted.
struct CloudAIDictationPreviewView: View {
    @StateObject var viewModel: CloudAIDictationPreviewViewModel
    let onComplete: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
            header

            if viewModel.isEnhancing {
                Spacer()
                VStack(spacing: ZenDesign.Spacing.sm) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Asking \(viewModel.providerName)…")
                            .font(ZenDesign.Typography.body)
                            .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    }
                    Button("Cancel and keep local transcript") {
                        viewModel.cancelEnhancement()
                        onComplete(nil)
                    }
                    .buttonStyle(ZenSecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else if let error = viewModel.errorMessage {
                errorBody(error)
            } else if let enhanced = viewModel.enhanced {
                comparisonBody(enhanced)
            } else {
                Spacer()
                ZenRow(
                    icon: "sparkles",
                    title: "No preview yet",
                    subtitle: "The enhancement will appear here once it finishes."
                )
                .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
        }
        .padding(ZenDesign.Spacing.lg)
        .frame(minWidth: 680, minHeight: 340)
        .background(ZenDesign.Semantic.canvas)
        .onAppear(perform: viewModel.enhance)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cloud enhancement")
                .font(ZenDesign.Typography.pageTitle)
                .foregroundStyle(ZenDesign.Semantic.textPrimary)
            Text(
                "Review what \(viewModel.providerName) returned before it "
                + "replaces your local transcript."
            )
            .font(ZenDesign.Typography.body)
            .foregroundStyle(ZenDesign.Semantic.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorBody(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
            ZenBanner(
                kind: .danger,
                icon: "exclamationmark.triangle",
                text: error
            )
            Text(
                "The local transcript is still available. You can keep it, "
                + "or close this window and try again."
            )
            .font(ZenDesign.Typography.caption)
            .foregroundStyle(ZenDesign.Semantic.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: ZenDesign.Spacing.sm) {
                Spacer()
                Button("Keep local transcript") {
                    onComplete(nil)
                }
                .buttonStyle(ZenSecondaryButtonStyle())
                Button("Retry") {
                    viewModel.enhance()
                }
                .buttonStyle(ZenPrimaryButtonStyle())
            }
        }
    }

    private func comparisonBody(_ enhanced: String) -> some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
            HStack(alignment: .top, spacing: ZenDesign.Spacing.sm) {
                previewColumn("Original", text: viewModel.original)
                previewColumn("Enhanced", text: enhanced)
            }

            HStack(spacing: ZenDesign.Spacing.sm) {
                Spacer()
                Button("Discard") {
                    onComplete(nil)
                }
                .buttonStyle(ZenSecondaryButtonStyle())
                Button("Accept") {
                    onComplete(enhanced)
                }
                .buttonStyle(ZenPrimaryButtonStyle())
            }
        }
    }

    private func previewColumn(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(ZenDesign.Typography.eyebrow)
                .tracking(1.5)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            ScrollView {
                Text(text)
                    .font(ZenDesign.Typography.body)
                    .foregroundStyle(ZenDesign.Semantic.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(ZenDesign.Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: ZenDesign.Radius.small)
                    .fill(ZenDesign.Semantic.surfaceRaised)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Window controller that hosts the dictation cloud preview and reports the
/// user's choice through a closure.
///
/// This is a non-activating floating panel, not an ordinary window, and that
/// choice is load-bearing. The transcript is inserted into whichever
/// application was frontmost when dictation ended, and accepting an
/// enhancement replaces that text in place. An ordinary window would activate
/// ZenVoice, make *it* frontmost, and the accessibility call that swaps the
/// text would then aim at the wrong process — dropping the replacement or
/// leaving the local transcript and the enhanced one both on screen.
/// A `.nonactivatingPanel` takes clicks without stealing focus, so the target
/// application stays frontmost the whole time.
@MainActor
final class CloudAIPreviewWindowController: NSWindowController {
    private let onComplete: (String?) -> Void
    private var hasCompleted = false

    init(
        original: String,
        keyStore: CloudAIKeyStoring,
        onComplete: @escaping (String?) -> Void
    ) {
        self.onComplete = onComplete
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [
                .titled,
                .closable,
                .utilityWindow,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )
        panel.title = "Cloud Enhancement Preview"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior.insert(.moveToActiveSpace)
        panel.appearance = NSAppearance(named: .darkAqua)
        let window: NSWindow = panel
        super.init(window: window)
        let viewModel = CloudAIDictationPreviewViewModel(
            original: original,
            keyStore: keyStore
        )
        window.contentViewController = NSHostingController(
            rootView: CloudAIDictationPreviewView(
                viewModel: viewModel,
                onComplete: { [weak self] text in
                    self?.complete(text)
                }
            )
        )
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        // `orderFrontRegardless` rather than `makeKeyAndOrderFront` plus
        // `NSApp.activate`: the panel needs to be visible and clickable, not
        // focused. See the type comment for why stealing focus here breaks
        // the text replacement.
        window?.orderFrontRegardless()
    }

    private func complete(_ text: String?) {
        guard !hasCompleted else { return }
        hasCompleted = true
        window?.close()
        onComplete(text)
    }
}

extension CloudAIPreviewWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // If the user closes the window without choosing, keep the local
        // transcript so nothing is lost.
        complete(nil)
    }
}
