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
import AVFoundation
import Combine
import Foundation
import os
import ZenVoiceCore
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
            processingDurationSeconds: result.processingDurationSeconds,
            runawayWordsCut: result.runawayWordsCut
        )
        correctionUsages = correctionApplication?.usages ?? []
    }

    /// Swaps in text produced downstream — currently a cloud enhancement —
    /// while keeping the raw transcript, model, and timings that describe how
    /// the local decode actually went.
    func replacingFinalTranscript(with text: String) -> ProcessedTranscription {
        ProcessedTranscription(
            result: TranscriptionResult(
                rawTranscript: result.rawTranscript,
                finalTranscript: text,
                correctionCount: result.correctionCount,
                isPartial: result.isPartial,
                modelID: result.modelID,
                processingDurationSeconds: result.processingDurationSeconds,
                runawayWordsCut: result.runawayWordsCut
            ),
            correctionUsages: correctionUsages
        )
    }
}

private struct ActiveDictationBehavior: Sendable {
    let languageProfile: LanguageProfile
    let correctionScope: CorrectionLanguageScope
    let formattingMode: TranscriptFormattingMode
    let voiceCommandsEnabled: Bool
    let context: String
    let snippets: [VoiceSnippet]
    let modelID: String

    static var global: ActiveDictationBehavior {
        let languageProfile = LanguagePreferences.load()
        return ActiveDictationBehavior(
            languageProfile: languageProfile,
            correctionScope: languageProfile.correctionScope,
            formattingMode: TranscriptFormattingPreferences.load(),
            voiceCommandsEnabled: false,
            context: "",
            snippets: [],
            modelID: "unknown"
        )
    }
}

private extension LanguageProfile {
    var correctionScope: CorrectionLanguageScope {
        self == .hinglish ? .hinglish : .all
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let state = AppState()
    private static let dictationPerformanceLog = OSLog(
        subsystem: RuntimeIdentity.productionBundleID,
        category: "DictationPerformance"
    )
    private let recorder = AudioRecorder()
    private let inserter = TextInserter()

    private var statusItem: NSStatusItem!
    private var startStopMenuItem: NSMenuItem!
    private var zenBarMenuItem: NSMenuItem!
    private var statusMessageMenuItem: NSMenuItem!
    private var todayUsageMenuItem: NSMenuItem!
    private var languageMenuItem: NSMenuItem!
    private var accessibilityMenuItem: NSMenuItem!
    private var zenBarController: OverlayPanelController!
    private var escapeMonitors: [Any] = []
    private var globalHotKey: GlobalHotKey?
    private var pasteLastGlobalHotKey: GlobalHotKey?
    private var holdToDictateController: HoldToDictateController?
    private var engineRegistry: EngineRegistry?
    private var whisperEngine: WhisperSpeechEngine?
    private var engineConfigurationTask: Task<Void, Never>?
    private var resetWorkItem: DispatchWorkItem?
    // Orders partial-transcript stores against finalization: a fire-and-
    // forget partial store scheduled before `storeTranscript` must not land
    // after it and flip the finalized record back to is_partial.
    private var partialStoreSequence = 0
    private var finalizedPartialStoreSequence = 0
    private var stateObservers: Set<AnyCancellable> = []
    private var currentHotKeyConfiguration = HotKeyPreferences.load()
    private var pasteLastHotKeyConfiguration =
        HotKeyPreferences.loadPasteLast()
    private var settingsViewModel: SettingsViewModel!
    private var historyViewModel: HistoryViewModel!
    private var audioHistoryViewModel: AudioHistoryViewModel!

    private var updatesViewModel: UpdatesViewModel!
    private var insightsViewModel: InsightsViewModel!
    private var voiceProfileViewModel: VoiceProfileViewModel!
    private let snippetsViewModel = SnippetsViewModel()
    private var modelManagerViewModel: ModelManagerViewModel!
    private let onboardingViewModel = OnboardingViewModel(
        showAtLaunch: OnboardingPreferences.shouldPresent()
    )
    private var settingsWindowController: SettingsWindowController!
    private let historyPreferences = HistoryPreferences()
    private let audioHistoryPreferences = AudioHistoryPreferences()
    private let learningPreferences = LocalLearningPreferences()
    private var dictationVault: DictationVault?
    private var vaultResolutionTask: Task<DictationVault, Error>?
    private var agenticModeCoordinator: AgenticModeCoordinator?
    private var activeHistoryID: UUID?
    private var transcribingHistoryID: UUID?
    private var nonPersistentHistoryIDs: Set<UUID> = []
    private var holdKeyPressed = false
    private var holdStartedRecording = false
    private var recoveryExpiryTimer: Timer?
    private var livePreviewTimer: Timer?
    private var liveSessionID = UUID()
    private var liveCommittedSampleIndex = 0
    private var liveTailPreviewedIndex = 0
    private var livePreviewInFlight = false
    private var livePreviewTask: Task<Void, Never>?
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
    /// Name of the device the active session records from, captured at
    /// recorder start — `recorder.activeDeviceUID` is nilled on stop, before
    /// the completion flow runs.
    private var recordingDeviceName: String?
    // Set when Esc lands during startRecorder's async gap, before the
    // recorder has actually opened the mic and cancelRecording's
    // isRecording guard can act on it.
    private var cancelRequested = false
    // Set synchronously before the retry's first await so a double-click on
    // Retry cannot start two decodes of the same record.
    private var retryInFlight = false
    private var dictationTargetProcessIdentifier: pid_t?
    private var activeDictationBehavior =
        ActiveDictationBehavior.global
    private var anticipatoryEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The approved graphite/violet reference is ZenVoice's one appearance
        // for now. Set it at the application boundary so settings, approval
        // windows, cloud review panels, menus, and native controls agree.
        NSApp.appearance = ZenAppearance.appKitAppearance
        NSApp.setActivationPolicy(.accessory)
        validateRuntimeIdentity()
        configureEngines()
        configureMainMenu()
        configureMenuBar()
        configureZenBar()
        Task { await configureHistoryStorage() }
        configureHotKey()
        configureHoldToDictate()
        // The global Esc-cancel monitor only observes keystrokes with
        // Accessibility trust; without it it silently never fires. Say so
        // once instead of leaving the user to discover the gap.
        if !AXIsProcessTrusted() {
            Logger(subsystem: RuntimeIdentity.productionBundleID, category: "EscCancel")
                .error("Accessibility permission not granted — Esc cannot cancel dictations started outside ZenVoice's own windows.")
        }
        configureAnticipatoryWarmup()
        configureSettingsWindow()
        SparkleUpdater.shared.start()
        // The main window is the app. Opening it on launch is what the
        // approved design specifies: ZenVoice keeps its menu-bar presence and
        // its global hotkey, but starting it shows you the app rather than
        // leaving you to hunt for a status item. Closing the window drops the
        // activation policy back to `.accessory`, so it still gets out of the
        // way once you are dictating.
        settingsWindowController.show()
#if DEBUG
        runDeterministicE2EIfRequested()
#endif

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

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        Task { @MainActor [weak self, weak sender] in
            await self?.prepareForTermination()
            sender?.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func prepareForTermination() async {
        livePreviewTimer?.invalidate()
        let historyID = activeHistoryID
        let processingHistoryID = transcribingHistoryID
        activeHistoryID = nil
        transcribingHistoryID = nil
        let recordedAudio = recorder.stop()
        if let historyID {
            if nonPersistentHistoryIDs.contains(historyID)
                || !historyPreferences.isHistoryEnabled {
                await bestEffortHistoryWrite { try await dictationVault?.discard(id: historyID) }
            } else {
                await bestEffortHistoryWrite {
                    try await dictationVault?.markFailed(
                        id: historyID,
                        message:
                            "ZenVoice closed before this dictation completed.",
                        retainAudio: historyPreferences.retainsFailedAudio
                    )
                }
            }
        } else if let recordedAudio {
            try? FileManager.default.removeItem(at: recordedAudio.url)
        }
        if let processingHistoryID,
           nonPersistentHistoryIDs.contains(processingHistoryID)
            || !historyPreferences.isHistoryEnabled {
            await bestEffortHistoryWrite {
                try await dictationVault?.discard(id: processingHistoryID)
            }
        }
        if let monitor = anticipatoryEventMonitor {
            NSEvent.removeMonitor(monitor)
            anticipatoryEventMonitor = nil
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

    private func configureEngines() {
        guard engineConfigurationTask == nil else {
            return
        }
        engineConfigurationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.configureEnginesNow()
            self.engineConfigurationTask = nil
        }
    }

    private func waitForEngineConfiguration() async {
        configureEngines()
        await engineConfigurationTask?.value
    }

    private func configureEnginesNow() async {
        let profile = LanguagePreferences.load()
        SelectedEnginePreferences.migrateLegacyWhisperSelectionIfNeeded(
            for: profile
        )
        do {
            let configuration = try await Task.detached(
                priority: .userInitiated
            ) {
                try ZenVoiceConfiguration.discover()
            }.value
            let whisper = WhisperSpeechEngine(configuration: configuration)
            whisperEngine = whisper
            engineRegistry = makeEngineRegistry(whisper: whisper)
            warmUpEngines()
        } catch ZenVoiceConfiguration.ConfigurationError.modelMissing {
            // TDT v3 can still run when no Whisper file is installed yet.
            whisperEngine = nil
            engineRegistry = makeEngineRegistry(whisper: nil)
        } catch {
            // Same recovery as every other error surface: show the banner,
            // then reset to idle so the phase pill does not stick on error.
            showError(error.localizedDescription)
        }
        modelManagerViewModel?.refreshEngineSelection()
        settingsViewModel?.refreshSystemStatus()
    }

    private func makeEngineRegistry(whisper: WhisperSpeechEngine?) -> EngineRegistry {
        var engines: [any SpeechEngine] = [AppleSpeechEngine()]
        if let whisper {
            engines.append(whisper)
        }
        if let parakeetTDTv3 = makeParakeetTDTEngine(.v3) {
            engines.append(parakeetTDTv3)
        }
        if let parakeetTDTv2 = makeParakeetTDTEngine(.v2) {
            engines.append(parakeetTDTv2)
        }
        if let nemotron = makeParakeetTDTEngine(.nemotron) {
            engines.append(nemotron)
        }
        if let cohere = makeCohereTranscribeEngine() {
            engines.append(cohere)
        }
        if let qwen3 = makeQwen3ASREngine() {
            engines.append(qwen3)
        }
        let temporary = EngineRegistry(engines: engines)
        let fallbackOrder = EngineRecommendationEngine.fallbackOrder(
            for: LanguagePreferences.load(),
            hardware: HardwareProfile.current(),
            registry: temporary
        )
        return EngineRegistry(
            engines: engines,
            fallbackOrder: fallbackOrder
        )
    }

    private func makeParakeetTDTEngine(
        _ configuration: ParakeetTDTEngine.Configuration
    ) -> ParakeetTDTEngine? {
        makeEngineIfModelExists(
            filename: configuration.modelFilename
        ) { url in
            ParakeetTDTEngine(configuration: configuration, modelURL: url)
        }
    }

    private func makeCohereTranscribeEngine() -> CohereTranscribeEngine? {
        guard let modelsDirectory = try? VerifiedModelCatalog.modelsDirectory()
        else {
            return nil
        }
        let engine = CohereTranscribeEngine(modelsDirectory: modelsDirectory)
        return engine.isAvailable ? engine : nil
    }

    private func makeQwen3ASREngine() -> Qwen3ASREngine? {
        guard let modelsDirectory = try? VerifiedModelCatalog.modelsDirectory()
        else {
            return nil
        }
        let engine = Qwen3ASREngine(modelsDirectory: modelsDirectory)
        return engine.isAvailable ? engine : nil
    }



    private func makeEngineIfModelExists<Engine: SpeechEngine>(
        filename: String,
        factory: (URL) -> Engine
    ) -> Engine? {
        let modelsDirectory = try? VerifiedModelCatalog.modelsDirectory()
        guard let modelsDirectory else {
            return nil
        }
        let modelURL = modelsDirectory
            .appendingPathComponent(filename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            return nil
        }
        return factory(modelURL)
    }

    /// Prepares the engines a dictation can reach before the user stops
    /// speaking. Every preparation goes through the engine API, which owns the
    /// same serial queue as decode and release; directly touching a transcriber
    /// from a second queue can run two `whisper_full` calls concurrently.
    private func warmUpEngines() {
        guard let registry = engineRegistry else {
            return
        }
        let profile = LanguagePreferences.load()
        let selectedID = SelectedEnginePreferences.load(for: profile)
        Task {
            let resolved = registry.resolve(
                for: profile,
                selectedID: selectedID
            )
            if LiveDictationPreferences.isPreviewEnabled(),
               let preview = registry.resolvePreview(for: profile)
            {
                let previewIsWhisper = EngineIdentifiers.isWhisperFamily(
                    preview.descriptor.id
                )
                let resolvedID = resolved?.descriptor.id
                let resolvedIsParakeet =
                    resolvedID == EngineIdentifiers.parakeetTDTv3
                if !(previewIsWhisper && resolvedIsParakeet) {
                    try? await preview.prepare()
                }
            }
            try? await registry.prepare(
                for: profile,
                selectedID: selectedID
            )
        }
        noteDictationActivity()
    }

    // MARK: - Idle model unloading

    /// How long a loaded model stays resident after the last dictation.
    ///
    /// A resident speech model is measured at 600 MB (Whisper Turbo) to
    /// 940 MB (Nemotron), nearly all of it GPU buffers, and warming one at
    /// launch means a menu-bar app nobody has dictated into still holds that
    /// all day. Five minutes keeps a working session warm — dictations cluster
    /// far closer together than that — and gives the memory back to anyone who
    /// walked away.
    private static let modelIdleTimeout: TimeInterval = 5 * 60

    /// Retry interval when the timeout expires mid-dictation.
    private static let modelIdleRetryInterval: TimeInterval = 30

    /// Peak level below which a dictation counted as a near-silent input —
    /// the same bar the Audio Doctor uses for its "very quiet" verdict.
    private static let quietInputPeakThreshold = 0.08

    private var modelIdleTimer: Timer?

    /// Restarts the idle countdown. Called wherever a model is warmed, which
    /// is every route into a dictation.
    private func noteDictationActivity() {
        scheduleModelIdleUnload(after: Self.modelIdleTimeout)
    }

    private func scheduleModelIdleUnload(after interval: TimeInterval) {
        modelIdleTimer?.invalidate()
        // One-shot and rescheduled rather than repeating: an idle menu-bar app
        // should not be waking every minute to ask whether it is still idle.
        let timer = Timer(
            timeInterval: interval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.releaseIdleModels()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        modelIdleTimer = timer
    }

    private func releaseIdleModels() {
        modelIdleTimer = nil
        // A dictation can outlive the timeout. Never free a model out from
        // under a decode that is still running — come back and check later.
        guard !state.isBusy, !recorder.isRecording else {
            scheduleModelIdleUnload(after: Self.modelIdleRetryInterval)
            return
        }
        guard let registry = engineRegistry else {
            return
        }
        Task {
            await registry.releaseAll()
        }
    }


    private func configureHistoryStorage() async {
        do {
            if historyPreferences.isHistoryEnabled {
                // Materialize the default so paused history can still display
                // records and paste-last can recover them after relaunch.
                historyPreferences.isHistoryEnabled = true
            }
            let policy = try RuntimeIdentity.policy()
            let vault = try await DictationVault.live(policy: policy)
            dictationVault = vault
            // 0.3.1: Command Mode / Agentic Mode is not ready for beta.
            // Keep the types compiled but never activate them on launch.
            CommandModePreferences.setEnabled(false)
            AgenticModePreferences.setEnabled(false)
            let coordinator = AgenticModeCoordinator(state: state, vault: vault)
            agenticModeCoordinator = coordinator
            try await vault.recoverInterrupted(
                retainAudio: historyPreferences.retainsFailedAudio
            )
            try await vault.purgeExpiredRecoveryAudio()
            // History retention is a published promise ("keep N days"), so it
            // is enforced rather than merely stored: anything older than the
            // preference says is discarded on launch, recovery audio and all.
            let retentionCutoff = Date().addingTimeInterval(
                -TimeInterval(historyPreferences.retentionDays * 24 * 60 * 60)
            )
            try await vault.purgeRecords(startedBefore: retentionCutoff)
            scheduleRecoveryExpiry()
            await enforceAudioHistoryBudgets()
            Task(priority: .background) { [weak self] in
                try? await self?.dictationVault?.vacuumIfNeeded()
            }
        } catch {
            showError(error.localizedDescription)
        }
    }


    /// Copies a completed recording into the Audio History archive.
    ///
    /// Archiving piggybacks on transcript persistence: the archive row is
    /// derived from the dictation row, so a dictation that is not persisted —
    /// paused history, a one-off suppression — is never
    /// archived. Must run before the recovery audio is deleted, because that
    /// file is the archive's source.
    private func archiveRecordingIfEnabled(historyID: UUID) async {
        guard audioHistoryPreferences.isEnabled,
              let vault = dictationVault else {
            return
        }
        // A failure to archive must not fail the dictation itself; the
        // transcript is already stored by this point.
        try? await vault.archiveRecording(id: historyID)
        await enforceAudioHistoryBudgets()
    }

    /// Applies the age and size budgets to the audio archive.
    ///
    /// Runs at launch and after each archived recording, so the archive cannot
    /// grow past what the user allowed even if the app is never quit.
    private func enforceAudioHistoryBudgets() async {
        guard let vault = dictationVault else {
            return
        }
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -audioHistoryPreferences.maxAgeDays,
            to: Date()
        ) ?? Date.distantPast
        _ = try? await vault.purgeAudioArchive(olderThan: cutoff)
        _ = try? await vault.enforceAudioArchiveSizeBudget(
            audioHistoryPreferences.maxSizeBytes
        )
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
        menu.delegate = self

        // Today's usage, refreshed each time the menu opens.
        todayUsageMenuItem = NSMenuItem(
            title: TodayUsageInsight.empty.pillSummary,
            action: nil,
            keyEquivalent: ""
        )
        todayUsageMenuItem.isEnabled = false
        menu.addItem(todayUsageMenuItem)

        menu.addItem(.separator())

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

        // Titled from the live permission state in `menuWillOpen`. A fixed
        // "Enable…" title claimed the permission was missing even when it had
        // been granted, and said nothing when it was revoked mid-session.
        accessibilityMenuItem = NSMenuItem(
            title: "Enable Auto-Paste Permission…",
            action: #selector(requestAccessibilityPermission),
            keyEquivalent: ""
        )
        accessibilityMenuItem.target = self
        menu.addItem(accessibilityMenuItem)

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

    /// Installs the application menu bar.
    ///
    /// ZenVoice had none. It ran as an accessory with only a status-item menu,
    /// which is fine while it is invisible — but the window flips the app to
    /// `.regular`, and AppKit routes the standard key equivalents through
    /// `NSApp.mainMenu`. With no main menu there was nothing to route to, so
    /// ⌘Q, ⌘W, ⌘M and — worse — ⌘C/⌘V/⌘A inside the app's own text fields all
    /// did nothing.
    ///
    /// The Edit menu is not decoration: every text field in the window, the
    /// Cloud AI key field included, depends on those responder actions
    /// existing somewhere in the menu bar.
    private func configureMainMenu() {
        let mainMenu = NSMenu()

        // AppKit treats the first item's submenu as the application menu and
        // supplies the app's name itself.
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About ZenVoice",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide ZenVoice",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit ZenVoice",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        let redoItem = NSMenuItem(
            title: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        // Closing the window is not quitting. ZenVoice keeps its status item
        // and its global shortcut, and `windowWillClose` drops the app back to
        // `.accessory` — so ⌘W puts it away and ⌘Q ends it, which is the
        // distinction a menu-bar app needs and could not previously express.
        windowMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        // Lets AppKit add "Enter Full Screen" and the window list itself.
        NSApp.windowsMenu = windowMenu
    }

    @objc private func showSettingsWindow() {
        settingsWindowController.show()
    }

    private func configureZenBar() {
        makeOverlayController()
        state.$phase
            .combineLatest(state.$showsZenVoiceAtAllTimes)
            .sink { [weak self] phase, showsAtAllTimes in
                self?.updateZenBarPresentation(
                    phase: phase,
                    showsAtAllTimes: showsAtAllTimes
                )
                self?.updateEscapeToCancel(phase: phase)
            }
            .store(in: &stateObservers)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(overlayPreferencesChanged),
            name: OverlayPreferences.didChangeNotification,
            object: nil
        )
    }

    /// Builds the overlay panel for the currently selected overlay kind.
    ///
    /// Separate from ``configureZenBar()`` because the panel is rebuilt whenever
    /// the selection changes, while the state subscription is set up only once.
    private func makeOverlayController() {
        zenBarController = OverlayPanelController(
            kind: resolvedOverlayKind(),
            state: state,
            toggleRecording: { [weak self] in
                self?.toggleRecording()
            },
            cancelRecording: { [weak self] in
                self?.cancelRecording()
            },
            finishRecording: { [weak self] in
                self?.finishRecording()
            },
            dismissError: { [weak self] in
                self?.dismissZenBarError()
            },
            cancelAgenticGoal: { [weak self] in
                self?.agenticModeCoordinator?.cancelActiveGoal()
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

    private func configureAnticipatoryWarmup() {
        // Global monitor for modifier flag changes. When the user taps Control or Option
        // (the modifier keys for the default dictation hotkey ^⌥Space), pre-warm the engine
        // asynchronously if it's currently unloaded.
        anticipatoryEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            let flags = event.modifierFlags
            if flags.contains(.control) || flags.contains(.option) {
                self?.warmUpEngines()
            }
        }
    }

    private func configureSettingsWindow() {
        modelManagerViewModel = ModelManagerViewModel(
            applySelection: { [weak self] model, profile in
                guard let self else {
                    return .failure(
                        ZenVoiceConfiguration.ConfigurationError.modelMissing
                    )
                }
                return self.applyConfiguration(
                    model: model,
                    languageProfile: profile
                )
            },
            selectionInvalidated: { [weak self] in
                self?.configureEngines()
            },
            engineRegistryProvider: { [weak self] in
                self?.engineRegistry
            }
        )
        settingsViewModel = SettingsViewModel(
            currentShortcut: currentHotKeyConfiguration,
            pasteLastShortcut: pasteLastHotKeyConfiguration,
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
            },
            isSpeechEngineReady: { [weak self] in
                let profile = LanguagePreferences.load()
                let selectedID = SelectedEnginePreferences.load(for: profile)
                return self?.engineRegistry?.resolve(
                    for: profile,
                    selectedID: selectedID
                ) != nil
            },
            isDictationActive: { [weak self] in
                self?.state.phase == .listening
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
                return try await self.resolvedVault()
            },
            retryRecord: { [weak self] record in
                guard let self else {
                    return .failure(
                        DictationVaultError.database(
                            "ZenVoice is no longer running."
                        )
                    )
                }
                return await self.retryHistoryRecord(record)
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
                return try await self.resolvedVault()
            }
        )
        voiceProfileViewModel = VoiceProfileViewModel(
            vaultProvider: { [weak self] in
                guard let self else {
                    throw DictationVaultError.database(
                        "ZenVoice is no longer running."
                    )
                }
                return try await self.resolvedVault()
            }
        )
        audioHistoryViewModel = AudioHistoryViewModel(
            preferences: audioHistoryPreferences,
            vaultProvider: { [weak self] in
                guard let self else {
                    throw DictationVaultError.database(
                        "ZenVoice is no longer running."
                    )
                }
                return try await self.resolvedVault()
            }
        )
        updatesViewModel = UpdatesViewModel()
        settingsWindowController = SettingsWindowController(
            viewModel: settingsViewModel,
            historyViewModel: historyViewModel,
            audioHistoryViewModel: audioHistoryViewModel,
            updatesViewModel: updatesViewModel,
            insightsViewModel: insightsViewModel,
            voiceProfileViewModel: voiceProfileViewModel,
            snippetsViewModel: snippetsViewModel,
            modelManagerViewModel: modelManagerViewModel,
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

    private func applyHotKey(
        _ configuration: HotKeyConfiguration
    ) -> Result<Void, Error> {
        guard configuration.isValid,
              configuration != pasteLastHotKeyConfiguration else {
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
              configuration != currentHotKeyConfiguration else {
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
        let result = modelManagerViewModel.selectProfile(profile)
        modelManagerViewModel.refreshEngineSelection()
        return result
    }

    private func applyConfiguration(
        model: VerifiedModel,
        languageProfile: LanguageProfile
    ) -> Result<Void, Error> {
        do {
            // Verification and candidate construction happen before either
            // preference changes, so a failure cannot leave a mismatched
            // model/profile pair behind.
            let whisperEngine = try ModelProfileTransition.prepareAndCommit(
                model: model,
                profile: languageProfile
            ) {
                let configuration = try ZenVoiceConfiguration.verified(
                    model: model,
                    languageProfile: languageProfile
                )
                return WhisperSpeechEngine(configuration: configuration)
            }
            self.whisperEngine = whisperEngine
            engineRegistry = makeEngineRegistry(whisper: whisperEngine)
            warmUpEngines()
            state.languageProfile = languageProfile
            settingsViewModel?.configurationDidChange(
                languageProfile: languageProfile
            )
            updateLanguageMenu()
            modelManagerViewModel.refreshEngineSelection()
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
        guard HoldKeyChoice.shouldOpenMicrophone(
            startedByHold: startedByHold,
            holdKeyPressed: holdKeyPressed
        ) else {
            return
        }
        if engineRegistry == nil {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.waitForEngineConfiguration()
                guard self.engineRegistry != nil else { return }
                self.beginRecording(startedByHold: startedByHold)
            }
            return
        }
        // Earliest useful moment: the model finishes building while the user is
        // still talking, rather than after they stop. A no-op once warm.
        warmUpEngines()

#if DEBUG
        if recorder.usesDeterministicFixture {
            Task { await startRecorder(startedByHold: startedByHold) }
            return
        }
#endif

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            Task { await startRecorder(startedByHold: startedByHold) }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted,
                       !startedByHold || self.holdKeyPressed {
                        Task {
                            await self.startRecorder(
                                startedByHold: startedByHold
                            )
                        }
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

    private func startRecorder(startedByHold: Bool = false) async {
        // A failed start must not leave the previous session's device name
        // behind for the quiet-input diagnosis to report.
        recordingDeviceName = nil
        cancelRequested = false
        guard !recorder.isRecording, !state.isBusy else {
            return
        }
        state.isStartingRecording = true
        defer { state.isStartingRecording = false }
        guard HoldKeyChoice.shouldOpenMicrophone(
            startedByHold: startedByHold,
            holdKeyPressed: holdKeyPressed
        ) else {
            return
        }
        resetWorkItem?.cancel()
        state.resetAudioSamples()
        var historyDraft: DictationDraft?
        let capturesLiveSamples =
            !isDeterministicE2E
            && LiveDictationPreferences.isPreviewEnabled()
        let targetApplication =
            NSWorkspace.shared.frontmostApplication
        guard let dictationBehavior = await resolvedDictationBehavior(
            targetBundleIdentifier:
                targetApplication?.bundleIdentifier
        ) else {
            return
        }
        activeDictationBehavior = dictationBehavior
        state.languageProfile = dictationBehavior.languageProfile

        if !isDeterministicE2E,
           historyPreferences.isHistoryEnabled {
            do {
                let vault = try await resolvedVault()
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
                    modelID: dictationBehavior.modelID,
                    targetBundleID: targetApplication?.bundleIdentifier,
                    targetAppName: targetApplication?.localizedName,
                    category: category,
                    recoveryAudioURL: await vault.recoveryAudioURL(for: id)
                )
                try await vault.begin(draft)
                historyDraft = draft
                activeHistoryID = id
            } catch {
                showError(error.localizedDescription)
                return
            }
        }
        dictationTargetProcessIdentifier = targetApplication?.processIdentifier
        guard !cancelRequested,
              HoldKeyChoice.shouldOpenMicrophone(
                  startedByHold: startedByHold,
                  holdKeyPressed: holdKeyPressed
              ) else {
            // Either Esc landed during the async gap above, or the hold key
            // was released before the mic opened — bail either way.
            if let historyID = historyDraft?.id {
                await bestEffortHistoryWrite { try await dictationVault?.discard(id: historyID) }
                activeHistoryID = nil
            }
            dictationTargetProcessIdentifier = nil
            return
        }
        do {
            try recorder.start(
                recordingURL: historyDraft?.recoveryAudioURL,
                capturesLiveSamples: capturesLiveSamples
            ) { [weak self] level, bands in
                DispatchQueue.main.async {
                    self?.state.appendAudioLevel(level)
                    self?.state.appendAudioSpectrum(bands)
                }
            }
            // The recovery WAV is plaintext until the vault seals it, so it
            // must never be world-readable while it exists. AVAudioFile
            // created it just above with default permissions.
            if let recoveryURL = historyDraft?.recoveryAudioURL,
               FileManager.default.fileExists(atPath: recoveryURL.path) {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: recoveryURL.path
                )
            }
            liveSamplesEnabledForRecording = capturesLiveSamples
            recordingDeviceName = MicrophoneCatalog.devices().first(
                where: { $0.id == recorder.activeDeviceUID }
            )?.name
            settingsViewModel.clearNextDictationContext()
            settingsViewModel.clearQuietDevice()
            state.phase = .listening
            beginLivePreviewSession()
            holdStartedRecording = startedByHold
            updateStartStopMenuTitle()
        } catch {
            liveSamplesEnabledForRecording = false
            dictationTargetProcessIdentifier = nil
            if let historyID = historyDraft?.id {
                await bestEffortHistoryWrite { try await dictationVault?.discard(id: historyID) }
                activeHistoryID = nil
            }
            showError(error.localizedDescription)
        }
    }

    private func resolvedDictationBehavior(
        targetBundleIdentifier _: String?
    ) async -> ActiveDictationBehavior? {
        let languageProfile = LanguagePreferences.load()
        let selectedID = SelectedEnginePreferences.load(for: languageProfile)
        guard let resolvedEngine = engineRegistry?.resolve(
            for: languageProfile,
            selectedID: selectedID
        ) else {
            showError(
                EngineError.noEngineAvailable.localizedDescription
            )
            return nil
        }
        guard languageProfile.isCompatible(
            with: resolvedEngine.languageCapability
        ) else {
            showError(
                EngineError.engineUnavailable(
                    resolvedEngine.descriptor.id
                ).localizedDescription
            )
            return nil
        }
        let correctionScope = languageProfile.correctionScope
        let preferredVocabulary: [String]
        if learningPreferences.appliesCorrectionRules,
           let vault = try? await resolvedVault() {
            preferredVocabulary =
                (try? await vault.preferredVocabulary(
                    activeScope: correctionScope
                )) ?? []
        } else {
            preferredVocabulary = []
        }
        return ActiveDictationBehavior(
            languageProfile: languageProfile,
            correctionScope: correctionScope,
            formattingMode:
                isDeterministicE2E
                    ? .clean
                    : TranscriptFormattingPreferences.load(),
            voiceCommandsEnabled:
                LocalVoiceCommandPreferences.isEnabled(),
            context:
                NextDictationContext.combined(
                    context:
                        settingsViewModel.sanitizedNextDictationContext,
                    preferredVocabulary: preferredVocabulary
                ),
            snippets: SnippetPreferences.load(),
            modelID:
                (resolvedEngine as? WhisperSpeechEngine)?.modelID
                ?? resolvedEngine.descriptor.id
        )
    }

    private func finishRecording() {
        // Double-tap guard: set synchronously before the Task hops, so a
        // second stop event cannot enqueue a duplicate finish. Cleared by
        // finishRecordingNow's defer on every exit path.
        guard !state.isStoppingRecording else {
            return
        }
        state.isStoppingRecording = true
        Task { await finishRecordingNow() }
    }

    private func finishRecordingNow() async {
        defer { state.isStoppingRecording = false }
        holdStartedRecording = false
        let usesLivePreview = liveSamplesEnabledForRecording
        liveSamplesEnabledForRecording = false
        stopLivePreviewScheduling(invalidatePending: true)
        let recordedAudio = recorder.stop(
            preserveLiveSamples: usesLivePreview
        )
        os_signpost(
            .event,
            log: Self.dictationPerformanceLog,
            name: "RecordingStopped"
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
        guard let recordedAudio else {
            resetLivePreviewSession()
            showError("No recording was captured.")
            return
        }
        let historyID = activeHistoryID
        activeHistoryID = nil
        transcribingHistoryID = historyID
        let behavior = activeDictationBehavior
        state.phase = .transcribing
        updateStartStopMenuTitle()

        if let historyID {
            let mark: () async throws -> Void = { [self] in
                try await resolvedVault().markTranscribing(
                    id: historyID,
                    durationSeconds: recordedAudio.durationSeconds
                )
            }
            do {
                try await mark()
            } catch {
                handleTranscriptionFailure(
                    error,
                    recordedAudio: recordedAudio,
                    historyID: historyID
                )
                return
            }
        }

        let correctionVault = dictationVault
        let appliesCorrectionRules =
            learningPreferences.appliesCorrectionRules

        if completesFromSegments {
            // Preview text is already on screen, but it was decoded from
            // fragments and the whole recording decodes more accurately. Try to
            // verify and swap what was inserted for the better transcript; only
            // if that cannot be done safely does the fragment path stand.
            let insertedText = liveInsertedStableTranscript
            let registry = engineRegistry
            let whisper = whisperEngine
            Task { [weak self] in
                guard let registry else {
                    await self?.completeFromSegments(
                        whisperEngine: whisper,
                        recordedAudio: recordedAudio,
                        historyID: historyID,
                        behavior: behavior,
                        remainingSamples: remainingSamples,
                        correctionVault: correctionVault,
                        appliesCorrectionRules: appliesCorrectionRules
                    )
                    return
                }
                guard let upgrade = await self?.wholeRecordingUpgrade(
                    registry: registry,
                    recordedAudio: recordedAudio,
                    behavior: behavior,
                    correctionVault: correctionVault,
                    appliesCorrectionRules: appliesCorrectionRules
                ) else {
                    await self?.completeFromSegments(
                        whisperEngine: whisper,
                        recordedAudio: recordedAudio,
                        historyID: historyID,
                        behavior: behavior,
                        remainingSamples: remainingSamples,
                        correctionVault: correctionVault,
                        appliesCorrectionRules: appliesCorrectionRules
                    )
                    return
                }
                await MainActor.run {
                    guard let self else { return }
                    // A non-throwing empty result must not swap
                    // already-inserted preview text for a bare space: keep
                    // the preview in place and finish as inserted.
                    if upgrade.result.finalTranscript.isEmpty {
                        self.resetLivePreviewSession()
                        self.state.liveTranscriptPreview = ""
                        self.complete(
                            processed: upgrade,
                            recordedAudio: recordedAudio,
                            historyID: historyID,
                            insertionText: "",
                            hasPriorInsertion: true,
                            formattingMode: behavior.formattingMode
                        )
                        return
                    }
                    let replaced = self.inserter.replaceTextBeforeCaret(
                        insertedText + " ",
                        with: upgrade.result.finalTranscript + " "
                    )
                    guard replaced == .replaced else {
                        Task {
                            await self.completeFromSegments(
                                whisperEngine: whisper,
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
                        hasPriorInsertion: true,
                        formattingMode: behavior.formattingMode
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
        let insertionTargetProcess =
            liveTargetProcessIdentifier ?? dictationTargetProcessIdentifier
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
            == insertionTargetProcess {
            let candidate = previewFallback.finalTranscript + " "
            if case .pasted = inserter.insert(candidate) {
                insertedPreview = candidate
                state.phase = .inserting
            }
        }

        let registry = engineRegistry
        let fallbackModelID = whisperEngine?.modelID ?? "unknown"
        Task { [weak self] in
            guard let registry else {
                await MainActor.run {
                    self?.handleTranscriptionFailure(
                        EngineError.noEngineAvailable,
                        recordedAudio: recordedAudio,
                        historyID: historyID
                    )
                }
                return
            }
            do {
                os_signpost(
                    .event,
                    log: Self.dictationPerformanceLog,
                    name: "DecodeStarted"
                )
                let result = try await registry.transcribe(
                    audioURL: recordedAudio.url,
                    profile: behavior.languageProfile,
                    defaults: RuntimeIdentity.userDefaults(),
                    initialPrompt: behavior.context
                )
                os_signpost(
                    .event,
                    log: Self.dictationPerformanceLog,
                    name: "DecodeFinished"
                )
                let refinement =
                    TranscriptRefinement.refine(
                        result.finalTranscript,
                        mode: behavior.formattingMode.instantRefineMode,
                        languageCode:
                            behavior.languageProfile
                                .inputLanguageCode,
                        voiceCommandsEnabled:
                            behavior.voiceCommandsEnabled,
                        snippets: behavior.snippets
                    )
                let processed = ProcessedTranscription(
                    result: result,
                    refinement: refinement,
                    correctionApplication:
                        appliesCorrectionRules
                            ? try? await correctionVault?.applyCorrections(
                                to: refinement.text,
                                activeScope: behavior.correctionScope
                            )
                            : nil
                )
                await MainActor.run { [weak self] in
                    self?.complete(
                        processed: processed,
                        recordedAudio: recordedAudio,
                        historyID: historyID,
                        insertionText: insertedPreview.isEmpty ? nil : "",
                        hasPriorInsertion: !insertedPreview.isEmpty,
                        formattingMode: behavior.formattingMode
                    )
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    guard let recovered = previewFallback.processed(
                        modelID: fallbackModelID
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
                        hasPriorInsertion: !insertedPreview.isEmpty,
                        formattingMode: behavior.formattingMode
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
        registry: EngineRegistry,
        recordedAudio: AudioRecorder.RecordedAudio,
        behavior: ActiveDictationBehavior,
        correctionVault: DictationVault?,
        appliesCorrectionRules: Bool
    ) async -> ProcessedTranscription? {
        let defaults = RuntimeIdentity.userDefaults()
        guard let result = try? await registry.transcribe(
            audioURL: recordedAudio.url,
            profile: behavior.languageProfile,
            defaults: defaults,
            initialPrompt: behavior.context
        ) else {
            return nil
        }
        let refinement = TranscriptRefinement.refine(
            result.finalTranscript,
            mode: behavior.formattingMode.instantRefineMode,
            languageCode: behavior.languageProfile.inputLanguageCode,

            voiceCommandsEnabled: behavior.voiceCommandsEnabled,
                        snippets: behavior.snippets
        )
        return ProcessedTranscription(
            result: result,
            refinement: refinement,
            correctionApplication: appliesCorrectionRules
                ? try? await correctionVault?.applyCorrections(
                    to: refinement.text,
                    activeScope: behavior.correctionScope
                )
                : nil
        )
    }

    /// Falls back to the original behaviour: transcribe whatever followed the
    /// last committed phrase and append it to the preview text already on
    /// screen. Used when the inserted text could not be verified and replaced.
    ///
    /// Called off the main thread.
    private nonisolated func completeFromSegments(
        whisperEngine: WhisperSpeechEngine?,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID?,
        behavior: ActiveDictationBehavior,
        remainingSamples: [Float],
        correctionVault: DictationVault?,
        appliesCorrectionRules: Bool
    ) async {
        let expectsRemainder = remainingSamples.count >= 1_600
        guard let whisperEngine else {
            DispatchQueue.main.async { [weak self] in
                self?.handleTranscriptionFailure(
                    EngineError.noEngineAvailable,
                    recordedAudio: recordedAudio,
                    historyID: historyID
                )
            }
            return
        }
        do {
            let processed: ProcessedTranscription?
            if expectsRemainder {
                let result = try await whisperEngine.enqueuePreview(
                    samples: remainingSamples,
                    languageProfile: behavior.languageProfile,
                    initialPrompt: behavior.context
                )
                let refinement = TranscriptRefinement.refine(
                    result.finalTranscript,
                    mode: behavior.formattingMode.instantRefineMode,
                    languageCode: behavior.languageProfile.inputLanguageCode,

                    voiceCommandsEnabled: behavior.voiceCommandsEnabled,
                        snippets: behavior.snippets
                )
                processed = ProcessedTranscription(
                    result: result,
                    refinement: refinement,
                    correctionApplication: appliesCorrectionRules
                        ? try? await correctionVault?.applyCorrections(
                            to: refinement.text,
                            activeScope: behavior.correctionScope
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

    /// Esc cancels an active dictation from anywhere. The ZenBar panel is
    /// non-activating, so the key lands in whichever app has focus — a local
    /// monitor covers ZenVoice's own windows, a global one covers the rest.
    /// The global monitor only observes; the frontmost app still receives
    /// its Esc.
    private func updateEscapeToCancel(phase: AppState.Phase) {
        if case .listening = phase {
            guard escapeMonitors.isEmpty else {
                return
            }
            if let local = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown,
                handler: { [weak self] event in
                    guard event.keyCode == 53 else {
                        return event
                    }
                    self?.cancelRecording()
                    return nil
                }
            ) {
                escapeMonitors.append(local)
            }
            if let global = NSEvent.addGlobalMonitorForEvents(
                matching: .keyDown,
                handler: { [weak self] event in
                    guard event.keyCode == 53 else {
                        return
                    }
                    self?.cancelRecording()
                }
            ) {
                escapeMonitors.append(global)
            }
        } else {
            for monitor in escapeMonitors {
                NSEvent.removeMonitor(monitor)
            }
            escapeMonitors.removeAll()
        }
    }

    private func cancelRecording() {
        guard recorder.isRecording || state.isStartingRecording else {
            return
        }
        guard recorder.isRecording else {
            // The recorder has not opened the mic yet; flag it so the
            // in-flight startRecorder bails instead of starting anyway.
            cancelRequested = true
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
            Task { await bestEffortHistoryWrite { try await dictationVault?.discard(id: historyID) } }
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
            Task {
                await bestEffortHistoryWrite {
                    try await dictationVault?.markFailed(
                        id: historyID,
                        message: message,
                        retainAudio: historyPreferences.retainsFailedAudio
                    )
                }
            }
            // Retaining audio without arming the expiry timer means the 24-hour
            // promise only takes effect at the next launch.
            scheduleRecoveryExpiry()
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
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.beginLivePreviewSession()
            }
            return
        }
        resetLivePreviewSession()
        guard LiveDictationPreferences.isPreviewEnabled() else {
            return
        }
        state.livePreviewEnabled = true
        liveSessionID = UUID()
        liveTargetProcessIdentifier =
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        // startRecorder awaits before this; a Timer on that executor never
        // fires because it has no run loop.
        let timer = Timer(timeInterval: 0.20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshLivePreview()
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        livePreviewTimer = timer
    }

    private func refreshLivePreview() {
        guard LiveDictationPreferences.isPreviewEnabled() else {
            stopLivePreviewScheduling(invalidatePending: true)
            return
        }
        guard recorder.isRecording, !livePreviewInFlight else {
            return
        }
        if let segment = recorder.stableSegment(
            after: liveCommittedSampleIndex
        ) {
            decodeLiveSegment(segment, commits: true)
            return
        }
        previewUncommittedTail()
    }

    private func previewUncommittedTail() {
        let tail = recorder.samples(after: liveCommittedSampleIndex)
        let sampleRate = 16_000
        let minimumSamples = sampleRate * 2 / 5
        let strideSamples = sampleRate / 5
        let windowSamples = sampleRate * 2
        guard tail.count >= minimumSamples else {
            return
        }
        let endIndex = liveCommittedSampleIndex + tail.count
        guard endIndex - liveTailPreviewedIndex >= strideSamples else {
            return
        }
        liveTailPreviewedIndex = endIndex
        let window = Array(tail.suffix(windowSamples))
        decodeLiveSegment(
            AudioRecorder.StableAudioSegment(
                samples: window,
                endSampleIndex: endIndex
            ),
            commits: false
        )
    }

    private func decodeLiveSegment(
        _ segment: AudioRecorder.StableAudioSegment,
        commits: Bool
    ) {
        let previewEngine = engineRegistry?.resolvePreview(
            for: activeDictationBehavior.languageProfile
        )
        guard previewEngine != nil else {
            return
        }

        livePreviewInFlight = true
        let sessionID = liveSessionID
        let behavior = activeDictationBehavior
        let correctionVault = dictationVault
        let appliesCorrectionRules =
            commits && learningPreferences.appliesCorrectionRules
        livePreviewTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.transcribePreview(
                    engine: previewEngine,
                    samples: segment.samples,
                    languageProfile: behavior.languageProfile,
                    initialPrompt: behavior.context
                )
                let refinement = TranscriptRefinement.refine(
                    result.finalTranscript,
                    mode: behavior.formattingMode.instantRefineMode,
                    languageCode: behavior.languageProfile.inputLanguageCode,
                    voiceCommandsEnabled: behavior.voiceCommandsEnabled,
                        snippets: behavior.snippets
                )
                let correctionApplication = appliesCorrectionRules
                    ? try? await correctionVault?.applyCorrections(
                        to: refinement.text,
                        activeScope: behavior.correctionScope
                    )
                    : nil
                await MainActor.run {
                    let processed = ProcessedTranscription(
                        result: result,
                        refinement: refinement,
                        correctionApplication: correctionApplication
                    )
                    self.livePreviewTask = nil
                    if commits {
                        self.acceptStablePhrase(
                            processed,
                            endSampleIndex: segment.endSampleIndex,
                            sessionID: sessionID
                        )
                    } else {
                        self.acceptTailPreview(
                            processed,
                            sessionID: sessionID
                        )
                    }
                }
            } catch WhisperTranscriber.TranscriptionError.noSpeech {
                await MainActor.run {
                    guard self.liveSessionID == sessionID else { return }
                    self.livePreviewTask = nil
                    self.livePreviewInFlight = false
                }
            } catch {
                await MainActor.run {
                    guard self.liveSessionID == sessionID else { return }
                    self.livePreviewTask = nil
                    self.livePreviewInFlight = false
                }
            }
        }
    }

    private func acceptTailPreview(
        _ processed: ProcessedTranscription,
        sessionID: UUID
    ) {
        guard liveSessionID == sessionID else { return }
        livePreviewInFlight = false
        guard recorder.isRecording else { return }
        let phrase = processed.result.finalTranscript
        guard !phrase.isEmpty else { return }
        state.liveTranscriptPreview = StableTranscriptComposer.appending(
            phrase,
            to: liveStableFinalTranscript
        )
    }

    private func transcribePreview(
        engine: (any SpeechEngine)?,
        samples: [Float],
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> TranscriptionResult {
        guard let engine else {
            throw EngineError.noEngineAvailable
        }
        if let whisper = engine as? WhisperSpeechEngine {
            return try await whisper.enqueuePreview(
                samples: samples,
                languageProfile: languageProfile,
                initialPrompt: initialPrompt
            )
        }
        if let parakeet = engine as? ParakeetTDTEngine {
            return try await parakeet.enqueuePreview(
                samples: samples,
                languageProfile: languageProfile
            )
        }
        // File-based engines (Apple Speech, Qwen3-ASR, Cohere): hand them a
        // short temp clip through their existing WAV path. The preview never
        // touches the recovery file the whole-recording decode reads.
        guard !samples.isEmpty,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
              ) else {
            throw EngineError.noEngineAvailable
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zenvoice-preview-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw EngineError.noEngineAvailable
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData?.pointee.update(
                from: source.baseAddress!,
                count: samples.count
            )
        }
        try file.write(from: buffer)
        return try await engine.transcribe(
            audioURL: url,
            languageProfile: languageProfile,
            initialPrompt: initialPrompt
        )
    }

    private func acceptStablePhrase(
        _ processed: ProcessedTranscription,
        endSampleIndex: Int,
        sessionID: UUID
    ) {
        guard liveSessionID == sessionID else { return }
        livePreviewInFlight = false
        guard recorder.isRecording else { return }
        liveCommittedSampleIndex = endSampleIndex
        liveTailPreviewedIndex = endSampleIndex
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
        state.liveTranscriptPreview = liveStableFinalTranscript

        if let historyID = activeHistoryID,
           !nonPersistentHistoryIDs.contains(historyID),
           historyPreferences.isHistoryEnabled {
            let rawTranscript = liveStableRawTranscript
            let finalTranscript = liveStableFinalTranscript
            let correctionCount = liveStableCorrectionCount
            partialStoreSequence += 1
            let partialSequence = partialStoreSequence
            Task {
                // Finalized already? This partial is stale — skip the write.
                guard partialSequence > finalizedPartialStoreSequence else {
                    return
                }
                try? await dictationVault?.storePartialTranscript(
                    id: historyID,
                    rawTranscript: rawTranscript,
                    finalTranscript: finalTranscript,
                    correctionCount: correctionCount
                )
            }
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
        case .copiedOnly, .blockedBySecureInput:
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
            livePreviewTask?.cancel()
            livePreviewTask = nil
        }
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
        guard !finalTranscript.isEmpty, let whisperEngine else {
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
            modelID: whisperEngine.modelID,
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
        let formattingMode = activeDictationBehavior.formattingMode
        resetLivePreviewSession()

        complete(
            processed: processed,
            recordedAudio: recordedAudio,
            historyID: historyID,
            insertionText: insertionText,
            hasPriorInsertion: hasPriorInsertion,
            formattingMode: formattingMode
        )
    }

    private func resetLivePreviewSession() {
        stopLivePreviewScheduling(invalidatePending: true)
        liveCommittedSampleIndex = 0
        liveTailPreviewedIndex = 0
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
        hasPriorInsertion: Bool = false,
        formattingMode: TranscriptFormattingMode? = nil
    ) {
        Task {
            await completeNow(
                processed: processed,
                recordedAudio: recordedAudio,
                historyID: historyID,
                insertionText: insertionText,
                hasPriorInsertion: hasPriorInsertion,
                formattingMode: formattingMode
            )
        }
    }

    private func completeNow(
        processed: ProcessedTranscription,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID?,
        insertionText: String?,
        hasPriorInsertion: Bool,
        formattingMode: TranscriptFormattingMode?
    ) async {
        let result = processed.result
        let resolvedFormattingMode = formattingMode ?? activeDictationBehavior.formattingMode
        transcribingHistoryID = nil
        // A session whose input never rose above the Audio Doctor's quiet
        // threshold produced no speech the user can act on — usually a
        // muted or very quiet input device (Bluetooth headsets are the
        // repeat offender). Name the device and the remedy instead of
        // pasting nothing.
        if result.finalTranscript.isEmpty,
           insertionText == nil,
           !hasPriorInsertion,
           state.audioLevel.sessionPeak < Self.quietInputPeakThreshold {
            let deviceName = recordingDeviceName ?? "your microphone"
            if let historyID {
                if nonPersistentHistoryIDs.remove(historyID) == nil,
                   historyPreferences.isHistoryEnabled {
                    await bestEffortHistoryWrite {
                        try await resolvedVault().markFailed(
                            id: historyID,
                            message: "No audible speech captured.",
                            retainAudio: historyPreferences.retainsFailedAudio
                        )
                    }
                    scheduleRecoveryExpiry()
                } else {
                    await bestEffortHistoryWrite { try await resolvedVault().discard(id: historyID) }
                    try? FileManager.default.removeItem(at: recordedAudio.url)
                }
            } else {
                try? FileManager.default.removeItem(at: recordedAudio.url)
            }
            resetActiveDictationBehavior()
            dictationTargetProcessIdentifier = nil
            settingsViewModel.reportQuietInput(deviceName: deviceName)
            // Short on purpose: this renders inside the window-toolbar phase
            // pill, which collapses the toolbar when the label overflows.
            // The full remedy lives in the Dictation screen banner.
            showError("No audible speech")
            return
        }
        let insertionTarget = dictationTargetProcessIdentifier
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
        } ?? false
        var historySaveError: Error?
        if let historyID, shouldPersist {
            do {
                let vault = try await resolvedVault()
                // Any partial store scheduled before this point is stale
                // once the final transcript lands.
                finalizedPartialStoreSequence = partialStoreSequence
                try await vault.storeTranscript(
                    id: historyID,
                    rawTranscript: result.rawTranscript,
                    finalTranscript: result.finalTranscript,
                    correctionCount: result.correctionCount,
                    isPartial: result.isPartial
                )
                await archiveRecordingIfEnabled(historyID: historyID)
                try await vault.deleteRecoveryAudio(id: historyID)
                try? await vault.recordCorrectionUsage(
                    processed.correctionUsages
                )
            } catch {
                historySaveError = error
                await bestEffortHistoryWrite {
                    try await resolvedVault().markFailed(
                        id: historyID,
                        message: error.localizedDescription,
                        retainAudio: historyPreferences.retainsFailedAudio
                    )
                }
                scheduleRecoveryExpiry()
            }
        } else {
            if let historyID {
                await bestEffortHistoryWrite { try await resolvedVault().discard(id: historyID) }
            }
            try? FileManager.default.removeItem(at: recordedAudio.url)
        }

        state.recordSuccessfulDictation(
            transcript: result.finalTranscript,
            durationSeconds: recordedAudio.durationSeconds,
            runawayWordsCut: result.runawayWordsCut
        )
        state.phase = .inserting

        let textToInsert: String
        if let insertionText {
            textToInsert = insertionText
        } else {
            textToInsert = await enhanceForMode(
                result.finalTranscript,
                formattingMode: resolvedFormattingMode
            )
        }

        // Only dictation is exposed in the current ZenBar UI; command and
        // write mode are still compiled but not selectable.
        if state.mode != .dictation {
            state.mode = .dictation
        }

        if textToInsert.isEmpty {
            // The decoder produced no text. Pasting an empty string would
            // clobber the clipboard and claim success for nothing, so stop
            // here. A session that already streamed preview text keeps its
            // record; a textless one is discarded as junk.
            if let historyID, shouldPersist, historySaveError == nil,
               hasPriorInsertion {
                try? await resolvedVault().markInsertion(
                    id: historyID,
                    outcome: .inserted
                )
            } else if let historyID {
                await bestEffortHistoryWrite { try await resolvedVault().discard(id: historyID) }
            }
            state.phase = .success
            historyViewModel?.refresh()
            insightsViewModel?.refresh()
            voiceProfileViewModel?.refresh()
            scheduleIdleReset(after: successResetDelay)
            return
        }

        if isDeterministicE2E {
            state.phase = .success
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            let frontmost = NSWorkspace.shared.frontmostApplication?
                .processIdentifier
            if !TextInserter.shouldPaste(
                intoFrontmost: frontmost,
                originalTarget: insertionTarget
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    textToInsert,
                    forType: .string
                )
                if let historyID, shouldPersist, historySaveError == nil {
                    Task {
                        try? await self.resolvedVault().markInsertion(
                            id: historyID,
                            outcome: .copiedOnly
                        )
                    }
                }
                self.showError(
                    "Copied—switched apps during dictation."
                )
                self.historyViewModel?.refresh()
                self.insightsViewModel?.refresh()
                self.voiceProfileViewModel?.refresh()
                return
            }
            os_signpost(
                .event,
                log: Self.dictationPerformanceLog,
                name: "InsertionStarted"
            )
            switch self.inserter.insert(textToInsert) {
            case .pasted:
                os_signpost(
                    .event,
                    log: Self.dictationPerformanceLog,
                    name: "TextInserted"
                )
                if let historyID, shouldPersist, historySaveError == nil {
                    Task {
                        try? await self.resolvedVault().markInsertion(
                            id: historyID,
                            outcome: .inserted
                        )
                    }
                }
                self.state.phase = .success
                self.historyViewModel?.refresh()
                self.insightsViewModel?.refresh()
                self.voiceProfileViewModel?.refresh()
                self.scheduleIdleReset(after: self.successResetDelay)
            case .copiedOnly:
                if let historyID, shouldPersist, historySaveError == nil {
                    Task {
                        try? await self.resolvedVault().markInsertion(
                            id: historyID,
                            outcome: .copiedOnly
                        )
                    }
                }
                self.showError("Copied—enable Accessibility to auto-paste.")
            case .blockedBySecureInput:
                if let historyID, shouldPersist, historySaveError == nil {
                    Task {
                        try? await self.resolvedVault().markInsertion(
                            id: historyID,
                            outcome: .copiedOnly
                        )
                    }
                }
                // Naming the cause matters: nothing the user can change in
                // ZenVoice fixes this, and without an explanation the app
                // simply looks broken in one app and fine in the next.
                self.showError(
                    "Copied—\(self.secureInputAdvice())"
                )
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
        Task {
            await handleTranscriptionFailureNow(
                error,
                recordedAudio: recordedAudio,
                historyID: historyID
            )
        }
    }

    private func handleTranscriptionFailureNow(
        _ error: Error,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID?
    ) async {
        transcribingHistoryID = nil
        resetActiveDictationBehavior()
        let shouldPersist = historyID.map {
            nonPersistentHistoryIDs.remove($0) == nil
                && historyPreferences.isHistoryEnabled
        } ?? false
        if let historyID, shouldPersist {
            do {
                try await resolvedVault().markFailed(
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
                await bestEffortHistoryWrite { try await resolvedVault().discard(id: historyID) }
            }
            try? FileManager.default.removeItem(at: recordedAudio.url)
        }
        historyViewModel?.refresh()
        // Live-preview sessions route noSpeech here instead of through
        // completeNow's quiet-input guard, so re-derive the same diagnosis:
        // a silent session is a device problem, not a transcription one.
        if case WhisperTranscriber.TranscriptionError.noSpeech = error,
           state.audioLevel.sessionPeak < Self.quietInputPeakThreshold {
            settingsViewModel.reportQuietInput(
                deviceName: recordingDeviceName ?? "your microphone"
            )
        }
        showError(error.localizedDescription)
    }

    private func resolvedVault() async throws -> DictationVault {
        if let dictationVault {
            return dictationVault
        }
        // `DictationVault.live` suspends while it opens the database; a
        // second caller racing in would otherwise build a second vault.
        // One task owns the resolution and everyone awaits its result.
        let task: Task<DictationVault, Error>
        if let running = vaultResolutionTask {
            task = running
        } else {
            let policy = try RuntimeIdentity.policy()
            task = Task { try await DictationVault.live(policy: policy) }
            vaultResolutionTask = task
        }
        do {
            let vault = try await task.value
            dictationVault = vault
            vaultResolutionTask = nil
            return vault
        } catch {
            // Let the next caller start over instead of awaiting a failed
            // resolution forever.
            vaultResolutionTask = nil
            throw error
        }
    }

    /// History writes on teardown and cleanup paths are best-effort: they
    /// must not block quitting or abort dictation, but a bare `try?` lets
    /// audio outlive user intent silently, so log one line on failure
    /// (no transcript content).
    private func bestEffortHistoryWrite(
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
        } catch {
            NSLog(
                "ZenVoice: history write failed: %@",
                error.localizedDescription
            )
        }
    }

    private func resetActiveDictationBehavior() {
        activeDictationBehavior = .global
        state.languageProfile = LanguagePreferences.load()
        dictationTargetProcessIdentifier = nil
    }

    private func enhanceForMode(
        _ transcript: String,
        formattingMode: TranscriptFormattingMode? = nil
    ) async -> String {
        let formattingMode = formattingMode ?? activeDictationBehavior.formattingMode
        var text: String
        if formattingMode == .smart {
            let zenPolish = ZenPolishLanguageModel(
                modelsDirectory: try? VerifiedModelCatalog.modelsDirectory()
            )
            if ZenPolishPreferences.load(),
               zenPolish.availability == .available {
                text = await SmartFormattingEngine(
                    model: zenPolish,
                    timeoutSeconds: 10,
                    sendsRawTranscript: true
                ).format(
                    transcript,
                    languageCode: state.languageProfile.inputLanguageCode,
                    context: settingsViewModel?.sanitizedNextDictationContext
                ).text
            } else {
                text = await SmartFormattingEngine().format(
                    transcript,
                    languageCode: state.languageProfile.inputLanguageCode,
                    context: settingsViewModel?.sanitizedNextDictationContext
                ).text
            }
        } else {
            let mode = formattingMode.zenIntelligenceMode
            guard mode != .off else {
                text = transcript
                return await applySnippets(
                    await translatedIfNeeded(text)
                )
            }
            text = ZenIntelligenceEngine().enhance(
                transcript,
                mode: mode,
                languageCode: state.languageProfile.inputLanguageCode,
                context: settingsViewModel?.sanitizedNextDictationContext
            ).text
        }
        // Snippets run last — after formatting, guards, and translation.
        // They are user-authored expansions, so nothing upstream may
        // reword or reject them.
        return await applySnippets(await translatedIfNeeded(text))
    }

    /// The single snippet application point: user-authored expansions that
    /// run after formatting, guards, and translation — nothing upstream may
    /// reword or reject them.
    private func applySnippets(_ text: String) async -> String {
        let snippetResult = SnippetEngine().apply(
            to: text,
            snippets: activeDictationBehavior.snippets,
            isEnabled: !activeDictationBehavior.snippets.isEmpty
        )
        return snippetResult.text
    }

    private func translatedIfNeeded(_ transcript: String) async -> String {
        guard state.languageProfile.shouldTranslateToEnglish else {
            return transcript
        }
        let engineID = engineRegistry?.resolve(
            for: state.languageProfile,
            selectedID: SelectedEnginePreferences.load(
                for: state.languageProfile
            )
        )?.descriptor.id ?? ""
        if EngineIdentifiers.isWhisperFamily(engineID) {
            return transcript
        }
        let model = AppleOnDeviceLanguageModel()
        guard model.availability == .available else {
            return transcript
        }
        do {
            return try await model.generate(
                prompt: """
                Translate to English. Return only the translation.

                \(transcript)
                """,
                maximumResponseTokens: 512
            )
        } catch {
            return transcript
        }
    }

    private func showError(_ message: String) {
        state.phase = .error(message)
        updateStartStopMenuTitle()
        scheduleIdleReset(after: 4)
    }

    private func dismissZenBarError() {
        resetWorkItem?.cancel()
        state.phase = .idle
        updateStartStopMenuTitle()
    }

    private var isDeterministicE2E: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["ZENVOICE_E2E_AUTORUN"] == "1"
#else
        false
#endif
    }

#if DEBUG
    private func runDeterministicE2EIfRequested() {
        guard isDeterministicE2E,
              ProcessInfo.processInfo.environment[
                "ZENVOICE_E2E_AUDIO_FILE"
              ] != nil else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.waitForEngineConfiguration()
            let profile = LanguagePreferences.load()
            let selectedID = SelectedEnginePreferences.load(for: profile)
            try? await self.engineRegistry?.prepare(
                for: profile,
                selectedID: selectedID
            )
            await self.startRecorder()
            guard self.recorder.isRecording else {
                print("ZENVOICE_E2E_RESULT failure recorder-not-started")
                await self.finishDeterministicE2E()
                return
            }
            let started = Date()
            await self.finishRecordingNow()
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                switch self.state.phase {
                case .success:
                    let elapsed = Date().timeIntervalSince(started)
                    print(
                        String(
                            format: "ZENVOICE_E2E_RESULT success %.3f",
                            elapsed
                        )
                    )
                    await self.finishDeterministicE2E()
                    return
                case .error(let message):
                    print("ZENVOICE_E2E_RESULT failure \(message)")
                    await self.finishDeterministicE2E()
                    return
                default:
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
            print("ZENVOICE_E2E_RESULT failure timeout")
            await self.finishDeterministicE2E()
        }
    }

    private func finishDeterministicE2E() async {
        await engineRegistry?.releaseAll()
        FileHandle.standardOutput.synchronizeFile()
        exit(EXIT_SUCCESS)
    }
#endif

    /// Refuses to run if the bundle identifier is missing, empty, or foreign.
    ///
    /// This is the fail-closed gate for the production Application Support path,
    /// UserDefaults suite, and Keychain namespace. It must run before any
    /// production storage is initialized.
    private func validateRuntimeIdentity() {
        do {
            _ = try RuntimeIdentity.policy()
        } catch {
            let alert = NSAlert()
            alert.messageText = "ZenVoice cannot start"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    /// A plain "inserted" needs a moment; a distrust warning needs long
    /// enough to actually be read.
    private var successResetDelay: TimeInterval {
        state.lastDecodeWarning == nil ? 1.5 : 4
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
        scheduleIdleReset(after: successResetDelay)
    }

    @objc private func pasteLastTranscript() {
        Task { await pasteLastTranscriptNow() }
    }

    private func pasteLastTranscriptNow() async {
        let transcript: String?
        if !state.lastTranscript.isEmpty {
            transcript = state.lastTranscript
        } else if historyPreferences.hasEverEnabledHistory,
                  let dictationVault {
            transcript = try? await dictationVault
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
            scheduleIdleReset(after: successResetDelay)
        case .copiedOnly:
            showError("Copied—enable Accessibility to auto-paste.")
        case .blockedBySecureInput:
            showError("Copied—\(secureInputAdvice())")
        }
    }

    /// Names the app holding secure input open, when it can be identified.
    ///
    /// Secure input is process-wide and system-enforced: while it is on, macOS
    /// refuses to deliver synthetic keystrokes to anyone. The usual culprits
    /// are Chromium-based browsers and Electron apps, which switch it on
    /// around password fields and often leave it on afterwards. Telling the
    /// user which app to click away from is the only actionable advice there
    /// is.
    private func secureInputAdvice() -> String {
        let frontmost = NSWorkspace.shared.frontmostApplication?
            .localizedName
        guard let frontmost else {
            return "another app has secure input on, blocking auto-paste."
        }
        return "\(frontmost) has secure input on, blocking auto-paste. "
            + "Click another app and back, or reopen it."
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

    private func handlePrivacyChanged() {
        guard !historyPreferences.isHistoryEnabled else {
            return
        }
        if let activeHistoryID {
            nonPersistentHistoryIDs.insert(activeHistoryID)
            Task { @MainActor in
                do {
                    try await dictationVault?.suppressPersistence(
                        id: activeHistoryID
                    )
                } catch {
                    showError(
                        "Could not update local history: "
                        + error.localizedDescription
                    )
                }
            }
        }
        if let transcribingHistoryID {
            nonPersistentHistoryIDs.insert(transcribingHistoryID)
            Task { @MainActor in
                do {
                    try await dictationVault?.suppressPersistence(
                        id: transcribingHistoryID
                    )
                } catch {
                    showError(
                        "Could not update local history: "
                        + error.localizedDescription
                    )
                }
            }
        }
    }

    private func scheduleRecoveryExpiry() {
        Task { await scheduleRecoveryExpiryNow() }
    }

    private func scheduleRecoveryExpiryNow() async {
        recoveryExpiryTimer?.invalidate()
        guard let vault = dictationVault,
              let expiry = try? await vault.nextRecoveryExpiry() else {
            return
        }
        let delay = max(1, expiry.timeIntervalSinceNow)
        recoveryExpiryTimer = Timer.scheduledTimer(
            withTimeInterval: delay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = try? await self.dictationVault?
                    .purgeExpiredRecoveryAudio()
                self.historyViewModel?.refresh()
                await self.scheduleRecoveryExpiryNow()
            }
        }
    }

    private func retryHistoryRecord(
        _ record: DictationRecord
    ) async -> Result<Void, Error> {
        guard !state.isBusy, state.phase != .listening, !retryInFlight else {
            return .failure(
                DictationVaultError.database(
                    "Finish the current dictation before retrying."
                )
            )
        }
        // A pending idle reset would flip the phase to .idle in the middle
        // of the decode below; cancel it like the dictation path does.
        resetWorkItem?.cancel()
        retryInFlight = true
        defer { retryInFlight = false }
        guard record.recoveryAudioURL != nil else {
            return .failure(
                DictationVaultError.database(
                    "The recovery audio is no longer available."
                )
            )
        }
        // Decrypted recovery audio must not sit world-readable in the shared
        // temp directory while the decoder runs. Park it in a 0700 directory
        // (macOS has no FileProtectionType; permissions are the mechanism)
        // and remove the directory as soon as the decode finishes or fails.
        let retryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "zenvoice-retry-\(record.id.uuidString)",
                isDirectory: true
            )
        let plaintextURL = retryDirectory.appendingPathComponent("audio.wav")
        do {
            try FileManager.default.createDirectory(
                at: retryDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let wav = try await resolvedVault().recoveryAudioData(id: record.id)
            try wav.write(to: plaintextURL, options: .atomic)
            // `.atomic` writes with default permissions; tighten the file
            // itself to 0600 immediately after it lands.
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: plaintextURL.path
            )
        } catch {
            try? FileManager.default.removeItem(at: retryDirectory)
            return .failure(error)
        }
        guard let registry = engineRegistry else {
            try? FileManager.default.removeItem(at: retryDirectory)
            return .failure(
                DictationVaultError.database(
                    "No speech engine is available."
                )
            )
        }
        let recordedLanguageProfile = LanguageProfile.historyRetryProfile(
            languageCode: record.language,
            modelID: record.modelID
        )
        let selectedID = SelectedEnginePreferences.load(
            for: recordedLanguageProfile
        )
        guard let resolvedEngine = registry.resolve(
            for: recordedLanguageProfile,
            selectedID: selectedID
        ),
              recordedLanguageProfile.isCompatible(
                  with: resolvedEngine.languageCapability
              ) else {
            try? FileManager.default.removeItem(at: retryDirectory)
            return .failure(
                DictationVaultError.database(
                    "This recording used \(recordedLanguageProfile.displayName). "
                        + "Select a compatible engine before retrying."
                )
            )
        }

        do {
            try await resolvedVault().markTranscribing(
                id: record.id,
                durationSeconds: record.durationSeconds
            )
        } catch {
            try? FileManager.default.removeItem(at: retryDirectory)
            return .failure(error)
        }

        state.phase = .transcribing
        transcribingHistoryID = record.id
        let recordedAudio = AudioRecorder.RecordedAudio(
            url: plaintextURL,
            durationSeconds: record.durationSeconds
        )
        let correctionVault = dictationVault
        let appliesCorrectionRules =
            learningPreferences.appliesCorrectionRules
        let correctionScope = recordedLanguageProfile.correctionScope
        let preferredVocabulary =
            appliesCorrectionRules
                ? (try? await correctionVault?.preferredVocabulary(
                    activeScope: correctionScope
                )) ?? []
                : []
        let initialPrompt = NextDictationContext.combined(
            context: "",
            preferredVocabulary: preferredVocabulary
        )
        let formattingMode = TranscriptFormattingPreferences.load()
        let voiceCommandsEnabled =
            LocalVoiceCommandPreferences.isEnabled()
        let activeSnippets = SnippetPreferences.load()
        Task { [weak self] in
            defer { try? FileManager.default.removeItem(at: retryDirectory) }
            do {
                let result = try await registry.transcribe(
                    audioURL: plaintextURL,
                    profile: recordedLanguageProfile,
                    defaults: RuntimeIdentity.userDefaults(),
                    initialPrompt: initialPrompt
                )
                let refinement =
                    TranscriptRefinement.refine(
                        result.finalTranscript,
                        mode: formattingMode.instantRefineMode,
                        languageCode:
                            recordedLanguageProfile.inputLanguageCode,
                        voiceCommandsEnabled: voiceCommandsEnabled,
                        snippets: activeSnippets
                    )
                let processed = ProcessedTranscription(
                    result: result,
                    refinement: refinement,
                    correctionApplication:
                        appliesCorrectionRules
                            ? try? await correctionVault?.applyCorrections(
                                to: refinement.text,
                                activeScope: correctionScope
                            )
                            : nil
                )
                await self?.completeHistoryRetry(
                    processed: processed,
                    recordedAudio: recordedAudio,
                    historyID: record.id
                )
            } catch {
                await MainActor.run {
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
    ) async {
        let result = processed.result
        transcribingHistoryID = nil
        ModelBenchmarkStore.record(
            modelID: result.modelID,
            audioDurationSeconds: recordedAudio.durationSeconds,
            processingDurationSeconds: result.processingDurationSeconds
        )
        modelManagerViewModel?.refreshBenchmarks()
        guard nonPersistentHistoryIDs.remove(historyID) == nil,
              historyPreferences.isHistoryEnabled else {
            await bestEffortHistoryWrite { try await resolvedVault().discard(id: historyID) }
            try? FileManager.default.removeItem(at: recordedAudio.url)
            showError("History is paused; this retry was not saved.")
            return
        }
        do {
            let vault = try await resolvedVault()
            try await vault.storeTranscript(
                id: historyID,
                rawTranscript: result.rawTranscript,
                finalTranscript: result.finalTranscript,
                correctionCount: result.correctionCount,
                isPartial: result.isPartial
            )
            await archiveRecordingIfEnabled(historyID: historyID)
            try await vault.deleteRecoveryAudio(id: historyID)
            try? await vault.recordCorrectionUsage(processed.correctionUsages)
            state.recordSuccessfulDictation(
                transcript: result.finalTranscript,
                durationSeconds: recordedAudio.durationSeconds,
                runawayWordsCut: result.runawayWordsCut
            )
            state.phase = .success
            historyViewModel.refresh()
            insightsViewModel.refresh()
            voiceProfileViewModel.refresh()
            scheduleIdleReset(after: successResetDelay)
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
        case .listening, .transcribing, .inserting,
             .error:
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

    /// Recomputes today's usage as the menu opens, so the pill is current
    /// without polling insights on a timer.
    func menuWillOpen(_ menu: NSMenu) {
        refreshTodayUsagePill()
        refreshAccessibilityMenuItem()
    }

    /// Keeps the menu honest about auto-paste.
    ///
    /// Accessibility can be revoked in System Settings at any time, and when
    /// that happens dictation quietly falls back to the clipboard. The menu is
    /// the one surface a menu-bar app always has, so it says which mode the
    /// user is actually in.
    private func refreshAccessibilityMenuItem() {
        guard let item = accessibilityMenuItem else { return }
        if AXIsProcessTrusted() {
            item.title = "Auto-Paste Enabled"
            item.state = .on
            item.isEnabled = false
            item.action = nil
        } else {
            item.title = "Enable Auto-Paste Permission…"
            item.state = .off
            item.isEnabled = true
            item.action = #selector(requestAccessibilityPermission)
            item.target = self
        }
        settingsViewModel?.refreshSystemStatus()
    }

    private func refreshTodayUsagePill() {
        Task { await refreshTodayUsagePillNow() }
    }

    private func refreshTodayUsagePillNow() async {
        let today = (try? await dictationVault?.insights().today) ?? nil
        let summary = (today ?? .empty).pillSummary
        todayUsageMenuItem?.title = summary
        statusItem?.button?.toolTip = "ZenVoice — \(summary)"
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
        zenBarController.reposition()
    }

    /// Rebuilds the overlay panel when the user picks a different overlay kind
    /// or toggles live previews off. The panel's kind is fixed at construction,
    /// so a change means building a new one and restoring its visibility.
    @objc private func overlayPreferencesChanged() {
        let preview = LiveDictationPreferences.isPreviewEnabled()
        let previewChanged = state.livePreviewEnabled != preview
        state.livePreviewEnabled = preview
        if previewChanged {
            if recorder.isRecording {
                recorder.setCapturesLiveSamples(preview)
                liveSamplesEnabledForRecording = preview
                if preview {
                    beginLivePreviewSession()
                } else {
                    resetLivePreviewSession()
                }
            } else {
                state.liveTranscriptPreview = ""
            }
        }
        let kind = resolvedOverlayKind()
        if zenBarController.matches(
            kind: kind,
            reduceMotion: OverlayPreferences.loadReduceMotion()
        ) {
            zenBarController.reposition()
            return
        }
        zenBarController.hide()
        makeOverlayController()
        updateZenBarPresentation(
            phase: state.phase,
            showsAtAllTimes: state.showsZenVoiceAtAllTimes
        )
    }

    private func resolvedOverlayKind() -> OverlayKind {
        .livePreviewPill
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
