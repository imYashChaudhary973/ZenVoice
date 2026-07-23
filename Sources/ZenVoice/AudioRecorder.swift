import AVFoundation
import Foundation
import ZenVoiceCore

final class AudioRecorder {
    struct RecordedAudio {
        let url: URL
        let durationSeconds: TimeInterval
    }

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
    private var recordingStartedAt: Date?
    private var audioLevelMeter = AudioLevelMeter()

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    func start(
        recordingURL requestedURL: URL? = nil,
        levelChanged: @escaping (Double) -> Void
    ) throws {
        let url = requestedURL
            ?? FileManager.default.temporaryDirectory
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
        recordingStartedAt = Date()
        audioLevelMeter = AudioLevelMeter()
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) {
            [weak self, weak recorder] _ in
            guard let self, let recorder else { return }
            recorder.updateMeters()

            let level = audioLevelMeter.update(
                averageDecibels: recorder.averagePower(forChannel: 0),
                peakDecibels: recorder.peakPower(forChannel: 0)
            )
            levelChanged(level)
        }
    }

    func stop() -> RecordedAudio? {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        defer {
            recordingURL = nil
            recordingStartedAt = nil
        }
        guard let recordingURL else {
            return nil
        }
        let duration = recordingStartedAt.map {
            max(0, Date().timeIntervalSince($0))
        } ?? 0
        return RecordedAudio(
            url: recordingURL,
            durationSeconds: duration
        )
    }

    func cancel() {
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        recordingURL = nil
        recordingStartedAt = nil
    }

}
