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
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xxl) {
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
        ZenSection(title: "Trigger") {
            ZenPanel {
                ZenRow(
                    icon: "mic",
                    title: "Start / stop dictation",
                    subtitle: "Press once to start, again to transcribe and insert"
                ) {
                    shortcutControls(
                        displayName: viewModel.currentShortcut.displayName,
                        isCapturing: viewModel.isCapturingShortcut,
                        resetLabel: "Reset dictation shortcut",
                        capture: {
                            if viewModel.isCapturingShortcut {
                                viewModel.cancelShortcutCapture()
                            } else {
                                viewModel.beginShortcutCapture()
                            }
                        },
                        reset: viewModel.resetShortcut
                    )
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "eye.slash",
                    title: "Private dictation",
                    subtitle: "Dictate without saving history, insights, or recovery audio"
                ) {
                    shortcutControls(
                        displayName: viewModel.privateModeShortcut.displayName,
                        isCapturing:
                            viewModel.isCapturingPrivateModeShortcut,
                        resetLabel: "Reset private dictation shortcut",
                        capture: {
                            if viewModel.isCapturingPrivateModeShortcut {
                                viewModel.cancelShortcutCapture()
                            } else {
                                viewModel.beginShortcutCapture(
                                    for: .privateMode
                                )
                            }
                        },
                        reset: viewModel.resetPrivateModeShortcut
                    )
                }
                ZenPanelDivider()
                ZenRow(
                    icon: "doc.on.doc",
                    title: "Paste latest dictation",
                    subtitle: "Re-insert the most recent transcript anywhere"
                ) {
                    shortcutControls(
                        displayName: viewModel.pasteLastShortcut.displayName,
                        isCapturing:
                            viewModel.isCapturingPasteLastShortcut,
                        resetLabel: "Reset paste shortcut",
                        capture: {
                            if viewModel.isCapturingPasteLastShortcut {
                                viewModel.cancelShortcutCapture()
                            } else {
                                viewModel.beginShortcutCapture(
                                    for: .pasteLast
                                )
                            }
                        },
                        reset: viewModel.resetPasteLastShortcut
                    )
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
                        icon: "keyboard.badge.ellipsis",
                        title: "Hold key",
                        subtitle:
                            "Select Change, then press the modifier you want to hold"
                    ) {
                        shortcutControls(
                            displayName: viewModel.holdKey.displayName,
                            isCapturing: viewModel.isCapturingHoldKey,
                            resetLabel: "Reset hold key",
                            capture: {
                                if viewModel.isCapturingHoldKey {
                                    viewModel.cancelShortcutCapture()
                                } else {
                                    viewModel.beginHoldKeyCapture()
                                }
                            },
                            reset: viewModel.resetHoldKey
                        )
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

    // MARK: ZenBar behavior

    private var zenBarSection: some View {
        ZenSection(title: "Behavior") {
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
    private func shortcutControls(
        displayName: String,
        isCapturing: Bool,
        resetLabel: String,
        capture: @escaping () -> Void,
        reset: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            ShortcutCaptureButton(
                displayName: displayName,
                isCapturing: isCapturing,
                action: capture
            )
            ZenIconButton(
                systemImage: "arrow.counterclockwise",
                label: resetLabel,
                action: reset
            )
        }
        .frame(width: 232, alignment: .trailing)
    }

}

struct ShortcutCaptureButton: View {
    let displayName: String
    let isCapturing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ZenDesign.Spacing.xs) {
                if isCapturing {
                    // Sits on the accent fill, so it has to be the on-accent
                    // colour — an accent-on-accent dot was invisible.
                    Circle()
                        .fill(ZenDesign.Semantic.textOnAccent)
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
                        .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)
                }
            }
            .font(ZenDesign.Typography.button)
            .foregroundStyle(
                isCapturing
                    ? ZenDesign.Semantic.textOnAccent
                    : ZenDesign.Semantic.textPrimary
            )
            .padding(.horizontal, 12)
            .frame(minWidth: 180, minHeight: ZenDesign.Layout.hitTarget)
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
        .buttonStyle(ZenPressButtonStyle())
        .accessibilityLabel(
            isCapturing
                ? "Cancel shortcut capture"
                : "Change shortcut. Current shortcut \(displayName)"
        )
    }
}
