import AVFoundation
import CoreAudio
import Foundation

// 1. What ZenVoice's current catalogue sees.
let avDevices = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.microphone, .external],
    mediaType: .audio,
    position: .unspecified
).devices

print("== AVCaptureDevice discovery ==")
for device in avDevices {
    print("  \(device.localizedName)  uid=\(device.uniqueID)  connected=\(device.isConnected)")
}
print("  (\(avDevices.count) device(s))")

// 2. What CoreAudio reports as an input device.
func property<T>(
    _ objectID: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    default fallback: T
) -> T {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(MemoryLayout<T>.size)
    var value = fallback
    let status = AudioObjectGetPropertyData(
        objectID, &address, 0, nil, &size, &value
    )
    return status == noErr ? value : fallback
}

func inputChannelCount(_ deviceID: AudioDeviceID) -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
          size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(
        byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr else {
        return 0
    }
    let list = UnsafeMutableAudioBufferListPointer(
        raw.assumingMemoryBound(to: AudioBufferList.self)
    )
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(
    AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
)
var deviceIDs = [AudioDeviceID](
    repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size
)
AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs
)

print("\n== CoreAudio input devices ==")
for deviceID in deviceIDs {
    let channels = inputChannelCount(deviceID)
    guard channels > 0 else { continue }
    let uid = property(
        deviceID, kAudioDevicePropertyDeviceUID, default: "" as CFString
    ) as String
    let name = property(
        deviceID, kAudioObjectPropertyName, default: "" as CFString
    ) as String
    let transport = property(
        deviceID, kAudioDevicePropertyTransportType,
        default: UInt32(0)
    )
    let transportName: String
    switch transport {
    case kAudioDeviceTransportTypeBuiltIn: transportName = "built-in"
    case kAudioDeviceTransportTypeUSB: transportName = "usb"
    case kAudioDeviceTransportTypeBluetooth: transportName = "bluetooth"
    case kAudioDeviceTransportTypeAggregate: transportName = "aggregate"
    case kAudioDeviceTransportTypeVirtual: transportName = "virtual"
    case kAudioDeviceTransportTypeContinuityCaptureWired,
         kAudioDeviceTransportTypeContinuityCapture: transportName = "continuity"
    default: transportName = "other(\(transport))"
    }
    let seenByAV = avDevices.contains { $0.uniqueID == uid }
    print("  \(name)  uid=\(uid)  ch=\(channels)  transport=\(transportName)  inAVCatalogue=\(seenByAV)")
}
