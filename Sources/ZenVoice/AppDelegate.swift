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
    let modelID: String

    static var global: ActiveDictationBehavior {
        let languageProfile = LanguagePreferences.load()
        return ActiveDictationBehavior(
            languageProfile: languageProfile,
            correctionScope: languageProfile.correctionScope,
            formattingMode: TranscriptFormattingPreferences.load(),
            voiceCommandsEnabled: false,
            context: "",
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
    private lazy var commandExecutor: CommandModeExecutorImpl = {
        CommandModeExecutorImpl(
            state: state,
            pasteLast: { [weak self] in self?.pasteLastTranscript() },
            showSettings: { [weak self] in self?.settingsWindowController.show() }
        )
    }()
    private lazy var writeReader = WriteModeTextReaderImpl()

    private var statusItem: NSStatusItem!
    private var startStopMenuItem: NSMenuItem!
    private var zenBarMenuItem: NSMenuItem!
    private var statusMessageMenuItem: NSMenuItem!
    private var todayUsageMenuItem: NSMenuItem!
    private var livePreviewMenuItem: NSMenuItem!
    private var languageMenuItem: NSMenuItem!
    private var accessibilityMenuItem: NSMenuItem!
    private var zenBarController: OverlayPanelController!
    private var escapeMonitors: [Any] = []
    private var globalHotKey: GlobalHotKey?
    private var pasteLastGlobalHotKey: GlobalHotKey?
    private var privateModeGlobalHotKey: GlobalHotKey?
    private var holdToDictateController: HoldToDictateController?
    private var engineRegistry: EngineRegistry?
    private var whisperEngine: WhisperSpeechEngine?
    private var engineConfigurationTask: Task<Void, Never>?
    private var resetWorkItem: DispatchWorkItem?
    private var stateObservers: Set<AnyCancellable> = []
    private var currentHotKeyConfiguration = HotKeyPreferences.load()
    private var pasteLastHotKeyConfiguration =
        HotKeyPreferences.loadPasteLast()
    private var privateModeHotKeyConfiguration =
        HotKeyPreferences.loadPrivateMode()
    private var settingsViewModel: SettingsViewModel!
    private var historyViewModel: HistoryViewModel!
    private var audioHistoryViewModel: AudioHistoryViewModel!
    private var cloudAIViewModel: CloudAIViewModel!
    private var cloudPreviewWindowController:
        CloudAIPreviewWindowController?

    /// Applies cloud enhancement to a finished local transcript.
    ///
    /// Consent to send text off-device is given once, in Formatting: enabling
    /// the feature, storing a key, and choosing the Cloud rung. When the user
    /// has also asked for enhancements to apply automatically, this runs the
    /// request and returns the result without interrupting them. Otherwise it
    /// shows the review panel — which deliberately does not take focus.
    /// The transcript to carry forward, and whether a provider produced it.
    ///
    /// `didApply` is what lets `complete` tell "the cloud rewrote this" from
    /// "the cloud rung was selected but nothing happened" — the two need
    /// different local formatting and used to be indistinguishable.
    fileprivate struct CloudEnhancementOutcome {
        let processed: ProcessedTranscription
        let didApply: Bool
    }

    /// Inserts the locally formatted result before an optional cloud request.
    /// The cloud result may replace this exact text later, but never blocks the
    /// first useful output and never targets a different application.
    private func insertLocalBeforeCloud(
        _ processed: ProcessedTranscription,
        formattingMode: TranscriptFormattingMode,
        targetProcessIdentifier: pid_t?
    ) async -> String {
        guard formattingMode == .cloud,
              let targetProcessIdentifier,
              AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier
                == targetProcessIdentifier else {
            return ""
        }
        let text = await enhanceForMode(
            processed.result.finalTranscript,
            formattingMode: formattingMode
        )
        guard !text.isEmpty else {
            return ""
        }
        let candidate = text + " "
        guard case .pasted = inserter.insert(candidate) else {
            return ""
        }
        state.phase = .inserting
        os_signpost(
            .event,
            log: Self.dictationPerformanceLog,
            name: "LocalTextInserted"
        )
        return candidate
    }

    private func processCloudEnhancement(
        localProcessed: ProcessedTranscription,
        formattingMode: TranscriptFormattingMode
    ) async -> CloudEnhancementOutcome {

        guard formattingMode == .cloud else {
            return CloudEnhancementOutcome(
                processed: localProcessed,
                didApply: false
            )
        }
        guard cloudAIViewModel.isReady else {
            // Cloud is the selected rung but it cannot run. Silently using
            // local formatting made the app look like it had enhanced the
            // text when it never left the Mac, so say so instead.
            showError(cloudNotReadyMessage())
            return CloudEnhancementOutcome(
                processed: localProcessed,
                didApply: false
            )
        }

        let original = localProcessed.result.finalTranscript
        if CloudAIPreferences.load().autoApply {
            guard let enhanced = await enhanceWithoutPrompting(original)
            else {
                return CloudEnhancementOutcome(
                    processed: localProcessed,
                    didApply: false
                )
            }
            return CloudEnhancementOutcome(
                processed: localProcessed
                    .replacingFinalTranscript(with: enhanced),
                didApply: true
            )
        }

        return await awaitCloudReview(localProcessed: localProcessed)
    }

    /// Shows the review panel and waits for an answer.
    ///
    /// The wait holds the whole dictation open: `complete` has not run, so
    /// `state.phase` is still `.transcribing`, `state.isBusy` is true, and the
    /// dictation shortcut, hold-to-dictate and the menu item are all inert.
    /// The panel is a non-activating one that deliberately does not take
    /// focus, so a user who does not notice it just sees a hotkey that stopped
    /// working, with nothing on screen explaining why. Three things keep that
    /// from being a dead end:
    ///
    ///   * the ZenBar says what it is waiting for;
    ///   * pressing the dictation shortcut dismisses the panel and keeps the
    ///     local transcript, so the way out is the key you already pressed;
    ///   * `cloudReviewTimeout` resolves it anyway if nobody answers.
    private func awaitCloudReview(
        localProcessed: ProcessedTranscription
    ) async -> CloudEnhancementOutcome {
        let original = localProcessed.result.finalTranscript
        return await withCheckedContinuation { continuation in
            // Whichever of answer, dismissal or timeout arrives first wins;
            // the rest become no-ops. Resuming a continuation twice traps.
            var hasResumed = false
            let finish: (String?) -> Void = { [weak self] acceptedText in
                guard !hasResumed else { return }
                hasResumed = true
                self?.cloudReviewTimeoutTask?.cancel()
                self?.cloudReviewTimeoutTask = nil
                self?.dismissCloudReviewPanel()
                let resolution = CloudTranscriptResolution.resolve(
                    localTranscript: original,
                    acceptedTranscript: acceptedText
                )
                continuation.resume(
                    returning: CloudEnhancementOutcome(
                        processed: resolution.didApply
                            ? localProcessed.replacingFinalTranscript(
                                with: resolution.transcript
                            )
                            : localProcessed,
                        didApply: resolution.didApply
                    )
                )
            }

            let controller = CloudAIPreviewWindowController(
                original: original,
                keyStore: makeCloudAIKeyStore()
            ) { acceptedText in
                finish(acceptedText)
            }
            cloudPreviewWindowController = controller
            cancelPendingCloudReview = { finish(nil) }
            state.phase = .awaitingCloudReview
            updateStartStopMenuTitle()
            controller.show()

            cloudReviewTimeoutTask = Task { [weak self] in
                try? await Task.sleep(
                    nanoseconds: UInt64(Self.cloudReviewTimeout * 1_000_000_000)
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self != nil else { return }
                    finish(nil)
                }
            }
        }
    }

    /// How long the review panel waits before keeping the local transcript.
    ///
    /// Long enough to read a paragraph and decide, short enough that an
    /// unnoticed panel cannot hold dictation open indefinitely.
    private static let cloudReviewTimeout: TimeInterval = 120

    /// Resolves a pending review with the local transcript. Set only while a
    /// panel is on screen.
    private var cancelPendingCloudReview: (() -> Void)?

    private var cloudReviewTimeoutTask: Task<Void, Never>?

    private func dismissCloudReviewPanel() {
        cancelPendingCloudReview = nil
        cloudPreviewWindowController?.close()
        cloudPreviewWindowController = nil
    }

    /// Whether a review panel is waiting for an answer right now.
    private var isAwaitingCloudReview: Bool {
        cancelPendingCloudReview != nil
    }

    /// Runs the enhancement request with no UI at all, for the auto-apply
    /// path. Returns nil when the transcript should be left as it is; the
    /// failure is reported without stealing focus or blocking insertion.
    private func enhanceWithoutPrompting(
        _ transcript: String
    ) async -> String? {
        guard let key = ((try? makeCloudAIKeyStore().loadKey()) ?? nil),
              !key.isEmpty else {
            showError(cloudNotReadyMessage())
            return nil
        }
        do {
            let result = try await CloudAIEnhancementEngine().enhance(
                transcript: transcript,
                configuration: CloudAIPreferences.load(),
                apiKey: key
            )
            return result.enhanced
        } catch {
            showError(
                "Cloud enhancement failed — kept your local transcript. "
                + error.localizedDescription
            )
            return nil
        }
    }

    private func cloudNotReadyMessage() -> String {
        let configuration = CloudAIPreferences.load()
        if !configuration.isEnabled {
            return "Formatting is set to Cloud but Cloud AI is off — used "
                + "local formatting. Turn it on in Formatting."
        }
        if ((try? makeCloudAIKeyStore().loadKey()) ?? nil)?.isEmpty ?? true {
            return "Formatting is set to Cloud but no API key is stored — "
                + "used local formatting. Add a key in Formatting."
        }
        return "Formatting is set to Cloud but the provider endpoint is "
            + "invalid — used local formatting. Check it in Formatting."
    }

    private var updatesViewModel: UpdatesViewModel!
    private var insightsViewModel: InsightsViewModel!
    private var voiceProfileViewModel: VoiceProfileViewModel!
    private var modelManagerViewModel: ModelManagerViewModel!
    private var applicationProfileViewModel:
        ApplicationProfileViewModel!
    private let onboardingViewModel = OnboardingViewModel(
        showAtLaunch: OnboardingPreferences.shouldPresent()
    )
    private var settingsWindowController: SettingsWindowController!
    private let historyPreferences = HistoryPreferences()
    private let audioHistoryPreferences = AudioHistoryPreferences()
    private let learningPreferences = LocalLearningPreferences()
    private var dictationVault: DictationVault?
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
        configureAnticipatoryWarmup()
        configureSettingsWindow()
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
                || historyPreferences.isPrivateModeEnabled
                || !historyPreferences.isHistoryEnabled {
                try? await dictationVault?.discard(id: historyID)
            } else {
                try? await dictationVault?.markFailed(
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
            try? await dictationVault?.discard(id: processingHistoryID)
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
            // ZenVoice can still offer Apple Speech and Parakeet even when no
            // Whisper model is installed yet. Defer the error message until
            // dictation actually starts without an available engine.
            let whisper = WhisperSpeechEngine(
                configuration: ZenVoiceConfiguration(
                    modelURL: URL(fileURLWithPath: "/dev/null")
                )
            )
            whisperEngine = whisper
            engineRegistry = makeEngineRegistry(whisper: whisper)
        } catch {
            state.phase = .error(error.localizedDescription)
        }
        modelManagerViewModel?.refreshEngineSelection()
        settingsViewModel?.refreshSystemStatus()
    }

    private func makeEngineRegistry(whisper: WhisperSpeechEngine) -> EngineRegistry {
        let apple = AppleSpeechEngine()
        let parakeetFlash = makeParakeetFlashEngine()
        let parakeetTDTv2 = makeParakeetTDTEngine(.v2)
        let parakeetTDTv3 = makeParakeetTDTEngine(.v3)
        let nemotronUltraFast = makeNemotronSpeechUltraFastEngine()
        let nemotronMultilingual = makeNemotronSpeechMultilingualEngine()
        let cohere = makeCohereTranscribeEngine()
        var engines: [any SpeechEngine] = [whisper, apple]
        if let parakeetFlash {
            engines.append(parakeetFlash)
        }
        if let parakeetTDTv2 {
            engines.append(parakeetTDTv2)
        }
        if let parakeetTDTv3 {
            engines.append(parakeetTDTv3)
        }
        if let nemotronUltraFast {
            engines.append(nemotronUltraFast)
        }
        if let nemotronMultilingual {
            engines.append(nemotronMultilingual)
        }
        if let cohere {
            engines.append(cohere)
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

    private func makeParakeetFlashEngine() -> ParakeetFlashEngine? {
        makeEngineIfModelExists(
            filename: ParakeetFlashEngine.modelFilename
        ) { url in
            ParakeetFlashEngine(modelURL: url)
        }
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

    private func makeNemotronSpeechUltraFastEngine()
        -> NemotronSpeechUltraFastEngine? {
        makeEngineIfModelExists(
            filename: NemotronEngineConstants.modelFilename
        ) { url in
            NemotronSpeechUltraFastEngine(modelURL: url)
        }
    }

    private func makeNemotronSpeechMultilingualEngine()
        -> NemotronSpeechMultilingualEngine? {
        makeEngineIfModelExists(
            filename: NemotronEngineConstants.modelFilename
        ) { url in
            NemotronSpeechMultilingualEngine(modelURL: url)
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
            if LiveDictationPreferences.isPreviewEnabled(),
               let preview = registry.resolvePreview(for: profile) {
                try? await preview.prepare()
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

    /// The Keychain store for the Cloud AI provider key.
    ///
    /// Falls back to an in-memory store if the runtime identity cannot be
    /// resolved, so a misconfigured build cannot silently write a live
    /// third-party credential somewhere unexpected.
    private func makeCloudAIKeyStore() -> CloudAIKeyStoring {
        guard let policy = try? RuntimeIdentity.policy() else {
            return InMemoryCloudAIKeyStore()
        }
        return CloudAIKeychainKeyStore(policy: policy)
    }


    /// Copies a completed recording into the Audio History archive.
    ///
    /// Archiving piggybacks on transcript persistence: the archive row is
    /// derived from the dictation row, so a dictation that is not persisted —
    /// Private Dictation, paused history, a one-off suppression — is never
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
        guard audioHistoryPreferences.isEnabled,
              let vault = dictationVault else {
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

        livePreviewMenuItem = NSMenuItem(
            title: "Show Live Preview Overlay",
            action: #selector(toggleLivePreviewOverlay),
            keyEquivalent: ""
        )
        livePreviewMenuItem.target = self
        livePreviewMenuItem.state =
            OverlayPreferences.loadLivePreviewEnabled() ? .on : .off
        menu.addItem(livePreviewMenuItem)

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
            setMode: { [weak self] mode in
                self?.state.mode = mode
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
            },
            isSpeechEngineReady: { [weak self] in
                let profile = LanguagePreferences.load()
                let selectedID = SelectedEnginePreferences.load(for: profile)
                return self?.engineRegistry?.resolve(
                    for: profile,
                    selectedID: selectedID
                ) != nil
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
        cloudAIViewModel = CloudAIViewModel(
            keyStore: makeCloudAIKeyStore(),
            lastTranscript: { [weak self] in
                self?.state.lastTranscript ?? ""
            },
            applyEnhanced: { [weak self] text in
                self?.state.lastTranscript = text
            }
        )
        updatesViewModel = UpdatesViewModel()
        settingsWindowController = SettingsWindowController(
            viewModel: settingsViewModel,
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
            appState: state,
            toggleRecording: { [weak self] in
                self?.toggleRecording()
            }
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
        // A pending cloud review holds the previous dictation open behind a
        // panel that never takes focus. The shortcut is the key the user has
        // already pressed, so it is the one that has to get them out: it
        // resolves the review with the local transcript rather than starting
        // a second dictation on top of an unfinished one.
        if isAwaitingCloudReview {
            cancelPendingCloudReview?()
            return
        }
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

        if whisperEngine == nil {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.waitForEngineConfiguration()
                guard self.whisperEngine != nil else { return }
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
        guard !recorder.isRecording, !state.isBusy else {
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
           historyPreferences.isHistoryEnabled,
           !historyPreferences.isPrivateModeEnabled {
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
            dictationTargetProcessIdentifier = nil
            if let historyID = historyDraft?.id {
                try? await dictationVault?.discard(id: historyID)
                activeHistoryID = nil
            }
            showError(error.localizedDescription)
        }
    }

    private func resolvedDictationBehavior(
        targetBundleIdentifier: String?
    ) async -> ActiveDictationBehavior? {
        let profile = ApplicationProfilePreferences.profile(
            for: targetBundleIdentifier
        )
        let baseLanguageProfile =
            profile?.languageProfile ?? LanguagePreferences.load()
        let languageProfile: LanguageProfile
        if let preferredOutputMode = profile?.preferredOutputMode {
            languageProfile = LanguageProfile(
                inputLanguageCode: baseLanguageProfile.inputLanguageCode,
                outputMode: preferredOutputMode
            )
        } else {
            languageProfile = baseLanguageProfile
        }
        let selectedID =
            profile?.preferredEngineID
            ?? SelectedEnginePreferences.load(for: languageProfile)
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
        let profileFormattingMode = profile?.formattingMode
        return ActiveDictationBehavior(
            languageProfile: languageProfile,
            correctionScope: correctionScope,
            formattingMode:
                isDeterministicE2E
                    ? .clean
                    : profileFormattingMode
                        ?? TranscriptFormattingPreferences.load(),
            voiceCommandsEnabled:
                profile?.voiceCommandsEnabled
                ?? LocalVoiceCommandPreferences.isEnabled(),
            context:
                NextDictationContext.combined(
                    context:
                        settingsViewModel.sanitizedNextDictationContext,
                    preferredVocabulary: preferredVocabulary
                ),
            modelID:
                (resolvedEngine as? WhisperSpeechEngine)?.modelID
                ?? resolvedEngine.descriptor.id
        )
    }

    private func finishRecording() {
        Task { await finishRecordingNow() }
    }

    private func finishRecordingNow() async {
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

        if let historyID {
            do {
                try await resolvedVault().markTranscribing(
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
                            behavior.voiceCommandsEnabled
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
                let insertedBeforeCloud: String
                if insertedPreview.isEmpty {
                    insertedBeforeCloud = await Task {
                        @MainActor [weak self] in
                        guard let self else { return "" }
                        return await self.insertLocalBeforeCloud(
                            processed,
                            formattingMode: behavior.formattingMode,
                            targetProcessIdentifier: insertionTargetProcess
                        )
                    }.value
                } else {
                    insertedBeforeCloud = insertedPreview
                }
                os_signpost(
                    .event,
                    log: Self.dictationPerformanceLog,
                    name: "CloudEnhancementStarted"
                )
                let cloudOutcome = await Task { @MainActor [weak self] in
                    guard let self else {
                        return CloudEnhancementOutcome(
                            processed: processed,
                            didApply: false
                        )
                    }
                    return await self.processCloudEnhancement(
                        localProcessed: processed,
                        formattingMode: behavior.formattingMode
                    )
                }.value
                os_signpost(
                    .event,
                    log: Self.dictationPerformanceLog,
                    name: "CloudEnhancementFinished"
                )
                let cloudProcessed = cloudOutcome.processed
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard !insertedBeforeCloud.isEmpty else {
                        self.complete(
                            processed: cloudProcessed,
                            recordedAudio: recordedAudio,
                            historyID: historyID,
                            formattingMode: behavior.formattingMode,
                            cloudDidApply: cloudOutcome.didApply
                        )
                        return
                    }
                    // Only swap while the caret is still where the preview
                    // text was typed. Cloud enhancement can take seconds, and
                    // if the user has moved to another application in the
                    // meantime this would overwrite whatever happens to sit
                    // before *that* caret.
                    if NSWorkspace.shared.frontmostApplication?
                        .processIdentifier == insertionTargetProcess {
                        _ = self.inserter.replaceTextBeforeCaret(
                            insertedBeforeCloud,
                            with: cloudProcessed.result.finalTranscript + " "
                        )
                    }
                    // Whether or not the swap succeeded, preview text is
                    // already on screen. Inserting again would give the user
                    // their dictation twice, which is worse than either
                    // failure on its own — so the accurate transcript is
                    // recorded in history and nothing further is typed.
                    self.complete(
                        processed: cloudProcessed,
                        recordedAudio: recordedAudio,
                        historyID: historyID,
                        insertionText: "",
                        hasPriorInsertion: true,
                        formattingMode: behavior.formattingMode,
                        cloudDidApply: cloudOutcome.didApply
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

            voiceCommandsEnabled: behavior.voiceCommandsEnabled
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
                let result = try whisperEngine.transcribe(
                    samples: remainingSamples,
                    languageProfile: behavior.languageProfile,
                    initialPrompt: behavior.context
                )
                let refinement = TranscriptRefinement.refine(
                    result.finalTranscript,
                    mode: behavior.formattingMode.instantRefineMode,
                    languageCode: behavior.languageProfile.inputLanguageCode,

                    voiceCommandsEnabled: behavior.voiceCommandsEnabled
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
            Task { try? await dictationVault?.discard(id: historyID) }
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
                try? await dictationVault?.markFailed(
                    id: historyID,
                    message: message,
                    retainAudio: historyPreferences.retainsFailedAudio
                )
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
              let segment = recorder.stableSegment(
                after: liveCommittedSampleIndex
              ) else {
            return
        }
        let previewEngine = engineRegistry?.resolvePreview(
            for: activeDictationBehavior.languageProfile
        )
        guard previewEngine != nil || whisperEngine != nil else {
            return
        }

        livePreviewInFlight = true
        let sessionID = liveSessionID
        let behavior = activeDictationBehavior
        let correctionVault = dictationVault
        let appliesCorrectionRules =
            learningPreferences.appliesCorrectionRules
        let whisper = whisperEngine
        livePreviewTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.transcribePreview(
                    engine: previewEngine,
                    whisperFallback: whisper,
                    samples: segment.samples,
                    languageProfile: behavior.languageProfile,
                    initialPrompt: behavior.context
                )
                let refinement = TranscriptRefinement.refine(
                    result.finalTranscript,
                    mode: behavior.formattingMode.instantRefineMode,
                    languageCode: behavior.languageProfile.inputLanguageCode,
                    voiceCommandsEnabled: behavior.voiceCommandsEnabled
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
                    self.acceptStablePhrase(
                        processed,
                        endSampleIndex: segment.endSampleIndex,
                        sessionID: sessionID
                    )
                }
            } catch WhisperTranscriber.TranscriptionError.noSpeech {
                await MainActor.run {
                    guard self.liveSessionID == sessionID else { return }
                    self.livePreviewTask = nil
                    self.livePreviewInFlight = false
                    self.stopLivePreviewScheduling(invalidatePending: false)
                }
            } catch {
                await MainActor.run {
                    guard self.liveSessionID == sessionID else { return }
                    self.livePreviewTask = nil
                    self.livePreviewInFlight = false
                    self.stopLivePreviewScheduling(invalidatePending: false)
                }
            }
        }
    }

    private func transcribePreview(
        engine: (any SpeechEngine)?,
        whisperFallback: WhisperSpeechEngine?,
        samples: [Float],
        languageProfile: LanguageProfile,
        initialPrompt: String?
    ) async throws -> TranscriptionResult {
        if let flash = engine as? ParakeetFlashEngine {
            return try await flash.transcribe(
                samples: samples,
                languageProfile: languageProfile,
                initialPrompt: initialPrompt
            )
        }
        if let nemotron = engine as? NemotronSpeechUltraFastEngine {
            return try await nemotron.transcribe(
                samples: samples,
                languageProfile: languageProfile,
                initialPrompt: initialPrompt
            )
        }
        let whisper = (engine as? WhisperSpeechEngine) ?? whisperFallback
        guard let whisper else {
            throw EngineError.noEngineAvailable
        }
        // Whisper preview fragments must go through the engine's async API:
        // it serializes on the engine's own queue, the same queue the final
        // whole-recording decode uses. Calling the synchronous samples API on
        // this side's transcriptionQueue could run whisper_full on the same
        // context at the same time as a final decode — whisper.cpp contexts
        // are not thread-safe, and the result is corruption or a crash that
        // looks like a flaky decoder.
        return try await whisper.enqueuePreview(
            samples: samples,
            languageProfile: languageProfile,
            initialPrompt: initialPrompt
        )
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
            let rawTranscript = liveStableRawTranscript
            let finalTranscript = liveStableFinalTranscript
            let correctionCount = liveStableCorrectionCount
            Task {
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
        let insertedSoFar = liveInsertedStableTranscript
        let previewTargetProcess = liveTargetProcessIdentifier
        resetLivePreviewSession()

        guard formattingMode == .cloud else {
            complete(
                processed: processed,
                recordedAudio: recordedAudio,
                historyID: historyID,
                insertionText: insertionText,
                hasPriorInsertion: hasPriorInsertion,
                formattingMode: formattingMode
            )
            return
        }

        // The live-preview routes never ran cloud enhancement. With Formatting
        // set to Cloud and streaming insertion on, no request was made, no
        // review panel appeared, and the "Cloud AI is off" warning never
        // fired — the user got the local transcript believing their provider
        // had rewritten it.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.processCloudEnhancement(
                localProcessed: processed,
                formattingMode: formattingMode
            )
            guard outcome.didApply, hasPriorInsertion else {
                self.complete(
                    processed: outcome.processed,
                    recordedAudio: recordedAudio,
                    historyID: historyID,
                    insertionText: outcome.didApply
                        ? outcome.processed.result.finalTranscript
                        : insertionText,
                    hasPriorInsertion: hasPriorInsertion,
                    formattingMode: formattingMode,
                    cloudDidApply: outcome.didApply
                )
                return
            }
            // Text is already on screen, so swap rather than append — and only
            // while the caret is still where it was typed. Enhancement takes
            // seconds; if the user has moved on, this would overwrite whatever
            // sits before *that* caret.
            if NSWorkspace.shared.frontmostApplication?
                .processIdentifier == previewTargetProcess {
                _ = self.inserter.replaceTextBeforeCaret(
                    insertedSoFar,
                    with: outcome.processed.result.finalTranscript + " "
                )
            }
            // Whether or not the swap landed, inserting again would give the
            // user their dictation twice. History keeps the accurate text and
            // nothing further is typed.
            self.complete(
                processed: outcome.processed,
                recordedAudio: recordedAudio,
                historyID: historyID,
                insertionText: "",
                hasPriorInsertion: true,
                formattingMode: formattingMode,
                cloudDidApply: true
            )
        }
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

    /// - Parameter cloudDidApply: whether a cloud provider actually produced
    ///   `processed.result.finalTranscript`. Only true when the request ran
    ///   *and* its result was kept, so a discarded suggestion or an unreachable
    ///   provider still gets local formatting rather than raw refined text.
    private func complete(
        processed: ProcessedTranscription,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID?,
        insertionText: String? = nil,
        hasPriorInsertion: Bool = false,
        formattingMode: TranscriptFormattingMode? = nil,
        cloudDidApply: Bool = false
    ) {
        Task {
            await completeNow(
                processed: processed,
                recordedAudio: recordedAudio,
                historyID: historyID,
                insertionText: insertionText,
                hasPriorInsertion: hasPriorInsertion,
                formattingMode: formattingMode,
                cloudDidApply: cloudDidApply
            )
        }
    }

    private func completeNow(
        processed: ProcessedTranscription,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID?,
        insertionText: String?,
        hasPriorInsertion: Bool,
        formattingMode: TranscriptFormattingMode?,
        cloudDidApply: Bool
    ) async {
        let result = processed.result
        let resolvedFormattingMode = formattingMode ?? activeDictationBehavior.formattingMode
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
                try? await vault.recordCorrectionUsage(
                    processed.correctionUsages
                )
            } catch {
                historySaveError = error
                try? await resolvedVault().markFailed(
                    id: historyID,
                    message: error.localizedDescription,
                    retainAudio: historyPreferences.retainsFailedAudio
                )
                scheduleRecoveryExpiry()
            }
        } else {
            if let historyID {
                try? await resolvedVault().discard(id: historyID)
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
        } else if resolvedFormattingMode == .cloud, cloudDidApply {
            // The provider already rewrote this text; running the local
            // enhancer over its output would re-format someone else's work.
            textToInsert = result.finalTranscript
        } else {
            // Reached for every rung below Cloud, and for Cloud when the
            // request did not happen — no key, provider unreachable, or the
            // user discarded the suggestion. Skipping the local enhancer here
            // unconditionally made the top rung produce *less* formatting than
            // the one beneath it: the text came out only `.clean`-refined
            // while the app said it had "used local formatting".
            textToInsert = await enhanceForMode(
                result.finalTranscript,
                formattingMode: resolvedFormattingMode
            )
        }

        switch state.mode {
        case .command:
            handleCommandModeTranscript(
                textToInsert,
                historyID: historyID,
                shouldPersist: shouldPersist,
                historySaveError: historySaveError
            )
            return
        case .write:
            handleWriteModeTranscript(
                textToInsert,
                recordedAudio: recordedAudio,
                historyID: historyID,
                shouldPersist: shouldPersist,
                historySaveError: historySaveError
            )
            return
        case .dictation:
            break
        }

        if textToInsert.isEmpty, hasPriorInsertion {
            if let historyID, shouldPersist, historySaveError == nil {
                try? await resolvedVault().markInsertion(
                    id: historyID,
                    outcome: .inserted
                )
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
                && !historyPreferences.isPrivateModeEnabled
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
                try? await resolvedVault().discard(id: historyID)
            }
            try? FileManager.default.removeItem(at: recordedAudio.url)
        }
        historyViewModel?.refresh()
        showError(error.localizedDescription)
    }

    private func resolvedVault() async throws -> DictationVault {
        if let dictationVault {
            return dictationVault
        }
        let policy = try RuntimeIdentity.policy()
        let vault = try await DictationVault.live(policy: policy)
        dictationVault = vault
        return vault
    }

    private func resetActiveDictationBehavior() {
        activeDictationBehavior = .global
        state.languageProfile = LanguagePreferences.load()
        dictationTargetProcessIdentifier = nil
    }

    private func activeZenIntelligenceMode() -> ZenIntelligenceMode {
        TranscriptFormattingPreferences.load().zenIntelligenceMode
    }

    private func enhanceForMode(
        _ transcript: String,
        formattingMode: TranscriptFormattingMode? = nil
    ) async -> String {
        let formattingMode = formattingMode ?? activeDictationBehavior.formattingMode
        if formattingMode == .smart {
            return await SmartFormattingEngine().format(
                transcript,
                languageCode: state.languageProfile.inputLanguageCode,
                context: settingsViewModel?.sanitizedNextDictationContext
            ).text
        }

        let mode = formattingMode.zenIntelligenceMode
        guard mode != .off else { return transcript }
        let result = ZenIntelligenceEngine().enhance(
            transcript,
            mode: mode,
            languageCode: state.languageProfile.inputLanguageCode,
            context: settingsViewModel?.sanitizedNextDictationContext
        )
        return result.wasRejected ? transcript : result.text
    }

    private func handleCommandModeTranscript(
        _ transcript: String,
        historyID: UUID?,
        shouldPersist: Bool,
        historySaveError: Error?
    ) {
        guard CommandModePreferences.isEnabled() else {
            showError("Command Mode is disabled. Enable it in settings.")
            return
        }
        let manifest = CommandModePreferences.loadManifest()
            ?? CommandModeEngine.defaultManifest
        let action = CommandModeEngine().parse(
            transcript: transcript,
            manifest: manifest
        )
        if action != .none {
            Task { [weak self] in
                do {
                    try await self?.commandExecutor.execute(action)
                    await MainActor.run {
                        self?.state.phase = .success
                        self?.scheduleIdleReset(
                            after: self?.successResetDelay ?? 1.2
                        )
                    }
                } catch {
                    await MainActor.run {
                        self?.showError(error.localizedDescription)
                    }
                }
            }
            return
        }

        guard AgenticModePreferences.isEffectivelyEnabled(),
              let agenticModeCoordinator
        else {
            showError("No command matched what you said.")
            return
        }
        state.phase = .idle
        agenticModeCoordinator.handleTranscript(transcript) { [weak self] in
            guard let self else { return }
            self.state.phase = .inserting
            self.insertText(
                transcript,
                historyID: historyID,
                shouldPersist: shouldPersist,
                historySaveError: historySaveError
            )
        }
    }

    private func handleWriteModeTranscript(
        _ transcript: String,
        recordedAudio: AudioRecorder.RecordedAudio,
        historyID: UUID?,
        shouldPersist: Bool,
        historySaveError: Error?
    ) {
        let subMode = activeWriteModeSubMode()
        switch subMode {
        case .compose:
            insertText(
                transcript,
                historyID: historyID,
                shouldPersist: shouldPersist,
                historySaveError: historySaveError
            )
        case .rewrite:
            Task { [weak self] in
                await self?.rewriteAndInsert(
                    prompt: transcript,
                    historyID: historyID,
                    shouldPersist: shouldPersist,
                    historySaveError: historySaveError
                )
            }
        }
    }

    private func activeWriteModeSubMode() -> WriteModeSubMode {
        let global = WriteModePreferences.loadSubMode()
        guard let bundleID = NSWorkspace.shared.frontmostApplication?
            .bundleIdentifier,
              let profile = ApplicationProfilePreferences.profile(
                for: bundleID
              ) else {
            return global
        }
        return profile.writeModeDefault ?? global
    }

    private func rewriteAndInsert(
        prompt: String,
        historyID: UUID?,
        shouldPersist: Bool,
        historySaveError: Error?
    ) async {
        let request = WriteModeReadRequest(
            sourceBundleIdentifier: NSWorkspace.shared.frontmostApplication?
                .bundleIdentifier,
            fallbackToClipboard: true
        )
        let readResult: WriteModeReadResult
        do {
            readResult = try await writeReader.read(request)
        } catch {
            await MainActor.run {
                showError(error.localizedDescription)
            }
            return
        }

        let mode = activeZenIntelligenceMode()
        let rewrite = WriteModeEngine().rewrite(
            selectedText: readResult.text,
            prompt: prompt,
            mode: mode,
            languageCode: state.languageProfile.inputLanguageCode
        )

        await MainActor.run { [rewrite] in
            if rewrite.wasRejected {
                showError("Rewrite was rejected to preserve meaning.")
                return
            }
            if rewrite.requiresPreview {
                // For now, copy the rewritten text to the clipboard so the
                // user can preview and paste manually. A future UI will show a
                // diff preview before applying.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    rewrite.text,
                    forType: .string
                )
                showError(
                    "Rewrite copied to clipboard — large change, please preview."
                )
                return
            }
            insertText(
                rewrite.text,
                historyID: historyID,
                shouldPersist: shouldPersist,
                historySaveError: historySaveError
            )
        }
    }

    private func insertText(
        _ text: String,
        historyID: UUID?,
        shouldPersist: Bool,
        historySaveError: Error?
    ) {
        if text.isEmpty {
            state.phase = .success
            scheduleIdleReset(after: successResetDelay)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            switch self.inserter.insert(text) {
            case .pasted:
                if let historyID, shouldPersist, historySaveError == nil {
                    Task {
                        try? await self.resolvedVault().markInsertion(
                            id: historyID,
                            outcome: .inserted
                        )
                    }
                }
                self.state.phase = .success
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
                return
            case .blockedBySecureInput:
                if let historyID, shouldPersist, historySaveError == nil {
                    Task {
                        try? await self.resolvedVault().markInsertion(
                            id: historyID,
                            outcome: .copiedOnly
                        )
                    }
                }
                self.showError("Copied—\(self.secureInputAdvice())")
                return
            }
            self.historyViewModel?.refresh()
            self.insightsViewModel?.refresh()
            self.voiceProfileViewModel?.refresh()
            self.scheduleIdleReset(after: self.successResetDelay)
            if let historySaveError {
                self.showError(
                    "Inserted, but history was not saved: "
                    + historySaveError.localizedDescription
                )
            }
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
            Task { @MainActor in
                do {
                    try await dictationVault?.suppressPersistence(
                        id: activeHistoryID
                    )
                } catch {
                    showError(
                        "Private Dictation could not update local history: "
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
                        "Private Dictation could not update local history: "
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
        guard let registry = engineRegistry else {
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
        let applicationProfile = ApplicationProfilePreferences.profile(
            for: record.targetBundleID
        )
        let formattingMode = applicationProfile?.formattingMode
            ?? TranscriptFormattingPreferences.load()
        let voiceCommandsEnabled =
            applicationProfile?.voiceCommandsEnabled
            ?? LocalVoiceCommandPreferences.isEnabled()
        Task { [weak self] in
            do {
                let result = try await registry.transcribe(
                    audioURL: audioURL,
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
                        voiceCommandsEnabled: voiceCommandsEnabled
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
              historyPreferences.isHistoryEnabled,
              !historyPreferences.isPrivateModeEnabled else {
            try? await resolvedVault().discard(id: historyID)
            try? FileManager.default.removeItem(at: recordedAudio.url)
            showError("Private Dictation was enabled; this retry was not saved.")
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
        case .listening, .transcribing, .awaitingCloudReview, .inserting,
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

    /// Menu-bar toggle for the live-preview overlay. Saving the preference
    /// posts the change notification, which rebuilds the overlay panel.
    @objc private func toggleLivePreviewOverlay() {
        let enabled = !OverlayPreferences.loadLivePreviewEnabled()
        OverlayPreferences.saveLivePreviewEnabled(enabled)
        livePreviewMenuItem?.state = enabled ? .on : .off
        settingsViewModel?.syncOverlayPreferences()
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
        guard !zenBarController.matches(
            kind: resolvedOverlayKind(),
            reduceMotion: OverlayPreferences.loadReduceMotion()
        ) else {
            return
        }
        zenBarController.hide()
        makeOverlayController()
        updateZenBarPresentation(
            phase: state.phase,
            showsAtAllTimes: state.showsZenVoiceAtAllTimes
        )
    }

    /// The overlay to present: the user's selection when live previews are
    /// enabled, otherwise ZenBar.
    private func resolvedOverlayKind() -> OverlayKind {
        guard OverlayPreferences.loadLivePreviewEnabled() else {
            return .zenBar
        }
        return OverlayPreferences.loadActiveOverlay()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
