import Carbon
import Foundation
import ZenVoiceCore

final class GlobalHotKey {
    enum HotKeyError: LocalizedError {
        case registrationFailed(String)

        var errorDescription: String? {
            switch self {
            case .registrationFailed(let shortcut):
                return "\(shortcut) is unavailable. Choose another shortcut."
            }
        }
    }

    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private let action: () -> Void

    init(
        configuration: HotKeyConfiguration,
        action: @escaping () -> Void
    ) throws {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                let hotKey = Unmanaged<GlobalHotKey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    hotKey.action()
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandlerReference
        )

        guard handlerStatus == noErr else {
            throw HotKeyError.registrationFailed(configuration.displayName)
        }

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x5A564F49),
            id: UInt32.random(in: 1...UInt32.max)
        )
        let modifiers = Self.carbonModifiers(for: configuration.modifiers)
        let registrationStatus = RegisterEventHotKey(
            configuration.keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyReference
        )

        guard registrationStatus == noErr else {
            if let eventHandlerReference {
                RemoveEventHandler(eventHandlerReference)
            }
            throw HotKeyError.registrationFailed(configuration.displayName)
        }
    }

    private static func carbonModifiers(
        for modifiers: HotKeyModifiers
    ) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) {
            result |= UInt32(cmdKey)
        }
        if modifiers.contains(.control) {
            result |= UInt32(controlKey)
        }
        if modifiers.contains(.option) {
            result |= UInt32(optionKey)
        }
        if modifiers.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        return result
    }

    deinit {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
    }
}
