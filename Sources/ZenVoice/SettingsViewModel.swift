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

    private let applyShortcut:
        (HotKeyConfiguration) -> Result<Void, Error>
    private let applyPasteLastShortcut:
        (HotKeyConfiguration) -> Result<Void, Error>
    private let applyPrivateModeShortcut:
        (HotKeyConfiguration) -> Result<Void, Error>
    private let applyHoldToDictate: (Bool, HoldKeyChoice) -> Void
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
        applyHoldToDictate: @escaping (Bool, HoldKeyChoice) -> Void
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
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
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
