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
    private var pasteLastGlobalHotKey: GlobalHotKey?
    private var privateModeGlobalHotKey: GlobalHotKey?
    private var holdToDictateController: HoldToDictateController?
    private var transcriber: WhisperTranscriber?
    private var resetWorkItem: DispatchWorkItem?
    private var currentHotKeyConfiguration = HotKeyPreferences.load()
    private var pasteLastHotKeyConfiguration =
        HotKeyPreferences.loadPasteLast()
    private var privateModeHotKeyConfiguration =
        HotKeyPreferences.loadPrivateMode()
    private var settingsViewModel: SettingsViewModel!
    private var historyViewModel: HistoryViewModel!
    private var modelManagerViewModel: ModelManagerViewModel!
    private var settingsWindowController: SettingsWindowController!
    private let historyPreferences = HistoryPreferences()
    private var dictationVault: DictationVault?
    private var activeHistoryID: UUID?
    private var transcribingHistoryID: UUID?
    private var nonPersistentHistoryIDs: Set<UUID> = []
    private var holdKeyPressed = false
    private var holdStartedRecording = false
    private var recoveryExpiryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureTranscriber()
        configureMenuBar()
        configureZenBar()
        configureHistoryStorage()
        configureHotKey()
        configureHoldToDictate()
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
        let processingHistoryID = transcribingHistoryID
        activeHistoryID = nil
        transcribingHistoryID = nil
        let recordedAudio = recorder.stop()
        if let historyID {
            if nonPersistentHistoryIDs.contains(historyID)
                || historyPreferences.isPrivateModeEnabled
                || !historyPreferences.isHistoryEnabled {
                try? dictationVault?.discard(id: historyID)
            } else {
                try? dictationVault?.markFailed(
                    id: historyID,
                    message: "ZenVoice closed before this dictation completed.",
                    retainAudio: historyPreferences.retainsFailedAudio
                )
            }
        } else if let recordedAudio {
            try? FileManager.default.removeItem(at: recordedAudio.url)
        }
        if let processingHistoryID,
           nonPersistentHistoryIDs.contains(processingHistoryID)
            || historyPreferences.isPrivateModeEnabled
            || !historyPreferences.isHistoryEnabled {
            try? dictationVault?.discard(id: processingHistoryID)
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
        do {
            if historyPreferences.isHistoryEnabled {
                // Materialize the default so paused history can still display
                // records and paste-last can recover them after relaunch.
                historyPreferences.isHistoryEnabled = true
            }
            let vault = try DictationVault.live()
            dictationVault = vault
            try vault.recoverInterrupted(
                retainAudio: historyPreferences.retainsFailedAudio
            )
            try vault.purgeExpiredRecoveryAudio()
            scheduleRecoveryExpiry()
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

        let pasteLastItem = NSMenuItem(
            title: "Paste Last Dictation",
            action: #selector(pasteLastTranscript),
            keyEquivalent: ""
        )
        pasteLastItem.target = self
        menu.addItem(pasteLastItem)

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

        do {
            pasteLastGlobalHotKey = try makePasteLastGlobalHotKey(
                configuration: pasteLastHotKeyConfiguration
            )
        } catch {
            guard pasteLastHotKeyConfiguration != .pasteLastDefault else {
                showError(error.localizedDescription)
                return
            }

            do {
                pasteLastHotKeyConfiguration = .pasteLastDefault
                pasteLastGlobalHotKey = try makePasteLastGlobalHotKey(
                    configuration: pasteLastHotKeyConfiguration
                )
                HotKeyPreferences.savePasteLast(
                    pasteLastHotKeyConfiguration
                )
            } catch {
                showError(error.localizedDescription)
            }
        }

        do {
            privateModeGlobalHotKey = try makePrivateModeGlobalHotKey(
                configuration: privateModeHotKeyConfiguration
            )
        } catch {
            privateModeHotKeyConfiguration = .privateModeDefault
            do {
                privateModeGlobalHotKey = try makePrivateModeGlobalHotKey(
                    configuration: privateModeHotKeyConfiguration
                )
                HotKeyPreferences.savePrivateMode(
                    privateModeHotKeyConfiguration
                )
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    private func configureHoldToDictate() {
        let controller = HoldToDictateController(
            isEnabled: HotKeyPreferences.isHoldToDictateEnabled(),
            key: HotKeyPreferences.loadHoldKey()
        )
        controller.onPress = { [weak self] in
            self?.holdToDictatePressed()
        }
        controller.onRelease = { [weak self] in
            self?.holdToDictateReleased()
        }
        holdToDictateController = controller
    }

    private func configureSettingsWindow() {
        modelManagerViewModel = ModelManagerViewModel { [weak self] in
            self?.configureTranscriber()
            self?.settingsViewModel?.refreshSystemStatus()
        }
        settingsViewModel = SettingsViewModel(
            currentShortcut: currentHotKeyConfiguration,
            pasteLastShortcut: pasteLastHotKeyConfiguration,
            privateModeShortcut: privateModeHotKeyConfiguration,
            holdToDictateEnabled:
                HotKeyPreferences.isHoldToDictateEnabled(),
            holdKey: HotKeyPreferences.loadHoldKey(),
            applyShortcut: { [weak self] configuration in
                guard let self else {
                    return .failure(
                        GlobalHotKey.HotKeyError.registrationFailed(
                            configuration.displayName
                        )
                    )
                }
                return self.applyHotKey(configuration)
            },
            applyPasteLastShortcut: { [weak self] configuration in
                guard let self else {
                    return .failure(
                        GlobalHotKey.HotKeyError.registrationFailed(
                            configuration.displayName
                        )
                    )
                }
                return self.applyPasteLastHotKey(configuration)
            },
            applyPrivateModeShortcut: { [weak self] configuration in
                guard let self else {
                    return .failure(
                        GlobalHotKey.HotKeyError.registrationFailed(
                            configuration.displayName
                        )
                    )
                }
                return self.applyPrivateModeHotKey(configuration)
            },
            applyHoldToDictate: { [weak self] enabled, key in
                self?.applyHoldToDictate(enabled: enabled, key: key)
            }
        )
        historyViewModel = HistoryViewModel(
            preferences: historyPreferences,
            vaultProvider: { [weak self] in
                guard let self else {
                    throw DictationVaultError.database(
                        "ZenVoice is no longer running."
                    )
                }
                return try self.resolvedVault()
            },
            retryRecord: { [weak self] record in
                guard let self else {
                    return .failure(
                        DictationVaultError.database(
                            "ZenVoice is no longer running."
                        )
                    )
                }
                return self.retryHistoryRecord(record)
            },
            privacyChanged: { [weak self] in
                self?.handlePrivacyChanged()
            }
        )
        settingsWindowController = SettingsWindowController(
            viewModel: settingsViewModel,
            historyViewModel: historyViewModel,
            modelManagerViewModel: modelManagerViewModel,
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

    private func makePasteLastGlobalHotKey(
        configuration: HotKeyConfiguration
    ) throws -> GlobalHotKey {
        try GlobalHotKey(configuration: configuration) { [weak self] in
            self?.pasteLastTranscript()
        }
    }

    private func makePrivateModeGlobalHotKey(
        configuration: HotKeyConfiguration
    ) throws -> GlobalHotKey {
        try GlobalHotKey(configuration: configuration) { [weak self] in
            self?.togglePrivateMode()
        }
    }

    private func applyHotKey(
        _ configuration: HotKeyConfiguration
    ) -> Result<Void, Error> {
        guard configuration.isValid,
              configuration != pasteLastHotKeyConfiguration,
              configuration != privateModeHotKeyConfiguration else {
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

    private func applyPasteLastHotKey(
        _ configuration: HotKeyConfiguration
    ) -> Result<Void, Error> {
        guard configuration.isValid,
              configuration != currentHotKeyConfiguration,
              configuration != privateModeHotKeyConfiguration else {
            return .failure(
                GlobalHotKey.HotKeyError.registrationFailed(
                    configuration.displayName
                )
            )
        }
        if configuration == pasteLastHotKeyConfiguration {
            return .success(())
        }

        do {
            let replacement = try makePasteLastGlobalHotKey(
                configuration: configuration
            )
            pasteLastGlobalHotKey = replacement
            pasteLastHotKeyConfiguration = configuration
            HotKeyPreferences.savePasteLast(configuration)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func applyPrivateModeHotKey(
        _ configuration: HotKeyConfiguration
    ) -> Result<Void, Error> {
        guard configuration.isValid,
              configuration != currentHotKeyConfiguration,
              configuration != pasteLastHotKeyConfiguration else {
            return .failure(
                GlobalHotKey.HotKeyError.registrationFailed(
                    configuration.displayName
                )
            )
        }
        if configuration == privateModeHotKeyConfiguration {
            return .success(())
        }

        do {
            let replacement = try makePrivateModeGlobalHotKey(
                configuration: configuration
            )
            privateModeGlobalHotKey = replacement
            privateModeHotKeyConfiguration = configuration
            HotKeyPreferences.savePrivateMode(configuration)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func applyHoldToDictate(
        enabled: Bool,
        key: HoldKeyChoice
    ) {
        HotKeyPreferences.saveHoldToDictateEnabled(enabled)
        HotKeyPreferences.saveHoldKey(key)
        holdToDictateController?.update(isEnabled: enabled, key: key)
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

    private func beginRecording(startedByHold: Bool = false) {
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
            startRecorder(startedByHold: startedByHold)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted,
                       !startedByHold || self.holdKeyPressed {
                        self.startRecorder(startedByHold: startedByHold)
                    } else {
                        if !granted {
                            self.showError("Microphone permission is required.")
                            self.openMicrophoneSettings()
                        }
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

    private func startRecorder(startedByHold: Bool = false) {
        resetWorkItem?.cancel()
        state.resetAudioSamples()
        var historyDraft: DictationDraft?

        if historyPreferences.isHistoryEnabled,
           !historyPreferences.isPrivateModeEnabled {
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
            holdStartedRecording = startedByHold
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
        holdStartedRecording = false
        guard let recordedAudio = recorder.stop(), let transcriber else {
            showError("No recording was captured.")
            return
        }
        let historyID = activeHistoryID
        activeHistoryID = nil
        transcribingHistoryID = historyID

        if let historyID {
            do {
                try resolvedVault().markTranscribing(
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
        holdStartedRecording = false
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
        transcribingHistoryID = nil
        ModelBenchmarkStore.record(
            modelID: result.modelID,
            audioDurationSeconds: recordedAudio.durationSeconds,
            processingDurationSeconds: result.processingDurationSeconds
        )
        modelManagerViewModel?.refreshBenchmarks()
        let shouldPersist = historyID.map {
            nonPersistentHistoryIDs.remove($0) == nil
                && historyPreferences.isHistoryEnabled
                && !historyPreferences.isPrivateModeEnabled
        } ?? false
        var historySaveError: Error?
        if let historyID, shouldPersist {
            do {
                let vault = try resolvedVault()
                try vault.storeTranscript(
                    id: historyID,
                    rawTranscript: result.rawTranscript,
                    finalTranscript: result.finalTranscript,
                    correctionCount: result.correctionCount,
                    isPartial: result.isPartial
                )
                try vault.deleteRecoveryAudio(id: historyID)
            } catch {
                historySaveError = error
                try? resolvedVault().markFailed(
                    id: historyID,
                    message: error.localizedDescription,
                    retainAudio: historyPreferences.retainsFailedAudio
                )
            }
        } else {
            if let historyID {
                try? resolvedVault().discard(id: historyID)
            }
            try? FileManager.default.removeItem(at: recordedAudio.url)
        }

        state.lastTranscript = result.finalTranscript
        state.phase = .inserting

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            switch self.inserter.insert(result.finalTranscript) {
            case .pasted:
                if let historyID, shouldPersist, historySaveError == nil {
                    try? self.resolvedVault().markInsertion(
                        id: historyID,
                        outcome: .inserted
                    )
                }
                self.state.phase = .success
                self.historyViewModel?.refresh()
                self.scheduleIdleReset(after: 1.5)
            case .copiedOnly:
                if let historyID, shouldPersist, historySaveError == nil {
                    try? self.resolvedVault().markInsertion(
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
            self.historyViewModel?.refresh()
        }
    }

    private func handleTranscriptionFailure(
        _ error: Error,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID?
    ) {
        transcribingHistoryID = nil
        let shouldPersist = historyID.map {
            nonPersistentHistoryIDs.remove($0) == nil
                && historyPreferences.isHistoryEnabled
                && !historyPreferences.isPrivateModeEnabled
        } ?? false
        if let historyID, shouldPersist {
            do {
                try resolvedVault().markFailed(
                    id: historyID,
                    message: error.localizedDescription,
                    retainAudio: historyPreferences.retainsFailedAudio
                )
                scheduleRecoveryExpiry()
            } catch {
                try? FileManager.default.removeItem(at: recordedAudio.url)
            }
        } else {
            if let historyID {
                try? resolvedVault().discard(id: historyID)
            }
            try? FileManager.default.removeItem(at: recordedAudio.url)
        }
        historyViewModel?.refresh()
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

    @objc private func pasteLastTranscript() {
        let transcript: String?
        if !state.lastTranscript.isEmpty {
            transcript = state.lastTranscript
        } else if historyPreferences.hasEverEnabledHistory,
                  let dictationVault {
            transcript = try? dictationVault
                .recent(limit: 1)
                .first?
                .finalTranscript
        } else {
            transcript = nil
        }

        guard let transcript, !transcript.isEmpty else {
            showError("No saved dictation is available.")
            return
        }

        switch inserter.insert(transcript) {
        case .pasted:
            state.phase = .success
            scheduleIdleReset(after: 1.5)
        case .copiedOnly:
            showError("Copied—enable Accessibility to auto-paste.")
        }
    }

    private func holdToDictatePressed() {
        guard !recorder.isRecording, !state.isBusy else {
            return
        }
        holdKeyPressed = true
        beginRecording(startedByHold: true)
    }

    private func holdToDictateReleased() {
        holdKeyPressed = false
        guard holdStartedRecording, recorder.isRecording else {
            return
        }
        finishRecording()
    }

    private func togglePrivateMode() {
        let enabled = !historyPreferences.isPrivateModeEnabled
        historyViewModel?.setPrivateModeEnabled(enabled)
        if historyViewModel == nil {
            historyPreferences.isPrivateModeEnabled = enabled
            handlePrivacyChanged()
        }
        state.phase = enabled
            ? .error("Private Dictation on — nothing will be saved.")
            : .success
        scheduleIdleReset(after: 2)
    }

    private func handlePrivacyChanged() {
        guard !historyPreferences.isHistoryEnabled
                || historyPreferences.isPrivateModeEnabled else {
            return
        }
        if let activeHistoryID {
            nonPersistentHistoryIDs.insert(activeHistoryID)
            do {
                try dictationVault?.suppressPersistence(id: activeHistoryID)
            } catch {
                showError(
                    "Private Dictation could not update local history: "
                    + error.localizedDescription
                )
            }
        }
        if let transcribingHistoryID {
            nonPersistentHistoryIDs.insert(transcribingHistoryID)
            do {
                try dictationVault?.suppressPersistence(
                    id: transcribingHistoryID
                )
            } catch {
                showError(
                    "Private Dictation could not update local history: "
                    + error.localizedDescription
                )
            }
        }
    }

    private func scheduleRecoveryExpiry() {
        recoveryExpiryTimer?.invalidate()
        guard let vault = dictationVault,
              let expiry = try? vault.nextRecoveryExpiry() else {
            return
        }
        let delay = max(1, expiry.timeIntervalSinceNow)
        recoveryExpiryTimer = Timer.scheduledTimer(
            withTimeInterval: delay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = try? self.dictationVault?.purgeExpiredRecoveryAudio()
                self.historyViewModel?.refresh()
                self.scheduleRecoveryExpiry()
            }
        }
    }

    private func retryHistoryRecord(
        _ record: DictationRecord
    ) -> Result<Void, Error> {
        guard !state.isBusy else {
            return .failure(
                DictationVaultError.database(
                    "Finish the current dictation before retrying."
                )
            )
        }
        guard let audioURL = record.recoveryAudioURL,
              FileManager.default.fileExists(atPath: audioURL.path) else {
            return .failure(
                DictationVaultError.database(
                    "The recovery audio is no longer available."
                )
            )
        }
        guard let transcriber else {
            return .failure(
                DictationVaultError.database(
                    "The local transcription model is unavailable."
                )
            )
        }

        do {
            try resolvedVault().markTranscribing(
                id: record.id,
                durationSeconds: record.durationSeconds
            )
        } catch {
            return .failure(error)
        }

        state.phase = .transcribing
        transcribingHistoryID = record.id
        let recordedAudio = AudioRecorder.RecordedAudio(
            url: audioURL,
            durationSeconds: record.durationSeconds
        )
        transcriptionQueue.async { [weak self] in
            do {
                let result = try transcriber.transcribe(audioURL: audioURL)
                DispatchQueue.main.async {
                    self?.completeHistoryRetry(
                        result: result,
                        recordedAudio: recordedAudio,
                        historyID: record.id
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self?.handleTranscriptionFailure(
                        error,
                        recordedAudio: recordedAudio,
                        historyID: record.id
                    )
                }
            }
        }
        return .success(())
    }

    private func completeHistoryRetry(
        result: TranscriptionResult,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID
    ) {
        transcribingHistoryID = nil
        ModelBenchmarkStore.record(
            modelID: result.modelID,
            audioDurationSeconds: recordedAudio.durationSeconds,
            processingDurationSeconds: result.processingDurationSeconds
        )
        modelManagerViewModel?.refreshBenchmarks()
        guard nonPersistentHistoryIDs.remove(historyID) == nil,
              historyPreferences.isHistoryEnabled,
              !historyPreferences.isPrivateModeEnabled else {
            try? resolvedVault().discard(id: historyID)
            try? FileManager.default.removeItem(at: recordedAudio.url)
            showError("Private Dictation was enabled; this retry was not saved.")
            return
        }
        do {
            let vault = try resolvedVault()
            try vault.storeTranscript(
                id: historyID,
                rawTranscript: result.rawTranscript,
                finalTranscript: result.finalTranscript,
                correctionCount: result.correctionCount,
                isPartial: result.isPartial
            )
            try vault.deleteRecoveryAudio(id: historyID)
            state.lastTranscript = result.finalTranscript
            state.phase = .success
            historyViewModel.refresh()
            scheduleIdleReset(after: 1.5)
        } catch {
            handleTranscriptionFailure(
                error,
                recordedAudio: recordedAudio,
                historyID: historyID
            )
        }
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
