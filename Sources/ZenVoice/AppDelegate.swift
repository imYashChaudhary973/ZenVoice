import AppKit
import AVFoundation
import Foundation
import ZenVoiceCore
import ZenVoiceStorage

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private let recorder = AudioRecorder()
    private let inserter = TextInserter()
    private let transcriptionQueue = DispatchQueue(
        label: "dev.yashchaudhary.ZenVoice.transcription",
        qos: .userInitiated
    )

    private var statusItem: NSStatusItem!
    private var startStopMenuItem: NSMenuItem!
    private var zenBarMenuItem: NSMenuItem!
    private var statusMessageMenuItem: NSMenuItem!
    private var zenBarController: ZenBarPanelController!
    private var globalHotKey: GlobalHotKey?
    private var transcriber: WhisperTranscriber?
    private var resetWorkItem: DispatchWorkItem?
    private var currentHotKeyConfiguration = HotKeyPreferences.load()
    private var settingsViewModel: SettingsViewModel!
    private var settingsWindowController: SettingsWindowController!
    private let historyPreferences = HistoryPreferences()
    private var dictationVault: DictationVault?
    private var activeHistoryID: UUID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureTranscriber()
        configureMenuBar()
        configureZenBar()
        configureHistoryStorage()
        configureHotKey()
        configureSettingsWindow()
        zenBarController.show()
        settingsWindowController.show()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        let historyID = activeHistoryID
        activeHistoryID = nil
        recorder.cancel()
        if let historyID {
            try? dictationVault?.discard(id: historyID)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            settingsWindowController.show()
        }
        return true
    }

    private func configureTranscriber() {
        do {
            transcriber = WhisperTranscriber(
                configuration: try ZenVoiceConfiguration.discover()
            )
        } catch {
            state.phase = .error(error.localizedDescription)
        }
    }

    private func configureHistoryStorage() {
        guard historyPreferences.isHistoryEnabled else {
            return
        }

        do {
            let vault = try DictationVault.live()
            dictationVault = vault
            try vault.recoverInterrupted(
                retainAudio: historyPreferences.retainsFailedAudio
            )
            try vault.purgeExpiredRecoveryAudio()
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        if let logo = BrandAssets.zenLogo?.copy() as? NSImage {
            logo.size = NSSize(width: 18, height: 18)
            logo.isTemplate = false
            statusItem.button?.image = logo
        } else {
            statusItem.button?.image = NSImage(
                systemSymbolName: "z.circle.fill",
                accessibilityDescription: "ZenVoice"
            )
        }

        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "Open ZenVoice…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        startStopMenuItem = NSMenuItem(
            title: startStopMenuTitle,
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        startStopMenuItem.target = self
        menu.addItem(startStopMenuItem)

        let copyItem = NSMenuItem(
            title: "Copy Last Transcript",
            action: #selector(copyLastTranscript),
            keyEquivalent: ""
        )
        copyItem.target = self
        menu.addItem(copyItem)

        menu.addItem(.separator())

        zenBarMenuItem = NSMenuItem(
            title: "Hide ZenBar",
            action: #selector(toggleZenBar),
            keyEquivalent: ""
        )
        zenBarMenuItem.target = self
        menu.addItem(zenBarMenuItem)

        statusMessageMenuItem = NSMenuItem(
            title: "Show Status Message",
            action: #selector(toggleStatusMessage),
            keyEquivalent: ""
        )
        statusMessageMenuItem.target = self
        statusMessageMenuItem.state = state.showsStatusMessage ? .on : .off
        menu.addItem(statusMessageMenuItem)

        let permissionItem = NSMenuItem(
            title: "Enable Auto-Paste Permission…",
            action: #selector(requestAccessibilityPermission),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit ZenVoice",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func configureZenBar() {
        zenBarController = ZenBarPanelController(
            state: state,
            toggleRecording: { [weak self] in
                self?.toggleRecording()
            },
            cancelRecording: { [weak self] in
                self?.cancelRecording()
            },
            finishRecording: { [weak self] in
                self?.finishRecording()
            }
        )
    }

    private func configureHotKey() {
        do {
            globalHotKey = try makeGlobalHotKey(
                configuration: currentHotKeyConfiguration
            )
        } catch {
            guard currentHotKeyConfiguration != .dictationDefault else {
                showError(error.localizedDescription)
                return
            }

            do {
                currentHotKeyConfiguration = .dictationDefault
                globalHotKey = try makeGlobalHotKey(
                    configuration: currentHotKeyConfiguration
                )
                HotKeyPreferences.save(currentHotKeyConfiguration)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    private func configureSettingsWindow() {
        settingsViewModel = SettingsViewModel(
            currentShortcut: currentHotKeyConfiguration,
            applyShortcut: { [weak self] configuration in
                guard let self else {
                    return .failure(
                        GlobalHotKey.HotKeyError.registrationFailed(
                            configuration.displayName
                        )
                    )
                }
                return self.applyHotKey(configuration)
            }
        )
        settingsWindowController = SettingsWindowController(
            viewModel: settingsViewModel,
            appState: state
        )
    }

    private func makeGlobalHotKey(
        configuration: HotKeyConfiguration
    ) throws -> GlobalHotKey {
        try GlobalHotKey(configuration: configuration) { [weak self] in
            self?.toggleRecording()
        }
    }

    private func applyHotKey(
        _ configuration: HotKeyConfiguration
    ) -> Result<Void, Error> {
        guard configuration.isValid else {
            return .failure(
                GlobalHotKey.HotKeyError.registrationFailed(
                    configuration.displayName
                )
            )
        }

        if configuration == currentHotKeyConfiguration {
            return .success(())
        }

        do {
            let replacement = try makeGlobalHotKey(
                configuration: configuration
            )
            globalHotKey = replacement
            currentHotKeyConfiguration = configuration
            HotKeyPreferences.save(configuration)
            updateStartStopMenuTitle()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private var startStopMenuTitle: String {
        let action = recorder.isRecording
            ? "Stop and Insert"
            : "Start Dictation"
        return "\(action)  \(currentHotKeyConfiguration.displayName)"
    }

    private func updateStartStopMenuTitle() {
        startStopMenuItem?.title = startStopMenuTitle
    }

    @objc private func toggleRecording() {
        if recorder.isRecording {
            finishRecording()
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        guard !state.isBusy else {
            return
        }

        if transcriber == nil {
            configureTranscriber()
            guard transcriber != nil else {
                return
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startRecorder()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startRecorder()
                    } else {
                        self?.showError("Microphone permission is required.")
                        self?.openMicrophoneSettings()
                    }
                }
            }
        case .denied:
            showError("Enable microphone access in System Settings.")
            openMicrophoneSettings()
        case .restricted:
            showError("Microphone access is restricted on this Mac.")
        @unknown default:
            showError("Microphone permission is unavailable.")
        }
    }

    private func startRecorder() {
        resetWorkItem?.cancel()
        state.resetAudioSamples()
        var historyDraft: DictationDraft?

        if historyPreferences.isHistoryEnabled {
            do {
                let vault = try resolvedVault()
                let id = UUID()
                let targetApplication = NSWorkspace.shared.frontmostApplication
                let draft = DictationDraft(
                    id: id,
                    language: transcriber?.language ?? "en",
                    modelID: transcriber?.modelID ?? "unknown",
                    targetBundleID: targetApplication?.bundleIdentifier,
                    targetAppName: targetApplication?.localizedName,
                    recoveryAudioURL: vault.recoveryAudioURL(for: id)
                )
                try vault.begin(draft)
                historyDraft = draft
                activeHistoryID = id
            } catch {
                showError(error.localizedDescription)
                return
            }
        }

        do {
            try recorder.start(
                recordingURL: historyDraft?.recoveryAudioURL
            ) { [weak self] level in
                DispatchQueue.main.async {
                    self?.state.appendAudioLevel(level)
                }
            }
            state.phase = .listening
            updateStartStopMenuTitle()
            if state.isZenBarVisible {
                zenBarController.show()
            }
        } catch {
            if let historyID = historyDraft?.id {
                try? dictationVault?.discard(id: historyID)
                activeHistoryID = nil
            }
            showError(error.localizedDescription)
        }
    }

    private func finishRecording() {
        guard let recordedAudio = recorder.stop(), let transcriber else {
            showError("No recording was captured.")
            return
        }
        let historyID = activeHistoryID
        activeHistoryID = nil

        if let historyID {
            do {
                try dictationVault?.markTranscribing(
                    id: historyID,
                    durationSeconds: recordedAudio.durationSeconds
                )
            } catch {
                handleTranscriptionFailure(
                    error,
                    recordedAudio: recordedAudio,
                    historyID: historyID
                )
                return
            }
        }

        state.phase = .transcribing
        updateStartStopMenuTitle()

        transcriptionQueue.async { [weak self] in
            do {
                let result = try transcriber.transcribe(
                    audioURL: recordedAudio.url
                )
                DispatchQueue.main.async {
                    self?.complete(
                        result: result,
                        recordedAudio: recordedAudio,
                        historyID: historyID
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self?.handleTranscriptionFailure(
                        error,
                        recordedAudio: recordedAudio,
                        historyID: historyID
                    )
                }
            }
        }
    }

    private func cancelRecording() {
        guard recorder.isRecording else {
            return
        }

        resetWorkItem?.cancel()
        let historyID = activeHistoryID
        activeHistoryID = nil
        recorder.cancel()
        if let historyID {
            try? dictationVault?.discard(id: historyID)
        }
        state.resetAudioSamples()
        state.phase = .idle
        updateStartStopMenuTitle()
    }

    private func complete(
        result: TranscriptionResult,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID?
    ) {
        var historySaveError: Error?
        if let historyID {
            do {
                try dictationVault?.storeTranscript(
                    id: historyID,
                    rawTranscript: result.rawTranscript,
                    finalTranscript: result.finalTranscript,
                    correctionCount: result.correctionCount
                )
                try dictationVault?.deleteRecoveryAudio(id: historyID)
            } catch {
                historySaveError = error
                try? dictationVault?.markFailed(
                    id: historyID,
                    message: error.localizedDescription,
                    retainAudio: historyPreferences.retainsFailedAudio
                )
            }
        } else {
            try? FileManager.default.removeItem(at: recordedAudio.url)
        }

        state.lastTranscript = result.finalTranscript
        state.phase = .inserting

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            switch self.inserter.insert(result.finalTranscript) {
            case .pasted:
                if let historyID, historySaveError == nil {
                    try? self.dictationVault?.markInsertion(
                        id: historyID,
                        outcome: .inserted
                    )
                }
                self.state.phase = .success
                self.scheduleIdleReset(after: 1.5)
            case .copiedOnly:
                if let historyID, historySaveError == nil {
                    try? self.dictationVault?.markInsertion(
                        id: historyID,
                        outcome: .copiedOnly
                    )
                }
                self.showError("Copied—enable Accessibility to auto-paste.")
            }

            if let historySaveError {
                self.showError(
                    "Inserted, but history was not saved: "
                        + historySaveError.localizedDescription
                )
            }
        }
    }

    private func handleTranscriptionFailure(
        _ error: Error,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID?
    ) {
        if let historyID {
            do {
                try dictationVault?.markFailed(
                    id: historyID,
                    message: error.localizedDescription,
                    retainAudio: historyPreferences.retainsFailedAudio
                )
            } catch {
                try? FileManager.default.removeItem(at: recordedAudio.url)
            }
        } else {
            try? FileManager.default.removeItem(at: recordedAudio.url)
        }
        showError(error.localizedDescription)
    }

    private func resolvedVault() throws -> DictationVault {
        if let dictationVault {
            return dictationVault
        }
        let vault = try DictationVault.live()
        dictationVault = vault
        return vault
    }

    private func showError(_ message: String) {
        state.phase = .error(message)
        updateStartStopMenuTitle()
        if state.isZenBarVisible {
            zenBarController?.show()
        }
        scheduleIdleReset(after: 4)
    }

    private func scheduleIdleReset(after delay: TimeInterval) {
        resetWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.state.phase = .idle
        }
        resetWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    @objc private func copyLastTranscript() {
        guard !state.lastTranscript.isEmpty else {
            showError("No transcript yet.")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.lastTranscript, forType: .string)
        state.phase = .success
        scheduleIdleReset(after: 1.5)
    }

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    @objc private func toggleZenBar() {
        state.isZenBarVisible.toggle()
        if state.isZenBarVisible {
            zenBarController.show()
            zenBarMenuItem.title = "Hide ZenBar"
        } else {
            zenBarController.hide()
            zenBarMenuItem.title = "Show ZenBar"
        }
    }

    @objc private func requestAccessibilityPermission() {
        inserter.requestAccessibilityPermission()
    }

    private func openMicrophoneSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleStatusMessage() {
        state.toggleStatusMessage()
        statusMessageMenuItem.state = state.showsStatusMessage ? .on : .off
    }

    @objc private func screenConfigurationChanged() {
        zenBarController.positionAtBottomCenter()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
