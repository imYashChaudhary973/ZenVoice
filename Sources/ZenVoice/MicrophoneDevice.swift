import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import ZenVoiceCore

struct MicrophoneDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let isDefault: Bool
    let isConnected: Bool
    let isInUseByAnotherApplication: Bool
}

enum MicrophoneCatalog {
    enum CatalogError: LocalizedError {
        case deviceUnavailable
        case deviceLookupFailed

        var errorDescription: String? {
            switch self {
            case .deviceUnavailable:
                return "The selected microphone is not connected."
            case .deviceLookupFailed:
                return "ZenVoice could not open the selected microphone."
            }
        }
    }

    static func devices() -> [MicrophoneDevice] {
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        .devices
        .filter {
            !$0.localizedName.hasPrefix("CADefaultDeviceAggregate-")
        }
        .map {
            MicrophoneDevice(
                id: $0.uniqueID,
                name: $0.localizedName,
                isDefault: $0.uniqueID == defaultID,
                isConnected: $0.isConnected,
                isInUseByAnotherApplication:
                    $0.isInUseByAnotherApplication
            )
        }
        .sorted {
            if $0.isDefault != $1.isDefault {
                return $0.isDefault
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name)
                == .orderedAscending
        }
    }

    static func device(uid: String) -> MicrophoneDevice? {
        devices().first { $0.id == uid }
    }

    static func audioDeviceID(uid: String) throws -> AudioDeviceID {
        guard device(uid: uid)?.isConnected == true else {
            throw CatalogError.deviceUnavailable
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var uidReference: CFString = uid as CFString
        let status = withUnsafePointer(to: &uidReference) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                qualifier,
                &dataSize,
                &deviceID
            )
        }
        guard status == noErr,
              deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            throw CatalogError.deviceLookupFailed
        }
        return deviceID
    }
}
