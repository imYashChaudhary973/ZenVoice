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
        case passed
        case quiet
        case failed(String)

        var title: String {
            switch self {
            case .idle:
                return "Ready to test"
            case .running:
                return "Listening…"
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
    @Published private(set) var livePreviewEnabled: Bool
    @Published private(set) var commitOnPauseEnabled: Bool
    @Published private(set) var voiceCommandsEnabled: Bool
    @Published var nextDictationContext = ""

    private let applyShortcut:
        (HotKeyConfiguration) -> Result<Void, Error>
    private let applyPasteLastShortcut:
        (HotKeyConfiguration) -> Result<Void, Error>
    private let applyPrivateModeShortcut:
        (HotKeyConfiguration) -> Result<Void, Error>
    private let applyHoldToDictate: (Bool, HoldKeyChoice) -> Void
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
        applyShortcut: @escaping
            (HotKeyConfiguration) -> Result<Void, Error>,
        applyPasteLastShortcut: @escaping
            (HotKeyConfiguration) -> Result<Void, Error>,
        applyPrivateModeShortcut: @escaping
            (HotKeyConfiguration) -> Result<Void, Error>,
        applyHoldToDictate: @escaping (Bool, HoldKeyChoice) -> Void,
        applyLanguageProfile: @escaping
            (LanguageProfile) -> Result<Void, Error>,
        canRunAudioDoctor: @escaping () -> Bool
    ) {
        self.currentShortcut = currentShortcut
        self.pasteLastShortcut = pasteLastShortcut
        self.privateModeShortcut = privateModeShortcut
        self.holdToDictateEnabled = holdToDictateEnabled
        self.holdKey = holdKey
        self.applyShortcut = applyShortcut
        self.applyPasteLastShortcut = applyPasteLastShortcut
        self.applyPrivateModeShortcut = applyPrivateModeShortcut
        self.applyHoldToDictate = applyHoldToDictate
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

        accessibilityStatus = AXIsProcessTrusted()
            ? .allowed
            : .needsAccess
        isLocalModelReady = (try? ZenVoiceConfiguration.discover()) != nil
    }

    func beginShortcutCapture(
        for target: ShortcutTarget = .dictation
    ) {
        guard shortcutTarget == nil else {
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
        removeEventMonitor()
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

    func setHoldToDictateEnabled(_ enabled: Bool) {
        holdToDictateEnabled = enabled
        applyHoldToDictate(enabled, holdKey)
    }

    func setHoldKey(_ choice: HoldKeyChoice) {
        holdKey = choice
        applyHoldToDictate(holdToDictateEnabled, choice)
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
        guard audioDoctorState != .running else {
            return
        }
        selectedMicrophoneUID = uid
        MicrophonePreferences.save(deviceUID: uid)
        audioDoctorState = .idle
        audioDoctorLevel = 0
    }

    func refreshMicrophones() {
        microphones = MicrophoneCatalog.devices()
    }

    func runAudioDoctor() {
        guard audioDoctorState != .running else {
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
        audioDoctorState = .running
        do {
            try audioDoctorRecorder.start(
                selectedDeviceUID: selectedMicrophoneUID
            ) { [weak self] level in
                DispatchQueue.main.async {
                    self?.audioDoctorLevel = max(
                        self?.audioDoctorLevel ?? 0,
                        level
                    )
                }
            }
        } catch {
            audioDoctorState = .failed(error.localizedDescription)
            return
        }

        audioDoctorTask?.cancel()
        audioDoctorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else {
                return
            }
            let recordedAudio = audioDoctorRecorder.stop()
            guard let url = recordedAudio?.url else {
                audioDoctorState = .failed(
                    "The microphone test did not capture audio."
                )
                audioDoctorTask = nil
                return
            }
            let testFile = try? AVAudioFile(forReading: url)
            let hasValidLocalFormat =
                testFile?.processingFormat.sampleRate == 16_000
                && testFile?.processingFormat.channelCount == 1
                && (testFile?.length ?? 0) > 0
            try? FileManager.default.removeItem(at: url)
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
