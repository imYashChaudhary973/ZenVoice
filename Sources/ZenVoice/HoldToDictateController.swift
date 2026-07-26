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
        if isPressed {
            isPressed = false
            onRelease?()
        }
        self.isEnabled = isEnabled
        self.key = key
        reinstallMonitors()
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
        let pressed = isModifierPressed(in: event.modifierFlags)
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

    private func isModifierPressed(
        in flags: NSEvent.ModifierFlags
    ) -> Bool {
        let flags = flags.intersection(
            .deviceIndependentFlagsMask
        )
        switch key {
        case .function:
            return flags.contains(.function)
        case .leftCommand, .rightCommand:
            return flags.contains(.command)
        case .leftOption, .rightOption:
            return flags.contains(.option)
        case .leftControl, .rightControl:
            return flags.contains(.control)
        case .leftShift, .rightShift:
            return flags.contains(.shift)
        }
    }

    private func reinstallMonitors() {
        removeMonitors()
        installMonitors()
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
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
