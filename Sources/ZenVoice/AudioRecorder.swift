import AVFoundation
import AudioToolbox
import Foundation
import ZenVoiceCore

final class AudioRecorder {
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

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var recordingURL: URL?
    private var recordingStartedAt: Date?
    private var audioLevelMeter = AudioLevelMeter()
    private var levelChanged: ((Double) -> Void)?
    private var isTapInstalled = false
    private(set) var activeDeviceUID: String?
    private let sampleLock = NSLock()
    private var capturedSamples: [Float] = []
    private var lastSpeechSampleIndex = 0
    private var capturesLiveSamples = false

    var isRecording: Bool {
        engine.isRunning
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

        let inputNode = engine.inputNode
        let effectiveDeviceUID = selectedDeviceUID
            ?? AVCaptureDevice.default(for: .audio)?.uniqueID
        if let pinnedDeviceUID = selectedDeviceUID {
            var deviceID = try MicrophoneCatalog.audioDeviceID(
                uid: pinnedDeviceUID
            )
            guard let audioUnit = inputNode.audioUnit,
                  AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &deviceID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                  ) == noErr else {
                throw RecorderError.unableToCreateRecorder
            }
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              inputFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
              ),
              let converter = AVAudioConverter(
                from: inputFormat,
                to: targetFormat
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

        self.audioFile = audioFile
        self.converter = converter
        self.targetFormat = targetFormat
        self.levelChanged = levelChanged
        activeDeviceUID = effectiveDeviceUID
        recordingURL = url
        recordingStartedAt = Date()
        audioLevelMeter = AudioLevelMeter()
        self.capturesLiveSamples = capturesLiveSamples
        sampleLock.withLock {
            capturedSamples.removeAll(keepingCapacity: true)
            lastSpeechSampleIndex = 0
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        isTapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            if isTapInstalled {
                inputNode.removeTap(onBus: 0)
                isTapInstalled = false
            }
            try? FileManager.default.removeItem(at: url)
            reset()
            throw RecorderError.unableToStart
        }
    }

    func stop(
        preserveLiveSamples: Bool = false
    ) -> RecordedAudio? {
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        audioFile = nil
        converter = nil
        targetFormat = nil
        levelChanged = nil
        activeDeviceUID = nil
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

    private func process(_ buffer: AVAudioPCMBuffer) {
        let speechDetected = reportLevel(from: buffer)
        guard let converter,
              let targetFormat,
              let audioFile else {
            return
        }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(
            max(1, ceil(Double(buffer.frameLength) * ratio) + 8)
        )
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: capacity
        ) else {
            return
        }

        var suppliedInput = false
        var conversionError: NSError?
        _ = converter.convert(
            to: converted,
            error: &conversionError
        ) { _, status in
            if suppliedInput {
                status.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            status.pointee = .haveData
            return buffer
        }
        guard conversionError == nil,
              converted.frameLength > 0 else {
            return
        }
        try? audioFile.write(from: converted)
        guard let channel = converted.floatChannelData?.pointee else {
            return
        }
        guard capturesLiveSamples else {
            return
        }
        let samples = Array(
            UnsafeBufferPointer(
                start: channel,
                count: Int(converted.frameLength)
            )
        )
        sampleLock.withLock {
            capturedSamples.append(contentsOf: samples)
            if speechDetected {
                lastSpeechSampleIndex = capturedSamples.count
            }
        }
    }

    private func reportLevel(from buffer: AVAudioPCMBuffer) -> Bool {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let channel = buffer.floatChannelData?.pointee,
              buffer.frameLength > 0 else {
            return false
        }
        var sumSquares: Float = 0
        var peak: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            let sample = abs(channel[index])
            sumSquares += sample * sample
            peak = max(peak, sample)
        }
        let rms = sqrt(sumSquares / Float(buffer.frameLength))
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
        isTapInstalled = false
        audioFile = nil
        converter = nil
        targetFormat = nil
        levelChanged = nil
        activeDeviceUID = nil
        capturesLiveSamples = false
        recordingURL = nil
        recordingStartedAt = nil
    }
}
