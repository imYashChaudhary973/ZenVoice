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
import CoreMedia
import Foundation
import ScreenCaptureKit

/// System-audio half of a local meeting. Mic stays on `AudioRecorder`.
final class MeetingSystemAudio: NSObject, SCStreamOutput, SCStreamDelegate {
    enum CaptureError: LocalizedError {
        case noDisplay
        case cannotWrite
        case cannotStart

        var errorDescription: String? {
            switch self {
            case .noDisplay:
                return "ZenVoice could not find a display to capture."
            case .cannotWrite:
                return "ZenVoice could not write the meeting system audio."
            case .cannotStart:
                return "ZenVoice could not start system-audio capture. Grant Screen Recording in System Settings."
            }
        }
    }

    private let queue = DispatchQueue(
        label: "com.zenvoice.app.meetingSystemAudio"
    )
    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private let fileLock = NSLock()

    var isRunning: Bool { stream != nil }

    func start(writingTo url: URL) async throws {
        try await stop()
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw CaptureError.cannotWrite
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
            throw CaptureError.cannotWrite
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }
        let filter = Self.contentFilter(content: content, display: display)
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.width = 8
        configuration.height = 8
        configuration.showsCursor = false
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        self.targetFormat = targetFormat
        self.audioFile = audioFile
        self.stream = stream
        do {
            try stream.addStreamOutput(
                self,
                type: .audio,
                sampleHandlerQueue: queue
            )
            try await stream.startCapture()
        } catch {
            self.stream = nil
            self.audioFile = nil
            try? FileManager.default.removeItem(at: url)
            throw CaptureError.cannotStart
        }
    }

    func pause() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    func resume(writingTo url: URL) async throws {
        if stream != nil { return }
        // Keep appending to the existing file when we still hold it.
        if audioFile == nil {
            try await start(writingTo: url)
            return
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }
        let filter = Self.contentFilter(content: content, display: display)
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.width = 8
        configuration.height = 8
        configuration.showsCursor = false
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        try stream.addStreamOutput(
            self,
            type: .audio,
            sampleHandlerQueue: queue
        )
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async throws {
        if let stream {
            self.stream = nil
            try? await stream.stopCapture()
        }
        queue.sync {
            audioFile = nil
            converter = nil
            targetFormat = nil
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio,
              CMSampleBufferIsValid(sampleBuffer),
              let targetFormat else {
            return
        }
        guard let inputBuffer = Self.pcmBuffer(from: sampleBuffer) else {
            return
        }
        fileLock.lock()
        defer { fileLock.unlock() }
        guard let audioFile else { return }
        do {
            let toWrite: AVAudioPCMBuffer
            if inputBuffer.format.sampleRate == targetFormat.sampleRate,
               inputBuffer.format.channelCount == 1 {
                toWrite = inputBuffer
            } else {
                if converter == nil {
                    converter = AVAudioConverter(
                        from: inputBuffer.format,
                        to: targetFormat
                    )
                }
                guard let converter,
                      let converted = AVAudioPCMBuffer(
                        pcmFormat: targetFormat,
                        frameCapacity: AVAudioFrameCount(
                            Double(inputBuffer.frameLength)
                                * targetFormat.sampleRate
                                / inputBuffer.format.sampleRate
                                + 32
                        )
                    ) else {
                    return
                }
                var error: NSError?
                var consumed = false
                converter.convert(to: converted, error: &error) {
                    _, status in
                    if consumed {
                        status.pointee = .noDataNow
                        return nil
                    }
                    consumed = true
                    status.pointee = .haveData
                    return inputBuffer
                }
                if error != nil { return }
                toWrite = converted
            }
            if toWrite.frameLength > 0 {
                try audioFile.write(from: toWrite)
            }
        } catch {
            return
        }
    }

    private static let meetingBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.tinyspeck.slackmacgap",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.apple.Safari",
        "com.microsoft.edgemac"
    ]

    /// Prefers a meeting app; Meet is matched on the window title in memory
    /// only. Falls back to the display so ad-hoc calls still record Them.
    private static func contentFilter(
        content: SCShareableContent,
        display: SCDisplay
    ) -> SCContentFilter {
        if let meet = content.windows.first(where: { window in
            let title = window.title ?? ""
            return title.localizedCaseInsensitiveContains("Meet")
                || title.localizedCaseInsensitiveContains("Google Meet")
        }) {
            return SCContentFilter(desktopIndependentWindow: meet)
        }
        let apps = content.applications.filter {
            meetingBundleIDs.contains($0.bundleIdentifier)
        }
        if let zoom = apps.first(where: { $0.bundleIdentifier == "us.zoom.xos" }) {
            return SCContentFilter(
                display: display,
                including: [zoom],
                exceptingWindows: []
            )
        }
        if let teams = apps.first(where: {
            $0.bundleIdentifier == "com.microsoft.teams2"
                || $0.bundleIdentifier == "com.microsoft.teams"
        }) {
            return SCContentFilter(
                display: display,
                including: [teams],
                exceptingWindows: []
            )
        }
        if let slack = apps.first(where: {
            $0.bundleIdentifier == "com.tinyspeck.slackmacgap"
        }) {
            return SCContentFilter(
                display: display,
                including: [slack],
                exceptingWindows: []
            )
        }
        if !apps.isEmpty {
            return SCContentFilter(
                display: display,
                including: apps,
                exceptingWindows: []
            )
        }
        return SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
    }

    private static func pcmBuffer(
        from sampleBuffer: CMSampleBuffer
    ) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(
            sampleBuffer
        ) else {
            return nil
        }
        var asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
            formatDescription
        )!.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            return nil
        }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frames
        ) else {
            return nil
        }
        buffer.frameLength = frames
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }
        let abs = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        for (index, audioBuffer) in abs.enumerated() {
            guard index < buffer.audioBufferList.pointee.mNumberBuffers,
                  let source = audioBuffer.mData,
                  let dest = UnsafeMutableAudioBufferListPointer(
                    buffer.mutableAudioBufferList
                  )[index].mData else {
                continue
            }
            dest.copyMemory(
                from: source,
                byteCount: Int(audioBuffer.mDataByteSize)
            )
        }
        return buffer
    }
}
