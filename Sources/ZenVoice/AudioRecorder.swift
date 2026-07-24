import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import ZenVoiceCore

final class AudioRecorder: NSObject,
    AVCaptureAudioDataOutputSampleBufferDelegate
{
    struct RecordedAudio {
        let url: URL
        let durationSeconds: TimeInterval
    }

    struct StableAudioSegment {
        let samples: [Float]
        let endSampleIndex: Int
    }

    enum RecorderError: LocalizedError {
        case unableToCreateRecorder
        case unableToStart
        case invalidInputFormat

        var errorDescription: String? {
            switch self {
            case .unableToCreateRecorder:
                return "ZenVoice could not open the microphone."
            case .unableToStart:
                return "ZenVoice could not start recording."
            case .invalidInputFormat:
                return "The selected microphone returned an unsupported audio format."
            }
        }
    }

    private let captureQueue = DispatchQueue(
        label: "dev.yashchaudhary.ZenVoice.audioCapture",
        qos: .userInitiated
    )
    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var audioFile: AVAudioFile?
    private var targetFormat: AVAudioFormat?
    private var recordingURL: URL?
    private var recordingStartedAt: Date?
    private var audioLevelMeter = AudioLevelMeter()
    private var levelChanged: ((Double) -> Void)?
    private(set) var activeDeviceUID: String?
    private let sampleLock = NSLock()
    private var capturedSamples: [Float] = []
    private var lastSpeechSampleIndex = 0
    private var capturesLiveSamples = false

    var isRecording: Bool {
        captureSession?.isRunning == true
    }

    func start(
        recordingURL requestedURL: URL? = nil,
        selectedDeviceUID: String? =
            MicrophonePreferences.selectedDeviceUID(),
        capturesLiveSamples: Bool = false,
        levelChanged: @escaping (Double) -> Void
    ) throws {
        let url = requestedURL
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("zenvoice-\(UUID().uuidString)")
                .appendingPathExtension("wav")

        guard let device = resolvedDevice(uid: selectedDeviceUID),
              device.isConnected else {
            throw RecorderError.unableToCreateRecorder
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw RecorderError.unableToCreateRecorder
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw RecorderError.invalidInputFormat
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(
                forWriting: url,
                settings: targetFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw RecorderError.unableToCreateRecorder
        }

        let session = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true
        ]

        session.beginConfiguration()
        guard session.canAddInput(input),
              session.canAddOutput(output) else {
            session.commitConfiguration()
            try? FileManager.default.removeItem(at: url)
            throw RecorderError.unableToCreateRecorder
        }
        session.addInput(input)
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: captureQueue)
        session.commitConfiguration()

        self.audioFile = audioFile
        self.audioOutput = output
        self.targetFormat = targetFormat
        self.levelChanged = levelChanged
        activeDeviceUID = device.uniqueID
        recordingURL = url
        recordingStartedAt = Date()
        audioLevelMeter = AudioLevelMeter()
        self.capturesLiveSamples = capturesLiveSamples
        sampleLock.withLock {
            capturedSamples.removeAll(keepingCapacity: true)
            lastSpeechSampleIndex = 0
        }
        captureSession = session

        captureQueue.sync {
            session.startRunning()
        }
        guard session.isRunning else {
            try? FileManager.default.removeItem(at: url)
            reset()
            throw RecorderError.unableToStart
        }
    }

    func stop(
        preserveLiveSamples: Bool = false
    ) -> RecordedAudio? {
        if let captureSession {
            captureQueue.sync {
                audioOutput?.setSampleBufferDelegate(nil, queue: nil)
                captureSession.stopRunning()
            }
        }
        audioFile = nil
        audioOutput = nil
        targetFormat = nil
        levelChanged = nil
        activeDeviceUID = nil
        captureSession = nil
        capturesLiveSamples = false
        if !preserveLiveSamples {
            releaseCapturedSamples()
        }
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
        let url = recordingURL
        _ = stop()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func stableSegment(
        after sampleIndex: Int,
        minimumSpeechDuration: TimeInterval = 0.45,
        requiredSilenceDuration: TimeInterval = 0.70
    ) -> StableAudioSegment? {
        sampleLock.withLock {
            let start = max(0, min(sampleIndex, capturedSamples.count))
            guard StablePauseDetector.isStable(
                segmentStart: start,
                totalSamples: capturedSamples.count,
                lastSpeechSample: lastSpeechSampleIndex,
                minimumSpeechDuration: minimumSpeechDuration,
                requiredSilenceDuration: requiredSilenceDuration
            ) else {
                return nil
            }
            return StableAudioSegment(
                samples: Array(capturedSamples[start...]),
                endSampleIndex: capturedSamples.count
            )
        }
    }

    func samples(after sampleIndex: Int) -> [Float] {
        sampleLock.withLock {
            let start = max(0, min(sampleIndex, capturedSamples.count))
            guard start < capturedSamples.count else {
                return []
            }
            return Array(capturedSamples[start...])
        }
    }

    func releaseCapturedSamples() {
        sampleLock.withLock {
            capturedSamples.removeAll(keepingCapacity: false)
            lastSpeechSampleIndex = 0
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = pcmBuffer(from: sampleBuffer),
              buffer.frameLength > 0 else {
            return
        }
        process(buffer)
    }

    private func resolvedDevice(uid: String?) -> AVCaptureDevice? {
        guard let uid else {
            return AVCaptureDevice.default(for: .audio)
        }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        .devices
        .first { $0.uniqueID == uid }
    }

    private func pcmBuffer(
        from sampleBuffer: CMSampleBuffer
    ) -> AVAudioPCMBuffer? {
        guard let formatDescription =
                CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription =
                CMAudioFormatDescriptionGetStreamBasicDescription(
                    formatDescription
                ),
              let format = AVAudioFormat(
                streamDescription: streamDescription
              ) else {
            return nil
        }

        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0,
              sampleCount <= Int(UInt32.max),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleCount)
              ) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(sampleCount),
            into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let targetFormat,
              buffer.format.sampleRate == targetFormat.sampleRate,
              buffer.format.channelCount == targetFormat.channelCount,
              buffer.format.commonFormat == .pcmFormatFloat32,
              let channel = buffer.floatChannelData?.pointee else {
            return
        }

        let speechDetected = reportLevel(
            channel: channel,
            frameLength: buffer.frameLength
        )
        try? audioFile?.write(from: buffer)
        guard capturesLiveSamples else {
            return
        }
        let samples = Array(
            UnsafeBufferPointer(
                start: channel,
                count: Int(buffer.frameLength)
            )
        )
        sampleLock.withLock {
            capturedSamples.append(contentsOf: samples)
            if speechDetected {
                lastSpeechSampleIndex = capturedSamples.count
            }
        }
    }

    private func reportLevel(
        channel: UnsafeMutablePointer<Float>,
        frameLength: AVAudioFrameCount
    ) -> Bool {
        guard frameLength > 0 else {
            return false
        }
        var sumSquares: Float = 0
        var peak: Float = 0
        for index in 0..<Int(frameLength) {
            let sample = abs(channel[index])
            sumSquares += sample * sample
            peak = max(peak, sample)
        }
        let rms = sqrt(sumSquares / Float(frameLength))
        let averageDecibels = 20 * log10(max(rms, 0.000_001))
        let peakDecibels = 20 * log10(max(peak, 0.000_001))
        let level = audioLevelMeter.update(
            averageDecibels: averageDecibels,
            peakDecibels: peakDecibels
        )
        levelChanged?(level)
        return averageDecibels > -38 || peakDecibels > -28
    }

    private func reset() {
        audioOutput?.setSampleBufferDelegate(nil, queue: nil)
        captureSession?.stopRunning()
        captureSession = nil
        audioOutput = nil
        audioFile = nil
        targetFormat = nil
        levelChanged = nil
        activeDeviceUID = nil
        capturesLiveSamples = false
        recordingURL = nil
        recordingStartedAt = nil
    }
}
