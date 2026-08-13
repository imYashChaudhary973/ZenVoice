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
import Carbon.HIToolbox
import CoreAudio
import Foundation
import IOKit
import os
import ZenVoiceCore

/// Concrete executor for Command Mode actions.
///
/// Built-in actions are executed directly. `appleScript`, `shellScript`, and
/// `openURL` require explicit first-run approval stored in
/// `CommandModeApprovalPreferences`.
@MainActor
final class CommandModeExecutorImpl: CommandModeExecutor {
    private let inserter: TextInserter
    private let state: AppState
    private let pasteLast: () -> Void
    private let showSettings: () -> Void
    private let logger = Logger(
        subsystem: "com.zenvoice.app",
        category: "CommandMode"
    )

    init(
        inserter: TextInserter,
        state: AppState,
        pasteLast: @escaping () -> Void,
        showSettings: @escaping () -> Void
    ) {
        self.inserter = inserter
        self.state = state
        self.pasteLast = pasteLast
        self.showSettings = showSettings
    }

    func execute(_ action: CommandAction) async throws {
        guard action != .none else { return }

        if CommandModeApprovalPreferences.requiresApproval(action),
           !CommandModeApprovalPreferences.isApproved(action) {
            throw CommandModeExecutionError.notApproved
        }

        switch action {
        case .none:
            return
        case .launchApp(let bundleID):
            try launchApp(bundleID: bundleID)
        case .runShortcut(let name):
            try runShortcut(name: name)
        case .systemAction(let systemAction):
            try executeSystemAction(systemAction)
        case .appleScript(let source):
            try runAppleScript(source)
        case .shellScript(let command):
            try runShellScript(command)
        case .openURL(let url):
            try openURL(url)
        }
    }

    // MARK: - Launch

    private func launchApp(bundleID: String) throws {
        guard !bundleID.isEmpty else {
            throw CommandModeExecutionError.missingBundleID
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            logger.warning("Could not find application URL for bundle ID: \(bundleID)")
            throw CommandModeExecutionError.missingBundleID
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration,
            completionHandler: { _, error in
                if let error {
                    self.logger.warning(
                        "Failed to open app \(bundleID): \(error.localizedDescription)"
                    )
                }
            }
        )
    }

    // MARK: - Shortcuts

    private func runShortcut(name: String) throws {
        let task = Process()
        task.launchPath = "/usr/bin/shortcuts"
        task.arguments = ["run", name]
        try runProcess(task)
    }

    // MARK: - System actions

    private func executeSystemAction(_ action: CommandModeSystemAction) throws {
        switch action {
        case .copyLastTranscript:
            copyLastTranscript()
        case .pasteLastDictation:
            pasteLast()
        case .showPreferences:
            showSettings()
        case .lockScreen:
            try lockScreen()
        case .searchSelectedText:
            try searchSelectedText()
        case .increaseVolume:
            adjustVolume(by: 0.0625)
        case .decreaseVolume:
            adjustVolume(by: -0.0625)
        case .mute:
            setMuted(true)
        case .increaseBrightness:
            adjustBrightness(by: 0.0625)
        case .decreaseBrightness:
            adjustBrightness(by: -0.0625)
        case .sleepDisplays:
            try sleepDisplays()
        }
    }

    private func copyLastTranscript() {
        guard !state.lastTranscript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            state.lastTranscript,
            forType: .string
        )
    }

    private func lockScreen() throws {
        // macOS screen-lock shortcut: Control-Command-Q.
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw CommandModeExecutionError.systemActionFailed(.lockScreen)
        }
        let keyQ = CGKeyCode(kVK_ANSI_Q)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyQ, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyQ, keyDown: false)
        let flags: CGEventFlags = [.maskCommand, .maskControl]
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func searchSelectedText() throws {
        let selected = try readSelectedText().text
        guard !selected.isEmpty else {
            throw CommandModeExecutionError.systemActionFailed(.searchSelectedText)
        }
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: selected)]
        guard let url = components?.url else {
            throw CommandModeExecutionError.scriptFailed("Invalid search query: \(selected)")
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - AppleScript / Shell / URL

    private func runAppleScript(_ source: String) throws {
        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else {
            throw CommandModeExecutionError.scriptFailed("Invalid script")
        }
        appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? "Unknown AppleScript error"
            throw CommandModeExecutionError.scriptFailed(message)
        }
    }

    private func runShellScript(_ command: String) throws {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c", command]
        try runProcess(task)
    }

    private func openURL(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw CommandModeExecutionError.scriptFailed("Failed to open URL: \(url.absoluteString)")
        }
    }

    private func runProcess(_ task: Process) throws {
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Process exited with \(task.terminationStatus)"
            throw CommandModeExecutionError.scriptFailed(message)
        }
    }

    // MARK: - Volume (CoreAudio)

    private func adjustVolume(by delta: Float32) {
        guard let deviceID = defaultOutputDeviceID() else { return }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let hasVolume = AudioObjectHasProperty(deviceID, &address)
        if hasVolume,
           AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &volume
           ) == noErr {
            volume = max(0, min(1, volume + delta))
            AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                size,
                &volume
            )
        }

        // Unmute whenever the user explicitly changes volume.
        setMuted(false)
    }

    private func setMuted(_ muted: Bool) {
        guard let deviceID = defaultOutputDeviceID() else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        )
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr else {
            return nil
        }
        return deviceID
    }

    // MARK: - Brightness (IOKit)

    private func adjustBrightness(by delta: Float) {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect")
        )
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var brightness: Float = 0
        IODisplayGetFloatParameter(
            service,
            0,
            kIODisplayBrightnessKey as CFString,
            &brightness
        )
        brightness = max(0, min(1, brightness + delta))
        IODisplaySetFloatParameter(
            service,
            0,
            kIODisplayBrightnessKey as CFString,
            brightness
        )
    }

    // MARK: - Sleep displays

    private func sleepDisplays() throws {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayWrangler")
        )
        guard service != 0 else {
            throw CommandModeExecutionError.systemActionFailed(.sleepDisplays)
        }
        defer { IOObjectRelease(service) }

        let result = IORegistryEntrySetCFProperty(
            service,
            "IORequestIdle" as CFString,
            kCFBooleanTrue
        )
        guard result == kIOReturnSuccess else {
            throw CommandModeExecutionError.systemActionFailed(.sleepDisplays)
        }
    }
}

// MARK: - Selected text reader for search

extension CommandModeExecutorImpl {
    /// Reads the currently selected text via Accessibility.
    func readSelectedText() throws -> (text: String, isVerified: Bool) {
        guard AXIsProcessTrusted() else {
            if let clipboard = NSPasteboard.general.string(forType: .string),
               !clipboard.isEmpty {
                return (clipboard, false)
            }
            throw CommandModeExecutionError.systemActionFailed(.searchSelectedText)
        }

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let rawFocused = focusedValue,
        CFGetTypeID(rawFocused) == AXUIElementGetTypeID() else {
            throw CommandModeExecutionError.systemActionFailed(.searchSelectedText)
        }
        let element = unsafeBitCast(rawFocused, to: AXUIElement.self)

        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        ) == .success,
        let selected = selectedValue as? String else {
            throw CommandModeExecutionError.systemActionFailed(.searchSelectedText)
        }
        return (selected, true)
    }
}
