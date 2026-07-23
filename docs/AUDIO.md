# Microphones and Audio Doctor

ZenVoice can follow the current macOS input or stay pinned to one connected
microphone. The choice is stored locally as the device identifier; no audio or
device inventory is sent anywhere.

## Input choices

- **System Default** follows macOS when the default input changes.
- **Pinned microphone** keeps using the chosen connected device until the user
  selects another input or returns to System Default.

ZenVoice records through `AVAudioEngine`, routes the engine to the selected
Core Audio device, and converts the captured signal to 16 kHz mono floating
point PCM for the local Whisper runtime.

## Audio Doctor

Audio Doctor runs an explicit three-second local test. It checks that:

1. Microphone permission is available.
2. The selected device is still connected.
3. ZenVoice can start the selected input.
4. The microphone produces a measurable signal.
5. The result is a nonempty 16 kHz mono file accepted by the local runtime.

The temporary test file is deleted immediately after validation. The test does
not create a History record and does not send audio over the network.

## Disconnection behavior

When the active device disconnects during dictation, ZenVoice stops the
recording instead of silently switching microphones. If failed-audio recovery
is enabled, the partial recording follows the existing encrypted recovery
policy and expires within 24 hours. Otherwise it is removed. The user can
reconnect the device, select another input, or return to System Default.

The device-connect and device-disconnect lifecycle uses AVFoundation's capture
device notifications:

- [Device disconnected](https://developer.apple.com/documentation/avfoundation/avcapturedevice/wasdisconnectednotification)
- [Device connected](https://developer.apple.com/documentation/avfoundation/avcapturedevice/wasconnectednotification)

## Manual QA still required

- Disconnect a pinned USB or Bluetooth microphone while recording.
- Reconnect it and confirm the Audio screen refreshes without relaunching.
- Change the macOS default input while System Default is selected.
- Test an input already used by another application.
- Confirm a quiet microphone receives the quiet-signal result.
