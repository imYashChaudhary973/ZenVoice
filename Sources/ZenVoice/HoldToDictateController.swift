import AppKit
import ZenVoiceCore

@MainActor
final class HoldToDictateController {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var isPressed = false
    private(set) var isEnabled: Bool
    private(set) var key: HoldKeyChoice

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    init(isEnabled: Bool, key: HoldKeyChoice) {
        self.isEnabled = isEnabled
        self.key = key
        installMonitors()
    }

    func update(isEnabled: Bool, key: HoldKeyChoice) {
        if isPressed, !isEnabled || key != self.key {
            isPressed = false
            onRelease?()
        }
        self.isEnabled = isEnabled
        self.key = key
    }

    private func installMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        guard isEnabled, event.keyCode == key.keyCode else {
            return
        }
        let pressed = CGEventSource.keyState(
            .combinedSessionState,
            key: CGKeyCode(event.keyCode)
        )
        guard pressed != isPressed else {
            return
        }
        isPressed = pressed
        if pressed {
            onPress?()
        } else {
            onRelease?()
        }
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
    }
}
