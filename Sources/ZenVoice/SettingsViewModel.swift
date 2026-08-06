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
import ApplicationServices
import AVFoundation
import Combine
import Foundation
import ZenVoiceCore

@MainActor
final class SettingsViewModel: ObservableObject {
    enum ShortcutTarget {
        case dictation
        case pasteLast
        case privateMode
    }

    enum PermissionStatus: Equatable {
        case allowed
        case needsAccess
        case restricted

        var title: String {
            switch self {
            case .allowed:
                return "Allowed"
            case .needsAccess:
                return "Needs access"
            case .restricted:
                return "Restricted"
            }
        }
    }

    enum AudioDoctorState: Equatable {
        case idle
        case running
        case paused
        case analyzing
        case passed
        case quiet
        case failed(String)

        var title: String {
            switch self {
            case .idle:
                return "Ready to test"
            case .running:
                return "Listening…"
            case .paused:
                return "Check paused"
            case .analyzing:
                return "Checking signal and format…"
            case .passed:
                return "Microphone sounds good"
            case .quiet:
                return "Signal is very quiet"
            case .failed(let message):
                return message
            }
        }
    }

    @Published private(set) var currentShortcut: HotKeyConfiguration
    @Published private(set) var pasteLastShortcut: HotKeyConfiguration
    @Published private(set) var privateModeShortcut: HotKeyConfiguration
    @Published private(set) var holdToDictateEnabled: Bool
    @Published private(set) var holdKey: HoldKeyChoice
    @Published private(set) var isCapturingHoldKey = false
    @Published private(set) var showsZenVoiceAtAllTimes: Bool
    @Published private(set) var shortcutTarget: ShortcutTarget?
    @Published var shortcutError: String?
    @Published private(set) var microphoneStatus: PermissionStatus = .needsAccess
    @Published private(set) var accessibilityStatus: PermissionStatus = .needsAccess
    @Published private(set) var isLocalModelReady = false
    @Published private(set) var instantRefineMode: InstantRefineMode
    @Published private(set) var languageProfile: LanguageProfile
    @Published var languageError: String?
    @Published private(set) var microphones: [MicrophoneDevice] = []
    @Published private(set) var selectedMicrophoneUID: String?
    @Published private(set) var audioDoctorState: AudioDoctorState = .idle
    @Published private(set) var audioDoctorLevel = 0.0
    @Published private(set) var audioDoctorSamples =
        Array(repeating: 0.0, count: 32)
    @Published private(set) var audioDoctorRemainingSeconds = 3.0
    @Published private(set) var livePreviewEnabled: Bool
    @Published private(set) var commitOnPauseEnabled: Bool
    @Published private(set) var voiceCommandsEnabled: Bool
    @Published private(set) var zenIntelligenceMode: ZenIntelligenceMode
    @Published private(set) var commandModeEnabled: Bool
    @Published private(set) var commandModeManifest: CommandManifest
    @Published private(set) var writeModeSubMode: WriteModeSubMode
    @Published private(set) var writeModeDefaultPrompt: String
    @Published private(set) var activeOverlayKind: OverlayKind
    @Published private(set) var livePreviewOverlayEnabled: Bool
    @Published private(set) var overlayReduceMotion: Bool
    @Published var nextDictationContext = ""

    private let applyShortcut:
        (HotKeyConfiguration) -> Result<Void, Error>
    private let applyPasteLastShortcut:
        (HotKeyConfiguration) -> Result<Void, Error>
    private let applyPrivateModeShortcut:
        (HotKeyConfiguration) -> Result<Void, Error>
    private let applyHoldToDictate: (Bool, HoldKeyChoice) -> Void
    private let applyZenBarPreference: (Bool) -> Void
    private let applyLanguageProfile:
        (LanguageProfile) -> Result<Void, Error>
    private let canRunAudioDoctor: () -> Bool
    private let audioDoctorRecorder = AudioRecorder()
    private var audioDoctorTask: Task<Void, Never>?
    private var microphoneObserverTokens: [NSObjectProtocol] = []
    private var eventMonitor: Any?

    init(
        currentShortcut: HotKeyConfiguration,
        pasteLastShortcut: HotKeyConfiguration,
        privateModeShortcut: HotKeyConfiguration,
        holdToDictateEnabled: Bool,
        holdKey: HoldKeyChoice,
        showsZenVoiceAtAllTimes: Bool,
        applyShortcut: @escaping
            (HotKeyConfiguration) -> Result<Void, Error>,
        applyPasteLastShortcut: @escaping
            (HotKeyConfiguration) -> Result<Void, Error>,
        applyPrivateModeShortcut: @escaping
            (HotKeyConfiguration) -> Result<Void, Error>,
        applyHoldToDictate: @escaping (Bool, HoldKeyChoice) -> Void,
        applyZenBarPreference: @escaping (Bool) -> Void,
        applyLanguageProfile: @escaping
            (LanguageProfile) -> Result<Void, Error>,
        canRunAudioDoctor: @escaping () -> Bool
    ) {
        self.currentShortcut = currentShortcut
        self.pasteLastShortcut = pasteLastShortcut
        self.privateModeShortcut = privateModeShortcut
        self.holdToDictateEnabled = holdToDictateEnabled
        self.holdKey = holdKey
        self.showsZenVoiceAtAllTimes = showsZenVoiceAtAllTimes
        self.applyShortcut = applyShortcut
        self.applyPasteLastShortcut = applyPasteLastShortcut
        self.applyPrivateModeShortcut = applyPrivateModeShortcut
        self.applyHoldToDictate = applyHoldToDictate
        self.applyZenBarPreference = applyZenBarPreference
        self.applyLanguageProfile = applyLanguageProfile
        self.canRunAudioDoctor = canRunAudioDoctor
        instantRefineMode = InstantRefinePreferences.load()
        languageProfile = LanguagePreferences.load()
        livePreviewEnabled =
            LiveDictationPreferences.isPreviewEnabled()
        commitOnPauseEnabled =
            LiveDictationPreferences.isCommitOnPauseEnabled()
        voiceCommandsEnabled =
            LocalVoiceCommandPreferences.isEnabled()
        zenIntelligenceMode = ZenIntelligencePreferences.load()
        commandModeEnabled = CommandModePreferences.isEnabled()
        commandModeManifest =
            CommandModePreferences.loadManifest()
            ?? CommandModeEngine.defaultManifest
        writeModeSubMode = WriteModePreferences.loadSubMode()
        writeModeDefaultPrompt = WriteModePreferences.defaultPrompt()
        activeOverlayKind = OverlayPreferences.loadActiveOverlay()
        livePreviewOverlayEnabled = OverlayPreferences.loadLivePreviewEnabled()
        overlayReduceMotion = OverlayPreferences.loadReduceMotion()
        selectedMicrophoneUID =
            MicrophonePreferences.selectedDeviceUID()
        refreshMicrophones()
        observeMicrophoneChanges()
        refreshSystemStatus()
    }

    var isCapturingShortcut: Bool {
        shortcutTarget == .dictation
    }

    var isCapturingPasteLastShortcut: Bool {
        shortcutTarget == .pasteLast
    }

    var isCapturingPrivateModeShortcut: Bool {
        shortcutTarget == .privateMode
    }

    var isAudioDoctorActive: Bool {
        switch audioDoctorState {
        case .running, .paused, .analyzing:
            return true
        case .idle, .passed, .quiet, .failed:
            return false
        }
    }

    deinit {
        audioDoctorTask?.cancel()
        audioDoctorRecorder.cancel()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        for token in microphoneObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func refreshSystemStatus() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = .allowed
        case .restricted:
            microphoneStatus = .restricted
        case .notDetermined, .denied:
            microphoneStatus = .needsAccess
        @unknown default:
            microphoneStatus = .needsAccess
        }

        let previousAccessibilityStatus = accessibilityStatus
        accessibilityStatus = AXIsProcessTrusted()
            ? .allowed
            : .needsAccess
        if accessibilityStatus == .allowed,
           previousAccessibilityStatus != .allowed,
           holdToDictateEnabled {
            shortcutError = nil
            applyHoldToDictate(true, holdKey)
        }
        isLocalModelReady = (try? ZenVoiceConfiguration.discover()) != nil
    }

    func beginShortcutCapture(
        for target: ShortcutTarget = .dictation
    ) {
        guard shortcutTarget == nil, !isCapturingHoldKey else {
            return
        }

        shortcutError = nil
        shortcutTarget = target
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            self?.capture(event)
            return nil
        }
    }

    func cancelShortcutCapture() {
        shortcutTarget = nil
        isCapturingHoldKey = false
        removeEventMonitor()
    }

    func beginHoldKeyCapture() {
        guard shortcutTarget == nil, !isCapturingHoldKey else {
            return
        }
        shortcutError = nil
        isCapturingHoldKey = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            self?.captureHoldKey(event)
            return event
        }
    }

    func resetShortcut() {
        apply(.dictationDefault, to: .dictation)
    }

    func resetPasteLastShortcut() {
        apply(.pasteLastDefault, to: .pasteLast)
    }

    func resetPrivateModeShortcut() {
        apply(.privateModeDefault, to: .privateMode)
    }

    func resetHoldKey() {
        cancelShortcutCapture()
        setHoldKey(.default)
    }

    func setHoldToDictateEnabled(_ enabled: Bool) {
        holdToDictateEnabled = enabled
        applyHoldToDictate(enabled, holdKey)
        if enabled, accessibilityStatus != .allowed {
            shortcutError =
                "Hold to dictate needs Accessibility permission to detect the key outside ZenVoice."
            requestAccessibilityAccess()
        } else {
            shortcutError = nil
        }
    }

    func setHoldKey(_ choice: HoldKeyChoice) {
        holdKey = choice
        applyHoldToDictate(holdToDictateEnabled, choice)
        shortcutError = nil
    }

    func setShowsZenVoiceAtAllTimes(_ enabled: Bool) {
        showsZenVoiceAtAllTimes = enabled
        applyZenBarPreference(enabled)
    }

    func setInstantRefineMode(_ mode: InstantRefineMode) {
        instantRefineMode = mode
        InstantRefinePreferences.save(mode)
    }

    func setLivePreviewEnabled(_ enabled: Bool) {
        LiveDictationPreferences.setPreviewEnabled(enabled)
        livePreviewEnabled =
            LiveDictationPreferences.isPreviewEnabled()
        commitOnPauseEnabled =
            LiveDictationPreferences.isCommitOnPauseEnabled()
    }

    func setCommitOnPauseEnabled(_ enabled: Bool) {
        LiveDictationPreferences.setCommitOnPauseEnabled(enabled)
        livePreviewEnabled =
            LiveDictationPreferences.isPreviewEnabled()
        commitOnPauseEnabled =
            LiveDictationPreferences.isCommitOnPauseEnabled()
    }

    var sanitizedNextDictationContext: String {
        NextDictationContext.sanitized(nextDictationContext)
    }

    func clearNextDictationContext() {
        nextDictationContext = ""
    }

    func setVoiceCommandsEnabled(_ enabled: Bool) {
        LocalVoiceCommandPreferences.setEnabled(enabled)
        voiceCommandsEnabled = enabled
    }

    func setZenIntelligenceMode(_ mode: ZenIntelligenceMode) {
        ZenIntelligencePreferences.save(mode)
        zenIntelligenceMode = mode
    }

    func setCommandModeEnabled(_ enabled: Bool) {
        CommandModePreferences.setEnabled(enabled)
        commandModeEnabled = enabled
    }

    func setCommandModeManifest(_ manifest: CommandManifest) {
        CommandModePreferences.saveManifest(manifest)
        commandModeManifest = manifest
    }

    func resetCommandModeManifest() {
        CommandModePreferences.clearManifest()
        commandModeManifest = CommandModeEngine.defaultManifest
    }

    func setWriteModeSubMode(_ mode: WriteModeSubMode) {
        WriteModePreferences.saveSubMode(mode)
        writeModeSubMode = mode
    }

    func setWriteModeDefaultPrompt(_ prompt: String) {
        let trimmed = NextDictationContext.sanitized(prompt)
        WriteModePreferences.saveDefaultPrompt(trimmed)
        writeModeDefaultPrompt = trimmed
    }

    func setActiveOverlayKind(_ kind: OverlayKind) {
        OverlayPreferences.saveActiveOverlay(kind)
        activeOverlayKind = kind
    }

    func setLivePreviewOverlayEnabled(_ enabled: Bool) {
        OverlayPreferences.saveLivePreviewEnabled(enabled)
        livePreviewOverlayEnabled = enabled
    }

    func setOverlayReduceMotion(_ reduce: Bool) {
        OverlayPreferences.saveReduceMotion(reduce)
        overlayReduceMotion = reduce
    }

    /// Reloads overlay preferences from storage.
    ///
    /// The menu bar can toggle the live-preview overlay while the settings
    /// window is open; this keeps the Overlay screen in step with it.
    func syncOverlayPreferences() {
        activeOverlayKind = OverlayPreferences.loadActiveOverlay()
        livePreviewOverlayEnabled = OverlayPreferences.loadLivePreviewEnabled()
        overlayReduceMotion = OverlayPreferences.loadReduceMotion()
    }

    func setInputLanguage(_ code: String) {
        setLanguageProfile(
            LanguageProfile(
                inputLanguageCode: code,
                outputMode: languageProfile.outputMode
            )
        )
    }

    func setOutputMode(_ mode: TranscriptionOutputMode) {
        setLanguageProfile(
            LanguageProfile(
                inputLanguageCode: languageProfile.inputLanguageCode,
                outputMode: mode
            )
        )
    }

    func useEnglishProfile() {
        setLanguageProfile(.english)
    }

    func useHinglishProfile() {
        setLanguageProfile(.hinglish)
    }

    func useAutomaticProfile() {
        setLanguageProfile(
            LanguageProfile(
                inputLanguageCode: LanguageProfile.automaticCode,
                outputMode: .spokenLanguage
            )
        )
    }

    func configurationDidChange(
        languageProfile: LanguageProfile
    ) {
        self.languageProfile = languageProfile
        languageError = nil
        refreshSystemStatus()
    }

    var selectedMicrophoneName: String {
        guard let selectedMicrophoneUID else {
            return microphones.first(where: \.isDefault)?.name
                ?? "System Default"
        }
        return microphones.first {
            $0.id == selectedMicrophoneUID
        }?.name ?? "Disconnected microphone"
    }

    func selectMicrophone(_ uid: String?) {
        guard !isAudioDoctorActive else {
            return
        }
        selectedMicrophoneUID = uid
        MicrophonePreferences.save(deviceUID: uid)
        audioDoctorState = .idle
        audioDoctorLevel = 0
        audioDoctorSamples = Array(
            repeating: 0,
            count: audioDoctorSamples.count
        )
        audioDoctorRemainingSeconds = 3
    }

    func refreshMicrophones() {
        microphones = MicrophoneCatalog.devices()
    }

    func runAudioDoctor() {
        guard !isAudioDoctorActive else {
            return
        }
        guard microphoneStatus == .allowed else {
            audioDoctorState = .failed(
                "Allow microphone access before running the test."
            )
            return
        }
        guard canRunAudioDoctor() else {
            audioDoctorState = .failed(
                "Finish the current dictation before testing the microphone."
            )
            return
        }
        if let selectedMicrophoneUID,
           microphones.contains(
            where: {
                $0.id == selectedMicrophoneUID && $0.isConnected
            }
           ) == false {
            audioDoctorState = .failed(
                "The selected microphone is not connected."
            )
            return
        }

        audioDoctorLevel = 0
        audioDoctorSamples = Array(
            repeating: 0,
            count: audioDoctorSamples.count
        )
        audioDoctorRemainingSeconds = 3
        audioDoctorState = .running
        do {
            try audioDoctorRecorder.start(
                selectedDeviceUID: selectedMicrophoneUID
            ) { [weak self] level in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.audioDoctorLevel = max(
                        self.audioDoctorLevel,
                        level
                    )
                    var samples = self.audioDoctorSamples
                    samples.removeFirst()
                    samples.append(max(0, min(1, level)))
                    self.audioDoctorSamples = samples
                }
            }
        } catch {
            audioDoctorState = .failed(error.localizedDescription)
            return
        }

        startAudioDoctorCountdown()
    }

    func toggleAudioDoctorPause() {
        switch audioDoctorState {
        case .running:
            audioDoctorTask?.cancel()
            audioDoctorTask = nil
            audioDoctorRecorder.pause()
            audioDoctorState = .paused
        case .paused:
            do {
                try audioDoctorRecorder.resume()
                audioDoctorState = .running
                startAudioDoctorCountdown()
            } catch {
                audioDoctorRecorder.cancel()
                audioDoctorState = .failed(error.localizedDescription)
            }
        case .idle, .analyzing, .passed, .quiet, .failed:
            break
        }
    }

    private func startAudioDoctorCountdown() {
        audioDoctorTask?.cancel()
        let startingRemaining = audioDoctorRemainingSeconds
        let startedAt = Date()
        audioDoctorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, audioDoctorState == .running else {
                    return
                }
                let elapsed = Date().timeIntervalSince(startedAt)
                audioDoctorRemainingSeconds = max(
                    0,
                    startingRemaining - elapsed
                )
                if audioDoctorRemainingSeconds == 0 {
                    await finishAudioDoctor()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func finishAudioDoctor() async {
        audioDoctorState = .analyzing
        let recordedAudio = audioDoctorRecorder.stop()

        // Capture and validation remain visibly separate phases.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else {
            return
        }
        guard let url = recordedAudio?.url else {
            audioDoctorState = .failed(
                "The microphone test did not capture audio."
            )
            audioDoctorTask = nil
            return
        }
        defer {
            try? FileManager.default.removeItem(at: url)
        }
        let testFile = try? AVAudioFile(forReading: url)
        let hasValidLocalFormat =
            testFile?.processingFormat.sampleRate == 16_000
            && testFile?.processingFormat.channelCount == 1
            && (testFile?.length ?? 0) > 0
        guard hasValidLocalFormat else {
            audioDoctorState = .failed(
                "The microphone signal could not be prepared for local transcription."
            )
            audioDoctorTask = nil
            return
        }
        audioDoctorState =
            audioDoctorLevel >= 0.08 ? .passed : .quiet
        audioDoctorTask = nil
    }

    func requestMicrophoneAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshSystemStatus()
                }
            }
        case .denied:
            openSystemSettings(
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            )
        default:
            refreshSystemStatus()
        }
    }

    func requestAccessibilityAccess() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshSystemStatus()
        }
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 {
            cancelShortcutCapture()
            return
        }

        let modifiers = hotKeyModifiers(from: event.modifierFlags)
        guard !modifiers.isEmpty else {
            shortcutError = "Include Command, Control, Option, or Shift."
            cancelShortcutCapture()
            return
        }

        guard let keyLabel = HotKeyConfiguration.canonicalLabel(
            forKeyCode: UInt32(event.keyCode)
        ) else {
            shortcutError = "That key is not supported. Try another combination."
            cancelShortcutCapture()
            return
        }

        let configuration = HotKeyConfiguration(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            keyLabel: keyLabel
        )
        guard let shortcutTarget else {
            return
        }
        apply(configuration, to: shortcutTarget)
    }

    private func captureHoldKey(_ event: NSEvent) {
        guard let choice = HoldKeyChoice(keyCode: event.keyCode) else {
            shortcutError =
                "Use Fn or a left/right Command, Option, Control, or Shift key."
            cancelShortcutCapture()
            return
        }
        cancelShortcutCapture()
        setHoldKey(choice)
    }

    private func apply(
        _ configuration: HotKeyConfiguration,
        to target: ShortcutTarget
    ) {
        cancelShortcutCapture()
        let result: Result<Void, Error>
        switch target {
        case .dictation:
            result = applyShortcut(configuration)
        case .pasteLast:
            result = applyPasteLastShortcut(configuration)
        case .privateMode:
            result = applyPrivateModeShortcut(configuration)
        }

        switch result {
        case .success:
            switch target {
            case .dictation:
                currentShortcut = configuration
            case .pasteLast:
                pasteLastShortcut = configuration
            case .privateMode:
                privateModeShortcut = configuration
            }
            shortcutError = nil
        case .failure(let error):
            shortcutError = error.localizedDescription
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func setLanguageProfile(_ profile: LanguageProfile) {
        switch applyLanguageProfile(profile) {
        case .success:
            languageProfile = profile
            languageError = nil
            refreshSystemStatus()
        case .failure(let error):
            languageError = error.localizedDescription
        }
    }

    private func observeMicrophoneChanges() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            AVCaptureDevice.wasConnectedNotification,
            AVCaptureDevice.wasDisconnectedNotification
        ]
        microphoneObserverTokens = names.map { name in
            center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshMicrophones()
                }
            }
        }
    }

    private func hotKeyModifiers(
        from flags: NSEvent.ModifierFlags
    ) -> HotKeyModifiers {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: HotKeyModifiers = []
        if flags.contains(.command) {
            result.insert(.command)
        }
        if flags.contains(.control) {
            result.insert(.control)
        }
        if flags.contains(.option) {
            result.insert(.option)
        }
        if flags.contains(.shift) {
            result.insert(.shift)
        }
        return result
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
