import AVFoundation
import Foundation

final class AudioRecorder {
    enum RecorderError: LocalizedError {
        case unableToCreateRecorder
        case unableToStart

        var errorDescription: String? {
            switch self {
            case .unableToCreateRecorder:
                return "ZenVoice could not open the microphone."
            case .unableToStart:
                return "ZenVoice could not start recording."
            }
        }
    }

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var recordingURL: URL?

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    func start(levelChanged: @escaping (Double) -> Void) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zenvoice-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else {
            throw RecorderError.unableToCreateRecorder
        }

        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw RecorderError.unableToStart
        }

        self.recorder = recorder
        recordingURL = url
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak recorder] _ in
            guard let recorder else { return }
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let normalized = max(0, min(1, (Double(power) + 55) / 55))
            levelChanged(normalized)
        }
    }

    func stop() -> URL? {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        defer { recordingURL = nil }
        return recordingURL
    }

    func cancel() {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        recordingURL = nil
    }
}
