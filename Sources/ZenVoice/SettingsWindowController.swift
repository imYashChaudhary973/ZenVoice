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

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let viewModel: SettingsViewModel
    private let historyViewModel: HistoryViewModel
    private let audioHistoryViewModel: AudioHistoryViewModel
    private let cloudAIViewModel: CloudAIViewModel
    private let updatesViewModel: UpdatesViewModel
    private let insightsViewModel: InsightsViewModel
    private let voiceProfileViewModel: VoiceProfileViewModel
    private let modelManagerViewModel: ModelManagerViewModel
    private let applicationProfileViewModel:
        ApplicationProfileViewModel
    private let onboardingViewModel: OnboardingViewModel
    private var hasCenteredWindow = false

    init(
        viewModel: SettingsViewModel,
        historyViewModel: HistoryViewModel,
        audioHistoryViewModel: AudioHistoryViewModel,
        cloudAIViewModel: CloudAIViewModel,
        updatesViewModel: UpdatesViewModel,
        insightsViewModel: InsightsViewModel,
        voiceProfileViewModel: VoiceProfileViewModel,
        modelManagerViewModel: ModelManagerViewModel,
        applicationProfileViewModel:
            ApplicationProfileViewModel,
        onboardingViewModel: OnboardingViewModel,
        appState: AppState,
        toggleRecording: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.historyViewModel = historyViewModel
        self.audioHistoryViewModel = audioHistoryViewModel
        self.cloudAIViewModel = cloudAIViewModel
        self.updatesViewModel = updatesViewModel
        self.insightsViewModel = insightsViewModel
        self.voiceProfileViewModel = voiceProfileViewModel
        self.modelManagerViewModel = modelManagerViewModel
        self.applicationProfileViewModel =
            applicationProfileViewModel
        self.onboardingViewModel = onboardingViewModel
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 800),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "ZenVoice"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        // The sidebar's vibrancy material is what fills the top-left corner,
        // so the window must not paint a `windowBackgroundColor` title bar
        // over it. `.clear` lets each column own its own surface; the content
        // column paints the canvas itself.
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 940, height: 660)
        // Menu-bar apps don't get full screen for free: the green zoom
        // button only offers it when the window opts in explicitly.
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: ZenVoiceSettingsView(
                viewModel: viewModel,
                historyViewModel: historyViewModel,
                audioHistoryViewModel: audioHistoryViewModel,
                cloudAIViewModel: cloudAIViewModel,
                updatesViewModel: updatesViewModel,
                insightsViewModel: insightsViewModel,
                voiceProfileViewModel: voiceProfileViewModel,
                modelManagerViewModel: modelManagerViewModel,
                applicationProfileViewModel:
                    applicationProfileViewModel,
                onboardingViewModel: onboardingViewModel,
                appState: appState,
                toggleRecording: toggleRecording
            )
        )
    }

    func show() {
        viewModel.refreshSystemStatus()
        // Permissions are granted in System Settings, so the window has to
        // watch for the change rather than sampling once on open.
        viewModel.beginWatchingPermissions()
        historyViewModel.refresh()
        insightsViewModel.refresh()
        voiceProfileViewModel.refresh()
        modelManagerViewModel.refresh()
        applicationProfileViewModel.refresh()
        // Accessory apps can't enter native full screen; become a regular
        // app while the window is open so the green button works.
        NSApp.setActivationPolicy(.regular)
        if !hasCenteredWindow {
            window.center()
            hasCenteredWindow = true
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window.orderOut(nil)
        viewModel.stopWatchingPermissions()
        NSApp.setActivationPolicy(.accessory)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.cancelShortcutCapture()
        viewModel.stopWatchingPermissions()
        // Back to a pure menu-bar presence once the window is gone.
        NSApp.setActivationPolicy(.accessory)
    }
}
