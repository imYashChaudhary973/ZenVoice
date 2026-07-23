import Carbon
import Foundation

final class GlobalHotKey {
    enum HotKeyError: LocalizedError {
        case registrationFailed

        var errorDescription: String? {
            "ZenVoice could not register Control + Option + Space."
        }
    }

    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) throws {
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
            throw HotKeyError.registrationFailed
        }

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x5A564F49),
            id: 1
        )
        let modifiers = UInt32(controlKey | optionKey)
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
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
            throw HotKeyError.registrationFailed
        }
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
