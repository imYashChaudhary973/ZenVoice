import AppKit
import AVFoundation
import Combine
import Foundation
import ZenVoiceCore
import ZenVoiceRefinementRuntime
import ZenVoiceRuntime
import ZenVoiceStorage

/// Live preview text held back in case the whole-recording decode fails.
///
/// The preview is built from fragments and is less accurate, so it is only ever
/// used when the single-pass decode produced nothing at all.
private struct LivePreviewFallback {
    let rawTranscript: String
    let finalTranscript: String
    let correctionCount: Int
    let processingDurationSeconds: TimeInterval
    let correctionUsages: [CorrectionUsage]

    func processed(modelID: String) -> ProcessedTranscription? {
        guard !finalTranscript.isEmpty else {
            return nil
        }
        return ProcessedTranscription(
            result: TranscriptionResult(
                rawTranscript: rawTranscript,
                finalTranscript: finalTranscript,
                correctionCount: correctionCount,
                isPartial: true,
                modelID: modelID,
                processingDurationSeconds: processingDurationSeconds
            ),
            correctionUsages: correctionUsages
        )
    }
}

private struct ProcessedTranscription {
    let result: TranscriptionResult
    let correctionUsages: [CorrectionUsage]

    init(
        result: TranscriptionResult,
        correctionUsages: [CorrectionUsage]
    ) {
        self.result = result
        self.correctionUsages = correctionUsages
    }

    init(
        result: TranscriptionResult,
        refinement: InstantRefineResult,
        correctionApplication: CorrectionApplication?
    ) {
        let personalCorrectionCount =
            correctionApplication?.correctionCount ?? 0
        let finalText = correctionApplication?.text ?? refinement.text
        let totalCorrectionCount =
            refinement.correctionCount + personalCorrectionCount
        guard finalText != result.finalTranscript
                || totalCorrectionCount > 0 else {
            self.result = result
            correctionUsages = []
            return
        }
        self.result = TranscriptionResult(
            rawTranscript: result.rawTranscript,
            finalTranscript: finalText,
            correctionCount:
                result.correctionCount
                + totalCorrectionCount,
            isPartial: result.isPartial,
            modelID: result.modelID,
            processingDurationSeconds: result.processingDurationSeconds
        )
        correctionUsages = correctionApplication?.usages ?? []
    }
}

private struct ActiveDictationBehavior: Sendable {
    let languageProfile: LanguageProfile
    let refinementMode: InstantRefineMode
    let voiceCommandsEnabled: Bool
    let context: String

    static var global: ActiveDictationBehavior {
        ActiveDictationBehavior(
            languageProfile: LanguagePreferences.load(),
            refinementMode: InstantRefinePreferences.load(),
            voiceCommandsEnabled: false,
            context: ""
        )
    }
}

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
    private var languageMenuItem: NSMenuItem!
    private var zenBarController: ZenBarPanelController!
    private var globalHotKey: GlobalHotKey?
    private var pasteLastGlobalHotKey: GlobalHotKey?
    private var privateModeGlobalHotKey: GlobalHotKey?
    private var holdToDictateController: HoldToDictateController?
    private var transcriber: WhisperTranscriber?
    private var resetWorkItem: DispatchWorkItem?
    private var stateObservers: Set<AnyCancellable> = []
    private var currentHotKeyConfiguration = HotKeyPreferences.load()
    private var pasteLastHotKeyConfiguration =
        HotKeyPreferences.loadPasteLast()
    private var privateModeHotKeyConfiguration =
        HotKeyPreferences.loadPrivateMode()
    private var settingsViewModel: SettingsViewModel!
    private var historyViewModel: HistoryViewModel!
    private var insightsViewModel: InsightsViewModel!
    private var voiceProfileViewModel: VoiceProfileViewModel!
    private var modelManagerViewModel: ModelManagerViewModel!
    private var refinementModelManagerViewModel:
        RefinementModelManagerViewModel!
    private var applicationProfileViewModel:
        ApplicationProfileViewModel!
    private let onboardingViewModel = OnboardingViewModel(
        showAtLaunch: OnboardingPreferences.shouldPresent()
    )
    private var settingsWindowController: SettingsWindowController!
    private let refinementCoordinator =
        LocalRefinementCoordinator()
    private let historyPreferences = HistoryPreferences()
    private let learningPreferences = LocalLearningPreferences()
    private var dictationVault: DictationVault?
    private var activeHistoryID: UUID?
    private var transcribingHistoryID: UUID?
    private var nonPersistentHistoryIDs: Set<UUID> = []
    private var holdKeyPressed = false
    private var holdStartedRecording = false
    private var recoveryExpiryTimer: Timer?
    private var livePreviewTimer: Timer?
    private var liveSessionID = UUID()
    private var liveCommittedSampleIndex = 0
    private var livePreviewInFlight = false
    private var liveStableRawTranscript = ""
    private var liveStableFinalTranscript = ""
    private var livePendingStableTranscript = ""
    private var liveInsertedStableTranscript = ""
    private var liveStableCorrectionCount = 0
    private var liveStableProcessingDuration: TimeInterval = 0
    private var liveCorrectionUsages: [CorrectionUsage] = []
    private var liveStreamingInsertionBlocked = false
    private var liveTargetProcessIdentifier: pid_t?
    private var liveSamplesEnabledForRecording = false
    private var activeDictationBehavior =
        ActiveDictationBehavior.global

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureTranscriber()
        configureRefiner()
        configureMenuBar()
        configureZenBar()
        configureHistoryStorage()
        configureHotKey()
        configureHoldToDictate()
        configureSettingsWindow()
        settingsWindowController.show()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(microphoneDisconnected(_:)),
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(microphoneConnected(_:)),
            name: AVCaptureDevice.wasConnectedNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        livePreviewTimer?.invalidate()
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

    private func configureRefiner() {
        refinementCoordinator.update(modelURL: nil)
        guard let model =
            RefinementModelSelectionPreferences.load(),
              let url =
                try? VerifiedRefinementModelCatalog.installedURL(
                    for: model
                ) else {
            return
        }
        let coordinator = refinementCoordinator
        DispatchQueue.global(qos: .utility).async {
            let isVerified =
                (try? VerifiedRefinementModelCatalog.verify(
                    url,
                    for: model
                )) == true
            guard isVerified,
                  RefinementModelSelectionPreferences.load()?.id
                    == model.id else {
                return
            }
            coordinator.update(modelURL: url)
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
            title: "Show ZenVoice at all times",
            action: #selector(toggleZenBar),
            keyEquivalent: ""
        )
        zenBarMenuItem.target = self
        zenBarMenuItem.state =
            state.showsZenVoiceAtAllTimes ? .on : .off
        menu.addItem(zenBarMenuItem)

        statusMessageMenuItem = NSMenuItem(
            title: "Show Status Message",
            action: #selector(toggleStatusMessage),
            keyEquivalent: ""
        )
        statusMessageMenuItem.target = self
        statusMessageMenuItem.state = state.showsStatusMessage ? .on : .off
        menu.addItem(statusMessageMenuItem)

        languageMenuItem = NSMenuItem(
            title: languageMenuTitle,
            action: nil,
            keyEquivalent: ""
        )
        let languageMenu = NSMenu(title: "Dictation Language")
        for (index, profile) in quickLanguageProfiles.enumerated() {
            let item = NSMenuItem(
                title: profile.displayName,
                action: #selector(selectQuickLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state =
                profile == state.languageProfile ? .on : .off
            languageMenu.addItem(item)
        }
        languageMenuItem.submenu = languageMenu
        menu.addItem(languageMenuItem)

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
        state.$phase
            .combineLatest(state.$showsZenVoiceAtAllTimes)
            .sink { [weak self] phase, showsAtAllTimes in
                self?.updateZenBarPresentation(
                    phase: phase,
                    showsAtAllTimes: showsAtAllTimes
                )
            }
            .store(in: &stateObservers)
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

        announceReplacedShortcutsIfNeeded()
    }

    /// A shortcut that had to be replaced on load is worth saying out loud. The
    /// alternative is the user pressing keys that quietly do nothing while the
    /// settings screen appears to agree with them.
    private func announceReplacedShortcutsIfNeeded() {
        let replaced = HotKeyPreferences.replacedShortcuts
        guard !replaced.isEmpty else {
            return
        }

        showError("Shortcut changed: \(replaced.joined(separator: ", "))")
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
        refinementModelManagerViewModel =
            RefinementModelManagerViewModel { [weak self] in
                self?.configureRefiner()
            }
        applicationProfileViewModel = ApplicationProfileViewModel()
        settingsViewModel = SettingsViewModel(
            currentShortcut: currentHotKeyConfiguration,
            pasteLastShortcut: pasteLastHotKeyConfiguration,
            privateModeShortcut: privateModeHotKeyConfiguration,
            holdToDictateEnabled:
                HotKeyPreferences.isHoldToDictateEnabled(),
            holdKey: HotKeyPreferences.loadHoldKey(),
            showsZenVoiceAtAllTimes:
                state.showsZenVoiceAtAllTimes,
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
            },
            applyZenBarPreference: { [weak self] enabled in
                self?.state.setShowsZenVoiceAtAllTimes(enabled)
            },
            applyLanguageProfile: { [weak self] profile in
                guard let self else {
                    return .failure(
                        ZenVoiceConfiguration.ConfigurationError.modelMissing
                    )
                }
                return self.applyLanguageProfile(profile)
            },
            canRunAudioDoctor: { [weak self] in
                guard let self else {
                    return false
                }
                return !self.recorder.isRecording && !self.state.isBusy
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
        insightsViewModel = InsightsViewModel(
            vaultProvider: { [weak self] in
                guard let self else {
                    throw DictationVaultError.database(
                        "ZenVoice is no longer running."
                    )
                }
                return try self.resolvedVault()
            }
        )
        voiceProfileViewModel = VoiceProfileViewModel(
            vaultProvider: { [weak self] in
                guard let self else {
                    throw DictationVaultError.database(
                        "ZenVoice is no longer running."
                    )
                }
                return try self.resolvedVault()
            }
        )
        settingsWindowController = SettingsWindowController(
            viewModel: settingsViewModel,
            historyViewModel: historyViewModel,
            insightsViewModel: insightsViewModel,
            voiceProfileViewModel: voiceProfileViewModel,
            modelManagerViewModel: modelManagerViewModel,
            refinementModelManagerViewModel:
                refinementModelManagerViewModel,
            applicationProfileViewModel:
                applicationProfileViewModel,
            onboardingViewModel: onboardingViewModel,
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

    private var quickLanguageProfiles: [LanguageProfile] {
        [
            .english,
            .hinglish,
            LanguageProfile(
                inputLanguageCode: "es",
                outputMode: .spokenLanguage
            ),
            LanguageProfile(
                inputLanguageCode: "fr",
                outputMode: .spokenLanguage
            ),
            LanguageProfile(
                inputLanguageCode: "zh",
                outputMode: .spokenLanguage
            ),
            LanguageProfile(
                inputLanguageCode: "ar",
                outputMode: .spokenLanguage
            ),
            LanguageProfile(
                inputLanguageCode: LanguageProfile.automaticCode,
                outputMode: .spokenLanguage
            )
        ]
    }

    private var languageMenuTitle: String {
        "Language: \(state.languageProfile.displayName)"
    }

    private func applyLanguageProfile(
        _ profile: LanguageProfile
    ) -> Result<Void, Error> {
        do {
            let configuration = try ZenVoiceConfiguration.discover(
                languageProfile: profile
            )
            LanguagePreferences.save(profile)
            state.languageProfile = profile
            transcriber = WhisperTranscriber(configuration: configuration)
            updateLanguageMenu()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func updateLanguageMenu() {
        languageMenuItem?.title = languageMenuTitle
        for (index, item) in
            (languageMenuItem?.submenu?.items ?? []).enumerated() {
            guard quickLanguageProfiles.indices.contains(index) else {
                continue
            }
            item.state =
                quickLanguageProfiles[index] == state.languageProfile
                    ? .on
                    : .off
        }
    }

    @objc private func selectQuickLanguage(_ sender: NSMenuItem) {
        guard quickLanguageProfiles.indices.contains(sender.tag) else {
            return
        }
        switch applyLanguageProfile(quickLanguageProfiles[sender.tag]) {
        case .success:
            settingsViewModel?.refreshSystemStatus()
        case .failure(let error):
            showError(error.localizedDescription)
        }
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
        let capturesLiveSamples =
            LiveDictationPreferences.isPreviewEnabled()
        let targetApplication =
            NSWorkspace.shared.frontmostApplication
        guard let dictationBehavior = resolvedDictationBehavior(
            targetBundleIdentifier:
                targetApplication?.bundleIdentifier
        ) else {
            return
        }
        activeDictationBehavior = dictationBehavior
        state.languageProfile = dictationBehavior.languageProfile

        if historyPreferences.isHistoryEnabled,
           !historyPreferences.isPrivateModeEnabled {
            do {
                let vault = try resolvedVault()
                let id = UUID()
                let category = ApplicationCategoryClassifier.category(
                    bundleIdentifier: targetApplication?.bundleIdentifier,
                    appName: targetApplication?.localizedName
                )
                let draft = DictationDraft(
                    id: id,
                    language:
                        dictationBehavior.languageProfile
                            .inputLanguageCode,
                    modelID: transcriber?.modelID ?? "unknown",
                    targetBundleID: targetApplication?.bundleIdentifier,
                    targetAppName: targetApplication?.localizedName,
                    category: category,
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
                recordingURL: historyDraft?.recoveryAudioURL,
                capturesLiveSamples: capturesLiveSamples
            ) { [weak self] level in
                DispatchQueue.main.async {
                    self?.state.appendAudioLevel(level)
                }
            }
            liveSamplesEnabledForRecording = capturesLiveSamples
            settingsViewModel.clearNextDictationContext()
            state.phase = .listening
            beginLivePreviewSession()
            holdStartedRecording = startedByHold
            updateStartStopMenuTitle()
        } catch {
            liveSamplesEnabledForRecording = false
            if let historyID = historyDraft?.id {
                try? dictationVault?.discard(id: historyID)
                activeHistoryID = nil
            }
            showError(error.localizedDescription)
        }
    }

    private func resolvedDictationBehavior(
        targetBundleIdentifier: String?
    ) -> ActiveDictationBehavior? {
        let profile = ApplicationProfilePreferences.profile(
            for: targetBundleIdentifier
        )
        let languageProfile =
            profile?.languageProfile ?? LanguagePreferences.load()
        let capability =
            ModelSelectionPreferences.load()?.languageCapability
            ?? transcriber?.languageCapability
            ?? .english
        guard languageProfile.isCompatible(with: capability) else {
            showError(
                "\(languageProfile.displayName) requires a multilingual Whisper model. Select one in Models."
            )
            return nil
        }
        return ActiveDictationBehavior(
            languageProfile: languageProfile,
            refinementMode:
                profile?.refinementMode
                ?? InstantRefinePreferences.load(),
            voiceCommandsEnabled:
                profile?.voiceCommandsEnabled
                ?? LocalVoiceCommandPreferences.isEnabled(),
            context:
                settingsViewModel.sanitizedNextDictationContext
        )
    }

    private func finishRecording() {
        holdStartedRecording = false
        let usesLivePreview = liveSamplesEnabledForRecording
        liveSamplesEnabledForRecording = false
        stopLivePreviewScheduling(invalidatePending: true)
        let recordedAudio = recorder.stop(
            preserveLiveSamples: usesLivePreview
        )

        // Live preview text is exactly that — a preview. Whisper is markedly
        // more accurate when it hears a whole utterance than when it is fed the
        // fragments the pause detector cut, because words either side of a cut
        // lose their context. So unless preview text has already been inserted
        // into the target app, the committed transcript comes from decoding the
        // complete recording in one pass. ZenVoiceAccuracyChecks measures the
        // gap the two strategies produce.
        let completesFromSegments = DictationCompletionStrategy.resolve(
            usesLivePreview: usesLivePreview,
            hasInsertedPreviewText: !liveInsertedStableTranscript.isEmpty
        ) == .segments

        let remainingSamples = completesFromSegments
            ? recorder.samples(after: liveCommittedSampleIndex)
            : []
        recorder.releaseCapturedSamples()
        guard let recordedAudio, let transcriber else {
            resetLivePreviewSession()
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
        let correctionVault = dictationVault
        let appliesCorrectionRules =
            learningPreferences.appliesCorrectionRules
        let behavior = activeDictationBehavior

        if completesFromSegments {
            // Preview text is already on screen, but it was decoded from
            // fragments and the whole recording decodes more accurately. Try to
            // verify and swap what was inserted for the better transcript; only
            // if that cannot be done safely does the fragment path stand.
            let insertedText = liveInsertedStableTranscript
            transcriptionQueue.async { [weak self] in
                guard let upgrade = self?.wholeRecordingUpgrade(
                    transcriber: transcriber,
                    recordedAudio: recordedAudio,
                    behavior: behavior,
                    correctionVault: correctionVault,
                    appliesCorrectionRules: appliesCorrectionRules
                ) else {
                    self?.completeFromSegments(
                        transcriber: transcriber,
                        recordedAudio: recordedAudio,
                        historyID: historyID,
                        behavior: behavior,
                        remainingSamples: remainingSamples,
                        correctionVault: correctionVault,
                        appliesCorrectionRules: appliesCorrectionRules
                    )
                    return
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    let replaced = self.inserter.replaceTextBeforeCaret(
                        insertedText + " ",
                        with: upgrade.result.finalTranscript + " "
                    )
                    guard replaced == .replaced else {
                        self.transcriptionQueue.async {
                            self.completeFromSegments(
                                transcriber: transcriber,
                                recordedAudio: recordedAudio,
                                historyID: historyID,
                                behavior: behavior,
                                remainingSamples: remainingSamples,
                                correctionVault: correctionVault,
                                appliesCorrectionRules: appliesCorrectionRules
                            )
                        }
                        return
                    }
                    self.resetLivePreviewSession()
                    self.state.liveTranscriptPreview = ""
                    // The text is already in place, so there is nothing left
                    // to insert.
                    self.complete(
                        processed: upgrade,
                        recordedAudio: recordedAudio,
                        historyID: historyID,
                        insertionText: "",
                        hasPriorInsertion: true
                    )
                }
            }
            return
        }

        // The single-pass decode supersedes any preview text, but keep that
        // text as a fallback: if decoding the whole recording finds no speech
        // we would rather hand over an imperfect preview than lose the
        // dictation outright.
        let previewFallback = LivePreviewFallback(
            rawTranscript: liveStableRawTranscript,
            finalTranscript: liveStableFinalTranscript,
            correctionCount: liveStableCorrectionCount,
            processingDurationSeconds: liveStableProcessingDuration,
            correctionUsages: liveCorrectionUsages
        )
        let previewTargetProcess = liveTargetProcessIdentifier
        resetLivePreviewSession()
        state.liveTranscriptPreview = ""

        // Decoding the whole recording is more accurate but takes about a
        // second, and the user is staring at nothing for all of it. Since the
        // preview already knows roughly what they said, put that on screen now
        // and swap in the accurate transcript when it arrives — they get
        // immediate feedback and the better text.
        var insertedPreview = ""
        if !previewFallback.finalTranscript.isEmpty,
           AXIsProcessTrusted(),
           NSWorkspace.shared.frontmostApplication?.processIdentifier
            == previewTargetProcess {
            let candidate = previewFallback.finalTranscript + " "
            if case .pasted = inserter.insert(candidate) {
                insertedPreview = candidate
                state.phase = .inserting
            }
        }

        transcriptionQueue.async { [weak self] in
            do {
                let result = try transcriber.transcribe(
                    audioURL: recordedAudio.url,
                    languageProfile: behavior.languageProfile,
                    initialPrompt: behavior.context
                )
                let refinement =
                    self?.refinementCoordinator.refine(
                        result.finalTranscript,
                        mode: behavior.refinementMode,
                        languageCode:
                            behavior.languageProfile
                                .inputLanguageCode,
                        context: behavior.context,
                        voiceCommandsEnabled:
                            behavior.voiceCommandsEnabled
                    ) ?? InstantRefineEngine().refine(
                        result.finalTranscript,
                        mode: .clean
                    )
                let processed = ProcessedTranscription(
                    result: result,
                    refinement: refinement,
                    correctionApplication:
                        appliesCorrectionRules
                            ? try? correctionVault?.applyCorrections(
                                to: refinement.text
                            )
                            : nil
                )
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard !insertedPreview.isEmpty else {
                        self.complete(
                            processed: processed,
                            recordedAudio: recordedAudio,
                            historyID: historyID
                        )
                        return
                    }
                    _ = self.inserter.replaceTextBeforeCaret(
                        insertedPreview,
                        with: processed.result.finalTranscript + " "
                    )
                    // Whether or not the swap succeeded, preview text is
                    // already on screen. Inserting again would give the user
                    // their dictation twice, which is worse than either
                    // failure on its own — so the accurate transcript is
                    // recorded in history and nothing further is typed.
                    self.complete(
                        processed: processed,
                        recordedAudio: recordedAudio,
                        historyID: historyID,
                        insertionText: "",
                        hasPriorInsertion: true
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard let recovered = previewFallback.processed(
                        modelID: transcriber.modelID
                    ) else {
                        self.handleTranscriptionFailure(
                            error,
                            recordedAudio: recordedAudio,
                            historyID: historyID
                        )
                        return
                    }
                    self.complete(
                        processed: recovered,
                        recordedAudio: recordedAudio,
                        historyID: historyID,
                        insertionText: insertedPreview.isEmpty ? nil : "",
                        hasPriorInsertion: !insertedPreview.isEmpty
                    )
                }
            }
        }
    }

    /// Decodes the complete recording and runs it through refinement and
    /// personal corrections, or returns nil if it produced nothing usable.
    ///
    /// Called off the main thread.
    private nonisolated func wholeRecordingUpgrade(
        transcriber: WhisperTranscriber,
        recordedAudio: AudioRecorder.RecordedAudio,
        behavior: ActiveDictationBehavior,
        correctionVault: DictationVault?,
        appliesCorrectionRules: Bool
    ) -> ProcessedTranscription? {
        guard let result = try? transcriber.transcribe(
            audioURL: recordedAudio.url,
            languageProfile: behavior.languageProfile,
            initialPrompt: behavior.context
        ) else {
            return nil
        }
        let refinement = refinementCoordinator.refine(
            result.finalTranscript,
            mode: behavior.refinementMode,
            languageCode: behavior.languageProfile.inputLanguageCode,
            context: behavior.context,
            voiceCommandsEnabled: behavior.voiceCommandsEnabled
        )
        return ProcessedTranscription(
            result: result,
            refinement: refinement,
            correctionApplication: appliesCorrectionRules
                ? try? correctionVault?.applyCorrections(to: refinement.text)
                : nil
        )
    }

    /// Falls back to the original behaviour: transcribe whatever followed the
    /// last committed phrase and append it to the preview text already on
    /// screen. Used when the inserted text could not be verified and replaced.
    ///
    /// Called off the main thread.
    private nonisolated func completeFromSegments(
        transcriber: WhisperTranscriber,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID?,
        behavior: ActiveDictationBehavior,
        remainingSamples: [Float],
        correctionVault: DictationVault?,
        appliesCorrectionRules: Bool
    ) {
        let expectsRemainder = remainingSamples.count >= 1_600
        do {
            let processed: ProcessedTranscription?
            if expectsRemainder {
                let result = try transcriber.transcribe(
                    samples: remainingSamples,
                    languageProfile: behavior.languageProfile,
                    initialPrompt: behavior.context
                )
                let refinement = refinementCoordinator.refine(
                    result.finalTranscript,
                    mode: behavior.refinementMode,
                    languageCode: behavior.languageProfile.inputLanguageCode,
                    context: behavior.context,
                    voiceCommandsEnabled: behavior.voiceCommandsEnabled
                )
                processed = ProcessedTranscription(
                    result: result,
                    refinement: refinement,
                    correctionApplication: appliesCorrectionRules
                        ? try? correctionVault?.applyCorrections(
                            to: refinement.text
                        )
                        : nil
                )
            } else {
                processed = nil
            }
            DispatchQueue.main.async { [weak self] in
                self?.completeLiveRecording(
                    remaining: processed,
                    recordedAudio: recordedAudio,
                    historyID: historyID,
                    remainderWasExpected: expectsRemainder
                )
            }
        } catch WhisperTranscriber.TranscriptionError.noSpeech {
            DispatchQueue.main.async { [weak self] in
                self?.completeLiveRecording(
                    remaining: nil,
                    recordedAudio: recordedAudio,
                    historyID: historyID,
                    remainderWasExpected: false
                )
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.liveStableFinalTranscript.isEmpty {
                    self.resetLivePreviewSession()
                    self.handleTranscriptionFailure(
                        error,
                        recordedAudio: recordedAudio,
                        historyID: historyID
                    )
                } else {
                    self.completeLiveRecording(
                        remaining: nil,
                        recordedAudio: recordedAudio,
                        historyID: historyID,
                        remainderWasExpected: true
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
        liveSamplesEnabledForRecording = false
        resetLivePreviewSession()
        if let historyID {
            try? dictationVault?.discard(id: historyID)
        }
        state.resetAudioSamples()
        state.phase = .idle
        resetActiveDictationBehavior()
        updateStartStopMenuTitle()
    }

    @objc private func microphoneConnected(_ notification: Notification) {
        settingsViewModel?.refreshMicrophones()
    }

    @objc private func microphoneDisconnected(
        _ notification: Notification
    ) {
        settingsViewModel?.refreshMicrophones()
        guard recorder.isRecording,
              let disconnected = notification.object as? AVCaptureDevice,
              recorder.activeDeviceUID == disconnected.uniqueID else {
            return
        }

        resetWorkItem?.cancel()
        let recordedAudio = recorder.stop()
        liveSamplesEnabledForRecording = false
        resetLivePreviewSession()
        let historyID = activeHistoryID
        activeHistoryID = nil
        holdStartedRecording = false
        let message =
            "The selected microphone disconnected. Reconnect it or choose another microphone in Audio."
        if let historyID {
            try? dictationVault?.markFailed(
                id: historyID,
                message: message,
                retainAudio: historyPreferences.retainsFailedAudio
            )
        } else if let recordedAudio {
            try? FileManager.default.removeItem(at: recordedAudio.url)
        }
        state.resetAudioSamples()
        resetActiveDictationBehavior()
        updateStartStopMenuTitle()
        historyViewModel?.refresh()
        showError(message)
    }

    private func beginLivePreviewSession() {
        resetLivePreviewSession()
        guard LiveDictationPreferences.isPreviewEnabled() else {
            return
        }
        liveSessionID = UUID()
        liveTargetProcessIdentifier =
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        livePreviewTimer = Timer.scheduledTimer(
            withTimeInterval: 0.35,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.processStablePause()
            }
        }
    }

    private func processStablePause() {
        guard LiveDictationPreferences.isPreviewEnabled() else {
            stopLivePreviewScheduling(invalidatePending: true)
            return
        }
        guard recorder.isRecording,
              !livePreviewInFlight,
              let transcriber,
              let segment = recorder.stableSegment(
                after: liveCommittedSampleIndex
              ) else {
            return
        }

        livePreviewInFlight = true
        let sessionID = liveSessionID
        let behavior = activeDictationBehavior
        let correctionVault = dictationVault
        let appliesCorrectionRules =
            learningPreferences.appliesCorrectionRules
        transcriptionQueue.async { [weak self] in
            do {
                let result = try transcriber.transcribe(
                    samples: segment.samples,
                    languageProfile: behavior.languageProfile,
                    initialPrompt: behavior.context
                )
                let refinement =
                    self?.refinementCoordinator.refine(
                        result.finalTranscript,
                        mode: behavior.refinementMode,
                        languageCode:
                            behavior.languageProfile
                                .inputLanguageCode,
                        context: behavior.context,
                        voiceCommandsEnabled:
                            behavior.voiceCommandsEnabled
                    ) ?? InstantRefineEngine().refine(
                        result.finalTranscript,
                        mode: .clean
                    )
                let processed = ProcessedTranscription(
                    result: result,
                    refinement: refinement,
                    correctionApplication:
                        appliesCorrectionRules
                            ? try? correctionVault?.applyCorrections(
                                to: refinement.text
                            )
                            : nil
                )
                DispatchQueue.main.async {
                    self?.acceptStablePhrase(
                        processed,
                        endSampleIndex: segment.endSampleIndex,
                        sessionID: sessionID
                    )
                }
            } catch WhisperTranscriber.TranscriptionError.noSpeech {
                DispatchQueue.main.async {
                    guard let self,
                          self.liveSessionID == sessionID else {
                        return
                    }
                    self.livePreviewInFlight = false
                    // Keep this segment for final transcription. A short phrase
                    // can be misclassified during preview and must not be lost.
                    self.stopLivePreviewScheduling(
                        invalidatePending: false
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self,
                          self.liveSessionID == sessionID else {
                        return
                    }
                    self.livePreviewInFlight = false
                    self.stopLivePreviewScheduling(
                        invalidatePending: false
                    )
                }
            }
        }
    }

    private func acceptStablePhrase(
        _ processed: ProcessedTranscription,
        endSampleIndex: Int,
        sessionID: UUID
    ) {
        guard liveSessionID == sessionID,
              recorder.isRecording else {
            return
        }
        livePreviewInFlight = false
        liveCommittedSampleIndex = endSampleIndex
        liveStableRawTranscript = StableTranscriptComposer.appending(
            processed.result.rawTranscript,
            to: liveStableRawTranscript
        )
        liveStableFinalTranscript = StableTranscriptComposer.appending(
            processed.result.finalTranscript,
            to: liveStableFinalTranscript
        )
        liveStableCorrectionCount +=
            processed.result.correctionCount
        liveStableProcessingDuration +=
            processed.result.processingDurationSeconds
        liveCorrectionUsages.append(
            contentsOf: processed.correctionUsages
        )
        state.liveTranscriptPreview =
            processed.result.finalTranscript

        if let historyID = activeHistoryID,
           !nonPersistentHistoryIDs.contains(historyID),
           historyPreferences.isHistoryEnabled,
           !historyPreferences.isPrivateModeEnabled {
            try? dictationVault?.storePartialTranscript(
                id: historyID,
                rawTranscript: liveStableRawTranscript,
                finalTranscript: liveStableFinalTranscript,
                correctionCount: liveStableCorrectionCount
            )
        }

        guard LiveDictationPreferences.isCommitOnPauseEnabled(),
              !liveStreamingInsertionBlocked,
              AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier
                == liveTargetProcessIdentifier else {
            livePendingStableTranscript =
                StableTranscriptComposer.appending(
                    processed.result.finalTranscript,
                    to: livePendingStableTranscript
                )
            if LiveDictationPreferences.isCommitOnPauseEnabled() {
                liveStreamingInsertionBlocked = true
            }
            return
        }

        switch inserter.insert(processed.result.finalTranscript + " ") {
        case .pasted:
            liveInsertedStableTranscript =
                StableTranscriptComposer.appending(
                    processed.result.finalTranscript,
                    to: liveInsertedStableTranscript
                )
        case .copiedOnly:
            livePendingStableTranscript =
                StableTranscriptComposer.appending(
                    processed.result.finalTranscript,
                    to: livePendingStableTranscript
                )
            liveStreamingInsertionBlocked = true
        }
    }

    private func stopLivePreviewScheduling(
        invalidatePending: Bool
    ) {
        livePreviewTimer?.invalidate()
        livePreviewTimer = nil
        if invalidatePending {
            liveSessionID = UUID()
            livePreviewInFlight = false
        }
        state.liveTranscriptPreview = ""
    }

    private func completeLiveRecording(
        remaining: ProcessedTranscription?,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID?,
        remainderWasExpected: Bool
    ) {
        let remainingResult = remaining?.result
        let rawTranscript = StableTranscriptComposer.appending(
            remainingResult?.rawTranscript ?? "",
            to: liveStableRawTranscript
        )
        let finalTranscript = StableTranscriptComposer.appending(
            remainingResult?.finalTranscript ?? "",
            to: liveStableFinalTranscript
        )
        guard !finalTranscript.isEmpty, let transcriber else {
            resetLivePreviewSession()
            handleTranscriptionFailure(
                WhisperTranscriber.TranscriptionError.noSpeech,
                recordedAudio: recordedAudio,
                historyID: historyID
            )
            return
        }

        let combinedResult = TranscriptionResult(
            rawTranscript: rawTranscript,
            finalTranscript: finalTranscript,
            correctionCount:
                liveStableCorrectionCount
                + (remainingResult?.correctionCount ?? 0),
            isPartial:
                remainderWasExpected && remainingResult == nil,
            modelID: transcriber.modelID,
            processingDurationSeconds:
                liveStableProcessingDuration
                + (remainingResult?.processingDurationSeconds ?? 0)
        )
        let processed = ProcessedTranscription(
            result: combinedResult,
            correctionUsages:
                liveCorrectionUsages
                + (remaining?.correctionUsages ?? [])
        )
        let hasPriorInsertion =
            !liveInsertedStableTranscript.isEmpty
        let insertionText = hasPriorInsertion
            ? StableTranscriptComposer.appending(
                remainingResult?.finalTranscript ?? "",
                to: livePendingStableTranscript
            )
            : finalTranscript
        resetLivePreviewSession()
        complete(
            processed: processed,
            recordedAudio: recordedAudio,
            historyID: historyID,
            insertionText: insertionText,
            hasPriorInsertion: hasPriorInsertion
        )
    }

    private func resetLivePreviewSession() {
        stopLivePreviewScheduling(invalidatePending: true)
        liveCommittedSampleIndex = 0
        liveStableRawTranscript = ""
        liveStableFinalTranscript = ""
        livePendingStableTranscript = ""
        liveInsertedStableTranscript = ""
        liveStableCorrectionCount = 0
        liveStableProcessingDuration = 0
        liveCorrectionUsages = []
        liveStreamingInsertionBlocked = false
        liveTargetProcessIdentifier = nil
    }

    private func complete(
        processed: ProcessedTranscription,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID?,
        insertionText: String? = nil,
        hasPriorInsertion: Bool = false
    ) {
        let result = processed.result
        transcribingHistoryID = nil
        resetActiveDictationBehavior()
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
                try? vault.recordCorrectionUsage(
                    processed.correctionUsages
                )
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

        let textToInsert = insertionText ?? result.finalTranscript
        if textToInsert.isEmpty, hasPriorInsertion {
            if let historyID, shouldPersist, historySaveError == nil {
                try? resolvedVault().markInsertion(
                    id: historyID,
                    outcome: .inserted
                )
            }
            state.phase = .success
            historyViewModel?.refresh()
            insightsViewModel?.refresh()
            voiceProfileViewModel?.refresh()
            scheduleIdleReset(after: 1.5)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            switch self.inserter.insert(textToInsert) {
            case .pasted:
                if let historyID, shouldPersist, historySaveError == nil {
                    try? self.resolvedVault().markInsertion(
                        id: historyID,
                        outcome: .inserted
                    )
                }
                self.state.phase = .success
                self.historyViewModel?.refresh()
                self.insightsViewModel?.refresh()
                self.voiceProfileViewModel?.refresh()
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
            self.insightsViewModel?.refresh()
            self.voiceProfileViewModel?.refresh()
        }
    }

    private func handleTranscriptionFailure(
        _ error: Error,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID?
    ) {
        transcribingHistoryID = nil
        resetActiveDictationBehavior()
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

    private func resetActiveDictationBehavior() {
        activeDictationBehavior = .global
        state.languageProfile = LanguagePreferences.load()
    }

    private func showError(_ message: String) {
        state.phase = .error(message)
        updateStartStopMenuTitle()
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
        let correctionVault = dictationVault
        let appliesCorrectionRules =
            learningPreferences.appliesCorrectionRules
        let instantRefineMode = InstantRefinePreferences.load()
        transcriptionQueue.async { [weak self] in
            do {
                let result = try transcriber.transcribe(audioURL: audioURL)
                let refinement =
                    self?.refinementCoordinator.refine(
                        result.finalTranscript,
                        mode: instantRefineMode
                    ) ?? InstantRefineEngine().refine(
                        result.finalTranscript,
                        mode: .clean
                    )
                let processed = ProcessedTranscription(
                    result: result,
                    refinement: refinement,
                    correctionApplication:
                        appliesCorrectionRules
                            ? try? correctionVault?.applyCorrections(
                                to: refinement.text
                            )
                            : nil
                )
                DispatchQueue.main.async {
                    self?.completeHistoryRetry(
                        processed: processed,
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
        processed: ProcessedTranscription,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID
    ) {
        let result = processed.result
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
            try? vault.recordCorrectionUsage(processed.correctionUsages)
            state.lastTranscript = result.finalTranscript
            state.phase = .success
            historyViewModel.refresh()
            insightsViewModel.refresh()
            voiceProfileViewModel.refresh()
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
        let enabled = !state.showsZenVoiceAtAllTimes
        if let settingsViewModel {
            settingsViewModel.setShowsZenVoiceAtAllTimes(enabled)
        } else {
            state.setShowsZenVoiceAtAllTimes(enabled)
        }
    }

    private func updateZenBarPresentation(
        phase: AppState.Phase,
        showsAtAllTimes: Bool
    ) {
        let showsForActiveDictation: Bool
        switch phase {
        case .listening, .transcribing, .inserting, .error:
            showsForActiveDictation = true
        case .idle, .success:
            showsForActiveDictation = false
        }

        if showsAtAllTimes || showsForActiveDictation {
            zenBarController.show()
        } else {
            zenBarController.hide()
        }
        zenBarMenuItem?.state = showsAtAllTimes ? .on : .off
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
