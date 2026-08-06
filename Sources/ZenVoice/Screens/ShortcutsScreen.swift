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

struct ShortcutsScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ZenScreen(
            title: "Shortcuts",
            subtitle:
                "Global shortcuts work in any app. Change them anytime."
        ) {
            dictationSection
            zenBarSection

            ZenBanner(
                kind: .info,
                icon: "lightbulb",
                text:
                    "A two-modifier shortcut is less likely to conflict with other apps. Select Change, press one key with Command, Control, Option, or Shift — Escape cancels. Your choice stays on this Mac."
            )
        }
    }

    // MARK: dictation shortcuts

    private var dictationSection: some View {
        ZenSection(title: "Dictation") {
            VStack(alignment: .leading, spacing: ZenDesign.Spacing.sm) {
                ZenPanel {
                    ZenRow(
                        icon: "mic",
                        title: "Start / stop dictation",
                        subtitle: "Press once to start, again to transcribe and insert"
                    ) {
                        ShortcutCaptureButton(
                            displayName:
                                viewModel.currentShortcut.displayName,
                            isCapturing: viewModel.isCapturingShortcut,
                            action: {
                                if viewModel.isCapturingShortcut {
                                    viewModel.cancelShortcutCapture()
                                } else {
                                    viewModel.beginShortcutCapture()
                                }
                            }
                        )
                        ZenIconButton(
                            systemImage: "arrow.counterclockwise",
                            label: "Reset dictation shortcut"
                        ) {
                            viewModel.resetShortcut()
                        }
                    }
                    ZenPanelDivider()
                    ZenRow(
                        icon: "eye.slash",
                        title: "Private dictation",
                        subtitle: "Dictate without saving history, insights, or recovery audio"
                    ) {
                        ShortcutCaptureButton(
                            displayName:
                                viewModel.privateModeShortcut.displayName,
                            isCapturing:
                                viewModel.isCapturingPrivateModeShortcut,
                            action: {
                                if viewModel
                                    .isCapturingPrivateModeShortcut {
                                    viewModel.cancelShortcutCapture()
                                } else {
                                    viewModel.beginShortcutCapture(
                                        for: .privateMode
                                    )
                                }
                            }
                        )
                        ZenIconButton(
                            systemImage: "arrow.counterclockwise",
                            label: "Reset private dictation shortcut"
                        ) {
                            viewModel.resetPrivateModeShortcut()
                        }
                    }
                    ZenPanelDivider()
                    ZenRow(
                        icon: "doc.on.doc",
                        title: "Paste latest dictation",
                        subtitle: "Re-insert the most recent transcript anywhere"
                    ) {
                        ShortcutCaptureButton(
                            displayName:
                                viewModel.pasteLastShortcut.displayName,
                            isCapturing:
                                viewModel.isCapturingPasteLastShortcut,
                            action: {
                                if viewModel
                                    .isCapturingPasteLastShortcut {
                                    viewModel.cancelShortcutCapture()
                                } else {
                                    viewModel.beginShortcutCapture(
                                        for: .pasteLast
                                    )
                                }
                            }
                        )
                        ZenIconButton(
                            systemImage: "arrow.counterclockwise",
                            label: "Reset paste shortcut"
                        ) {
                            viewModel.resetPasteLastShortcut()
                        }
                    }
                    ZenPanelDivider()
                    ZenRow(
                        icon: "hand.tap",
                        title: "Hold to dictate",
                        subtitle:
                            "Hold a modifier, speak, then release to insert"
                    ) {
                        ZenSwitch(
                            isOn: Binding(
                                get: {
                                    viewModel.holdToDictateEnabled
                                },
                                set:
                                    viewModel.setHoldToDictateEnabled
                            ),
                            label: "Hold to dictate"
                        )
                    }
                    if viewModel.holdToDictateEnabled {
                        ZenPanelDivider()
                        ZenRow(
                            title: "Hold key",
                            subtitle:
                                "Select Change, then press the modifier you want to hold"
                        ) {
                            ShortcutCaptureButton(
                                displayName:
                                    viewModel.holdKey.displayName,
                                isCapturing:
                                    viewModel.isCapturingHoldKey,
                                action: {
                                    if viewModel.isCapturingHoldKey {
                                        viewModel.cancelShortcutCapture()
                                    } else {
                                        viewModel.beginHoldKeyCapture()
                                    }
                                }
                            )
                            ZenIconButton(
                                systemImage: "arrow.counterclockwise",
                                label: "Reset hold key"
                            ) {
                                viewModel.resetHoldKey()
                            }
                        }
                    }
                }

                if viewModel.holdToDictateEnabled,
                   viewModel.accessibilityStatus != .allowed {
                    HStack(spacing: ZenDesign.Spacing.sm) {
                        ZenBanner(
                            kind: .danger,
                            icon: "exclamationmark.shield",
                            text:
                                "Allow Accessibility so the hold key works in every app."
                        )
                        Button("Allow Access") {
                            viewModel.requestAccessibilityAccess()
                        }
                        .buttonStyle(ZenSecondaryButtonStyle())
                    }
                }

                if let error = viewModel.shortcutError {
                    ZenBanner(
                        kind: .danger,
                        icon: "exclamationmark.triangle",
                        text: error
                    )
                }
            }
        }
    }

    // MARK: ZenBar behavior

    private var zenBarSection: some View {
        ZenSection(title: "While dictating") {
            ZenPanel {
                ZenRow(
                    icon: "rectangle.bottomthird.inset.filled",
                    title: "Show ZenVoice at all times",
                    subtitle: "When off, the bar appears when dictation starts and hides after your text is inserted"
                ) {
                    ZenSwitch(
                        isOn: Binding(
                            get: { viewModel.showsZenVoiceAtAllTimes },
                            set: viewModel.setShowsZenVoiceAtAllTimes
                        ),
                        label: "Show ZenVoice at all times"
                    )
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "captions.bubble",
                    title: "ZenBar controls",
                    subtitle: "Cancel or finish a dictation from the bar itself — no shortcut needed. Live preview options live in Formatting."
                )
            }
        }
    }
}

struct ShortcutCaptureButton: View {
    let displayName: String
    let isCapturing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isCapturing {
                    Circle()
                        .fill(ZenDesign.Semantic.accent)
                        .frame(width: 7, height: 7)
                    Text("Press keys…")
                    Text("Cancel")
                        .foregroundStyle(
                            ZenDesign.Semantic.textOnAccent.opacity(0.72)
                        )
                } else {
                    ZenKbdGroup(combo: displayName)
                    Divider()
                        .frame(height: 16)
                    Text("Change")
                        .foregroundStyle(
                            ZenDesign.Semantic.textSecondary
                        )
                }
            }
            .font(ZenDesign.Typography.button)
            .foregroundStyle(
                isCapturing
                    ? ZenDesign.Semantic.textOnAccent
                    : ZenDesign.Semantic.textPrimary
            )
            .padding(.horizontal, 15)
            .frame(minWidth: 174, minHeight: 44)
            .background {
                RoundedRectangle(
                    cornerRadius: ZenDesign.Radius.small,
                    style: .continuous
                )
                .fill(
                    isCapturing
                        ? ZenDesign.Semantic.accent
                        : ZenDesign.Component.shortcutBackground
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ZenDesign.Radius.small,
                        style: .continuous
                    )
                    .strokeBorder(
                        isCapturing
                            ? ZenDesign.Component.focusRing
                            : ZenDesign.Semantic.borderStrong,
                        lineWidth: 1
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isCapturing
                ? "Cancel shortcut capture"
                : "Change shortcut. Current shortcut \(displayName)"
        )
    }
}
