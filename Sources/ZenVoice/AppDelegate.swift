import AppKit
import AVFoundation
import Foundation
import ZenVoiceCore

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureTranscriber()
        configureMenuBar()
        configureZenBar()
        configureHotKey()
        zenBarController.show()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        recorder.cancel()
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
        startStopMenuItem = NSMenuItem(
            title: "Start Dictation",
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
            globalHotKey = try GlobalHotKey { [weak self] in
                self?.toggleRecording()
            }
        } catch {
            showError(error.localizedDescription)
        }
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
        do {
            try recorder.start { [weak self] level in
                DispatchQueue.main.async {
                    self?.state.appendAudioLevel(level)
                }
            }
            state.phase = .listening
            startStopMenuItem.title = "Stop and Insert"
            if state.isZenBarVisible {
                zenBarController.show()
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func finishRecording() {
        guard let audioURL = recorder.stop(), let transcriber else {
            showError("No recording was captured.")
            return
        }

        state.phase = .transcribing
        startStopMenuItem.title = "Start Dictation"

        transcriptionQueue.async { [weak self] in
            do {
                let transcript = try transcriber.transcribe(audioURL: audioURL)
                DispatchQueue.main.async {
                    self?.complete(transcript: transcript)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showError(error.localizedDescription)
                }
            }
        }
    }

    private func cancelRecording() {
        guard recorder.isRecording else {
            return
        }

        resetWorkItem?.cancel()
        recorder.cancel()
        state.resetAudioSamples()
        state.phase = .idle
        startStopMenuItem.title = "Start Dictation"
    }

    private func complete(transcript: String) {
        state.lastTranscript = transcript
        state.phase = .inserting

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            switch self.inserter.insert(transcript) {
            case .pasted:
                self.state.phase = .success
                self.scheduleIdleReset(after: 1.5)
            case .copiedOnly:
                self.showError("Copied—enable Accessibility to auto-paste.")
            }
        }
    }

    private func showError(_ message: String) {
        state.phase = .error(message)
        startStopMenuItem?.title = "Start Dictation"
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
