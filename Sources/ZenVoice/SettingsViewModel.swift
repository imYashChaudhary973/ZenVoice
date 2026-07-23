import AppKit
import ApplicationServices
import AVFoundation
import Combine
import Foundation
import ZenVoiceCore

@MainActor
final class SettingsViewModel: ObservableObject {
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
    @Published private(set) var isCapturingShortcut = false
    @Published var shortcutError: String?
    @Published private(set) var microphoneStatus: PermissionStatus = .needsAccess
    @Published private(set) var accessibilityStatus: PermissionStatus = .needsAccess
    @Published private(set) var isLocalModelReady = false

    private let applyShortcut:
        (HotKeyConfiguration) -> Result<Void, Error>
    private var eventMonitor: Any?

    init(
        currentShortcut: HotKeyConfiguration,
        applyShortcut: @escaping
            (HotKeyConfiguration) -> Result<Void, Error>
    ) {
        self.currentShortcut = currentShortcut
        self.applyShortcut = applyShortcut
        refreshSystemStatus()
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

    func beginShortcutCapture() {
        guard !isCapturingShortcut else {
            return
        }

        shortcutError = nil
        isCapturingShortcut = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            self?.capture(event)
            return nil
        }
    }

    func cancelShortcutCapture() {
        isCapturingShortcut = false
        removeEventMonitor()
    }

    func resetShortcut() {
        apply(.dictationDefault)
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

        guard let keyLabel = keyLabel(for: event) else {
            shortcutError = "That key is not supported. Try another combination."
            cancelShortcutCapture()
            return
        }

        let configuration = HotKeyConfiguration(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            keyLabel: keyLabel
        )
        apply(configuration)
    }

    private func apply(_ configuration: HotKeyConfiguration) {
        cancelShortcutCapture()
        switch applyShortcut(configuration) {
        case .success:
            currentShortcut = configuration
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

    private func keyLabel(for event: NSEvent) -> String? {
        let specialKeys: [UInt16: String] = [
            36: "Return",
            48: "Tab",
            49: "Space",
            51: "Delete",
            53: "Escape",
            71: "Clear",
            76: "Enter",
            115: "Home",
            116: "Page Up",
            117: "Forward Delete",
            119: "End",
            121: "Page Down",
            123: "←",
            124: "→",
            125: "↓",
            126: "↑",
            122: "F1",
            120: "F2",
            99: "F3",
            118: "F4",
            96: "F5",
            97: "F6",
            98: "F7",
            100: "F8",
            101: "F9",
            109: "F10",
            103: "F11",
            111: "F12"
        ]

        if let specialKey = specialKeys[event.keyCode] {
            return specialKey
        }

        guard let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !characters.isEmpty else {
            return nil
        }
        return characters.uppercased()
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
