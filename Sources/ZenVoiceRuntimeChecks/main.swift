import AVFoundation
import Foundation
import ZenVoiceCore
import ZenVoiceRuntime

private func makeSilentFixture() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("zenvoice-runtime-\(UUID().uuidString).wav")
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!
    let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: 16_000
    )!
    buffer.frameLength = 16_000
    buffer.floatChannelData?.pointee.initialize(
        repeating: 0,
        count: 16_000
    )
    let file = try AVAudioFile(
        forWriting: url,
        settings: format.settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )
    try file.write(from: buffer)
    return url
}

private func runPass(
    _ number: Int,
    transcriber: WhisperTranscriber,
    audioURL: URL
) throws {
    do {
        let result = try transcriber.transcribe(audioURL: audioURL)
        guard result.modelID == transcriber.modelID else {
            throw NSError(
                domain: "ZenVoiceRuntimeChecks",
                code: number,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Runtime returned the wrong model identifier."
                ]
            )
        }
    } catch WhisperTranscriber.TranscriptionError.noSpeech {
        // Silence reaching the no-speech decision is a successful runtime pass.
    }
}

do {
    let configuration = try ZenVoiceConfiguration.discover()
    let audioURL = try makeSilentFixture()
    defer {
        try? FileManager.default.removeItem(at: audioURL)
    }
    let transcriber = WhisperTranscriber(configuration: configuration)
    try runPass(1, transcriber: transcriber, audioURL: audioURL)
    try runPass(2, transcriber: transcriber, audioURL: audioURL)
    print(
        "ZenVoice runtime checks passed (persistent model: "
            + "\(transcriber.modelID))."
    )
} catch ZenVoiceConfiguration.ConfigurationError.modelMissing {
    print(
        "ZenVoice runtime checks skipped: install a verified model in Models."
    )
} catch {
    FileHandle.standardError.write(
        Data("ZenVoice runtime checks failed: \(error)\n".utf8)
    )
    exit(1)
}
