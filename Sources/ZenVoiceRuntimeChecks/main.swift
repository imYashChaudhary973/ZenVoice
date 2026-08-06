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
    let environment = ProcessInfo.processInfo.environment
    let languageProfile: LanguageProfile =
        environment["ZENVOICE_RUNTIME_LANGUAGE"] == "hinglish"
        ? .hinglish
        : .english
    let configuration = try ZenVoiceConfiguration.discover(
        languageProfile: languageProfile,
        environment: environment
    )
    let audioURL = try makeSilentFixture()
    defer {
        try? FileManager.default.removeItem(at: audioURL)
    }
    let transcriber = WhisperTranscriber(configuration: configuration)

    // Warm-up moves model load and Metal pipeline construction off the first
    // dictation. Two things have to hold: it must be idempotent, because the
    // app fires it on every route into a recording, and it must leave the
    // transcriber decoding normally. The timings are reported rather than
    // asserted — the gap between a cold and a warm first decode is real but its
    // size depends on the model and the machine, which is not a stable gate.
    let warmStart = Date()
    transcriber.warmUp()
    let warmSeconds = Date().timeIntervalSince(warmStart)
    let repeatStart = Date()
    transcriber.warmUp()
    let repeatSeconds = Date().timeIntervalSince(repeatStart)
    guard repeatSeconds < warmSeconds || warmSeconds < 0.05 else {
        throw NSError(
            domain: "ZenVoiceRuntimeChecks",
            code: 3,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "warmUp() repeated the load instead of returning early."
            ]
        )
    }

    let firstDecodeStart = Date()
    try runPass(1, transcriber: transcriber, audioURL: audioURL)
    let firstDecodeSeconds = Date().timeIntervalSince(firstDecodeStart)
    let secondDecodeStart = Date()
    try runPass(2, transcriber: transcriber, audioURL: audioURL)
    let secondDecodeSeconds = Date().timeIntervalSince(secondDecodeStart)
    print(
        String(
            format:
                "  warm-up %.2fs (repeat %.3fs) · "
                + "first decode %.2fs · second decode %.2fs",
            warmSeconds,
            repeatSeconds,
            firstDecodeSeconds,
            secondDecodeSeconds
        )
    )
    do {
        _ = try transcriber.transcribe(
            samples: Array(repeating: 0, count: 16_000),
            languageProfile: languageProfile,
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
