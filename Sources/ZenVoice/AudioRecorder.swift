// Copyright 2026 Yash Chaudhary
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AVFoundation
import Accelerate
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
        case invalidDeterministicFixture

        var errorDescription: String? {
            switch self {
            case .unableToCreateRecorder:
                return "ZenVoice could not open the microphone."
            case .unableToStart:
                return "ZenVoice could not start recording."
            case .invalidInputFormat:
                return "The selected microphone returned an unsupported audio format."
            case .invalidDeterministicFixture:
                return
                    "The E2E audio fixture must be a readable 16 kHz mono "
                    + "local file no larger than 100 MB or 90 minutes."
            }
        }
    }

    private let captureQueue = DispatchQueue(
        label: "com.zenvoice.app.audioCapture",
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
    private var speechDetector = SpeechActivityDetector()
#if DEBUG
    private static let fixtureEnvironmentKey = "ZENVOICE_E2E_AUDIO_FILE"
    private static let maximumFixtureBytes: Int64 = 100 * 1_024 * 1_024
    private static let maximumFixtureDuration: TimeInterval = 90 * 60
    private var deterministicFixtureDuration: TimeInterval?
#endif
    /// Where the last consumed phrase ended.
    private var committedSampleIndex = 0
    /// A completed phrase boundary, remembered until someone asks for it.
    ///
    /// Stability used to be evaluated only when the preview timer fired every
    /// 0.35 s, but it needs 0.70 s of silence to be true — so a pause barely
    /// over 0.70 s was only noticed if a tick happened to land inside it, and
    /// otherwise vanished as soon as speech resumed and moved
    /// `lastSpeechSampleIndex` forward. Latching the boundary the moment it
    /// occurs makes detection independent of when anyone looks.
    private var latchedBoundary: Int?

    var isRecording: Bool {
#if DEBUG
        deterministicFixtureDuration != nil
            || captureSession?.isRunning == true
#else
        captureSession?.isRunning == true
#endif
    }

    var usesDeterministicFixture: Bool {
#if DEBUG
        guard let path = ProcessInfo.processInfo.environment[
            Self.fixtureEnvironmentKey
        ] else {
            return false
        }
        return !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
#else
        return false
#endif
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

#if DEBUG
        if let fixtureURL = try deterministicFixtureURL() {
            try startDeterministicFixture(
                sourceURL: fixtureURL,
                destinationURL: url,
                capturesLiveSamples: capturesLiveSamples,
                levelChanged: levelChanged
            )
            return
        }
#endif

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
            if capturesLiveSamples {
                // This array grows inside the capture callback, so a
                // reallocation there copies everything recorded so far on the
                // realtime audio thread. Reserving a minute up front keeps an
                // ordinary dictation clear of that entirely, and costs nothing
                // when preview is off because nothing is captured at all.
                capturedSamples.reserveCapacity(60 * 16_000)
            }
            lastSpeechSampleIndex = 0
            committedSampleIndex = 0
            latchedBoundary = nil
            speechDetector = SpeechActivityDetector()
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
#if DEBUG
        let fixtureDuration = deterministicFixtureDuration
        deterministicFixtureDuration = nil
#endif
        if let captureSession {
            captureQueue.sync {
                audioOutput?.setSampleBufferDelegate(nil, queue: nil)
                captureSession.stopRunning()
                audioFile = nil
            }
        } else {
            audioFile = nil
        }
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
#if DEBUG
        if let fixtureDuration {
            return RecordedAudio(
                url: recordingURL,
                durationSeconds: fixtureDuration
            )
        }
#endif
        let duration = recordingStartedAt.map {
            max(0, Date().timeIntervalSince($0))
        } ?? 0
        return RecordedAudio(
            url: recordingURL,
            durationSeconds: duration
        )
    }

    func pause() {
#if DEBUG
        if deterministicFixtureDuration != nil {
            return
        }
#endif
        guard let captureSession, captureSession.isRunning else {
            return
        }
        captureQueue.sync {
            audioOutput?.setSampleBufferDelegate(nil, queue: nil)
            captureSession.stopRunning()
        }
    }

    func resume() throws {
#if DEBUG
        if deterministicFixtureDuration != nil {
            return
        }
#endif
        guard let captureSession, let audioOutput else {
            throw RecorderError.unableToStart
        }
        guard !captureSession.isRunning else {
            return
        }
        captureQueue.sync {
            audioOutput.setSampleBufferDelegate(self, queue: captureQueue)
            captureSession.startRunning()
        }
        guard captureSession.isRunning else {
            throw RecorderError.unableToStart
        }
    }

    func cancel() {
        let url = recordingURL
        _ = stop()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func stableSegment(after sampleIndex: Int) -> StableAudioSegment? {
        sampleLock.withLock {
            let start = max(0, min(sampleIndex, capturedSamples.count))
            committedSampleIndex = max(committedSampleIndex, start)
            guard let boundary = latchedBoundary,
                  boundary > start,
                  boundary <= capturedSamples.count else {
                return nil
            }
            latchedBoundary = nil
            committedSampleIndex = boundary
            return StableAudioSegment(
                samples: Array(capturedSamples[start..<boundary]),
                endSampleIndex: boundary
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
            committedSampleIndex = 0
            latchedBoundary = nil
            speechDetector = SpeechActivityDetector()
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
            // Evaluate on every buffer rather than on a timer, and hold the
            // first boundary found until it is consumed.
            if latchedBoundary == nil,
               StablePauseDetector.isStable(
                segmentStart: committedSampleIndex,
                totalSamples: capturedSamples.count,
                lastSpeechSample: lastSpeechSampleIndex
               ) {
                latchedBoundary = capturedSamples.count
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
        // Runs in the capture callback for every buffer that arrives, so the
        // measurement is vectorised rather than looped: `vDSP_measqv` is the
        // mean of the squares and `vDSP_maxmgv` the largest magnitude, which is
        // what the scalar version computed a sample at a time.
        var meanSquare: Float = 0
        var peak: Float = 0
        vDSP_measqv(channel, 1, &meanSquare, vDSP_Length(frameLength))
        vDSP_maxmgv(channel, 1, &peak, vDSP_Length(frameLength))
        let rms = sqrt(meanSquare)
        let averageDecibels = 20 * log10(max(rms, 0.000_001))
        let peakDecibels = 20 * log10(max(peak, 0.000_001))
        let level = audioLevelMeter.update(
            averageDecibels: averageDecibels,
            peakDecibels: peakDecibels
        )
        levelChanged?(level)
        return speechDetector.isSpeech(
            averageDecibels: averageDecibels,
            peakDecibels: peakDecibels
        )
    }

#if DEBUG
    private func deterministicFixtureURL() throws -> URL? {
        guard let rawPath = ProcessInfo.processInfo.environment[
            Self.fixtureEnvironmentKey
        ]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else {
            return nil
        }
        guard rawPath.hasPrefix("/") else {
            throw RecorderError.invalidDeterministicFixture
        }
        let sourceURL = URL(fileURLWithPath: rawPath)
        let resolvedURL = sourceURL.standardizedFileURL
            .resolvingSymlinksInPath()
        let values = try resolvedURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
            .isReadableKey
        ])
        guard values.isRegularFile == true,
              values.isReadable == true,
              Int64(values.fileSize ?? -1) > 0,
              Int64(values.fileSize ?? -1) <= Self.maximumFixtureBytes else {
            throw RecorderError.invalidDeterministicFixture
        }
        return resolvedURL
    }

    private func startDeterministicFixture(
        sourceURL: URL,
        destinationURL: URL,
        capturesLiveSamples: Bool,
        levelChanged: @escaping (Double) -> Void
    ) throws {
        let sourceFile: AVAudioFile
        do {
            sourceFile = try AVAudioFile(forReading: sourceURL)
        } catch {
            throw RecorderError.invalidDeterministicFixture
        }
        let sourceFormat = sourceFile.processingFormat
        guard sourceFile.length > 0,
              sourceFormat.sampleRate == 16_000,
              sourceFormat.channelCount == 1,
              sourceFormat.commonFormat == .pcmFormatFloat32,
              !sourceFormat.isInterleaved else {
            throw RecorderError.invalidDeterministicFixture
        }
        let duration = Double(sourceFile.length) / sourceFormat.sampleRate
        guard duration > 0,
              duration <= Self.maximumFixtureDuration,
              let sourceCapacity = AVAudioFrameCount(
                  exactly: sourceFile.length
              ),
              let sourceBuffer = AVAudioPCMBuffer(
                  pcmFormat: sourceFormat,
                  frameCapacity: sourceCapacity
              ) else {
            throw RecorderError.invalidDeterministicFixture
        }
        do {
            try sourceFile.read(into: sourceBuffer)
        } catch {
            throw RecorderError.invalidDeterministicFixture
        }

        let outputFile: AVAudioFile
        do {
            outputFile = try AVAudioFile(
                forWriting: destinationURL,
                settings: sourceFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw RecorderError.unableToCreateRecorder
        }

        audioFile = outputFile
        targetFormat = sourceFormat
        self.levelChanged = levelChanged
        activeDeviceUID = "ZenVoice deterministic E2E fixture"
        recordingURL = destinationURL
        recordingStartedAt = Date()
        deterministicFixtureDuration =
            Double(sourceBuffer.frameLength) / sourceFormat.sampleRate
        audioLevelMeter = AudioLevelMeter()
        self.capturesLiveSamples = capturesLiveSamples
        sampleLock.withLock {
            capturedSamples.removeAll(keepingCapacity: true)
            lastSpeechSampleIndex = 0
            committedSampleIndex = 0
            latchedBoundary = nil
            speechDetector = SpeechActivityDetector()
        }
        process(sourceBuffer)
        audioFile = nil
    }
#endif

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
#if DEBUG
        deterministicFixtureDuration = nil
#endif
    }
}
