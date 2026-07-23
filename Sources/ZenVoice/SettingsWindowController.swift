import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let viewModel: SettingsViewModel
    private let historyViewModel: HistoryViewModel
    private let insightsViewModel: InsightsViewModel
    private let voiceProfileViewModel: VoiceProfileViewModel
    private let modelManagerViewModel: ModelManagerViewModel
    private let refinementModelManagerViewModel:
        RefinementModelManagerViewModel
    private let applicationProfileViewModel:
        ApplicationProfileViewModel
    private let onboardingViewModel: OnboardingViewModel
    private var hasCenteredWindow = false

    init(
        viewModel: SettingsViewModel,
        historyViewModel: HistoryViewModel,
        insightsViewModel: InsightsViewModel,
        voiceProfileViewModel: VoiceProfileViewModel,
        modelManagerViewModel: ModelManagerViewModel,
        refinementModelManagerViewModel:
            RefinementModelManagerViewModel,
        applicationProfileViewModel:
            ApplicationProfileViewModel,
        onboardingViewModel: OnboardingViewModel,
        appState: AppState
    ) {
        self.viewModel = viewModel
        self.historyViewModel = historyViewModel
        self.insightsViewModel = insightsViewModel
        self.voiceProfileViewModel = voiceProfileViewModel
        self.modelManagerViewModel = modelManagerViewModel
        self.refinementModelManagerViewModel =
            refinementModelManagerViewModel
        self.applicationProfileViewModel =
            applicationProfileViewModel
        self.onboardingViewModel = onboardingViewModel
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
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
        window.backgroundColor = NSColor(
            red: 0.035,
            green: 0.037,
            blue: 0.045,
            alpha: 1
        )
        window.minSize = NSSize(width: 720, height: 500)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: ZenVoiceSettingsView(
                viewModel: viewModel,
                historyViewModel: historyViewModel,
                insightsViewModel: insightsViewModel,
                voiceProfileViewModel: voiceProfileViewModel,
                modelManagerViewModel: modelManagerViewModel,
                refinementModelManagerViewModel:
                    refinementModelManagerViewModel,
                applicationProfileViewModel:
                    applicationProfileViewModel,
                onboardingViewModel: onboardingViewModel,
                appState: appState
            )
        )
    }

    func show() {
        viewModel.refreshSystemStatus()
        historyViewModel.refresh()
        insightsViewModel.refresh()
        voiceProfileViewModel.refresh()
        modelManagerViewModel.refresh()
        refinementModelManagerViewModel.refresh()
        applicationProfileViewModel.refresh()
        if !hasCenteredWindow {
            window.center()
            hasCenteredWindow = true
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.cancelShortcutCapture()
    }
}
