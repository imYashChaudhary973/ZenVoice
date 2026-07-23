import AVFoundation
import Foundation
import ZenVoiceCore
import ZenVoiceRefinementRuntime
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
    let missingRefiner = LocalTextRefiner(
        modelURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "missing-refinement-\(UUID().uuidString).gguf"
            )
    )
    do {
        _ = try missingRefiner.refine("Keep this local.")
        throw NSError(
            domain: "ZenVoiceRuntimeChecks",
            code: 3,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Missing refinement model unexpectedly loaded."
            ]
        )
    } catch LocalTextRefiner.RefinementError.modelLoadFailed {
        // The linked llama.cpp runtime rejected the missing model.
    }

    if let refinementPath =
        ProcessInfo.processInfo.environment[
            "ZENVOICE_REFINEMENT_MODEL_PATH"
        ] {
        let original =
            "Um, create the the local app with Swift."
        let localOutput = try LocalTextRefiner(
            modelURL: URL(fileURLWithPath: refinementPath)
        ).refine(
            original,
            timeLimit: 5
        )
        guard LocalRefinementGuard.validatedCandidate(
            output: localOutput,
            original: original
        ) != nil else {
            throw NSError(
                domain: "ZenVoiceRuntimeChecks",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The real refinement model failed the meaning guard: \(localOutput)"
                ]
            )
        }
        print("ZenVoice local refinement runtime passed.")
    }

    let configuration = try ZenVoiceConfiguration.discover()
    let audioURL = try makeSilentFixture()
    defer {
        try? FileManager.default.removeItem(at: audioURL)
    }
    let transcriber = WhisperTranscriber(configuration: configuration)
    try runPass(1, transcriber: transcriber, audioURL: audioURL)
    try runPass(2, transcriber: transcriber, audioURL: audioURL)
    do {
        _ = try transcriber.transcribe(
            samples: Array(repeating: 0, count: 16_000),
            languageProfile: .english,
            initialPrompt: "ZenVoice SwiftUI"
        )
    } catch WhisperTranscriber.TranscriptionError.noSpeech {
        // Direct in-memory samples reached the no-speech decision.
    }
    print(
        "ZenVoice runtime checks passed (persistent model + live samples: "
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
