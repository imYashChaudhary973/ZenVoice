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

/// Parakeet TDT smoke: loads each installed TDT GGUF through
/// `ParakeetTDTEngine`, decodes one clip, and checks the release round trip.
///
/// Silent by default (asserts a clean decode and engine plumbing). Set
/// `ZENVOICE_PARAKEET_AUDIO` to a real recording to also require a non-empty
/// transcript. Skips configurations whose model file is absent, matching the
/// whisper path's local-development skip.
do {
    let environment = ProcessInfo.processInfo.environment
    let modelsDirectory = try VerifiedModelCatalog.modelsDirectory()
    var exercised = 0
    for configuration: ParakeetTDTEngine.Configuration in [.v2, .v3] {
        let modelURL = modelsDirectory
            .appendingPathComponent(configuration.modelFilename)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            continue
        }
        let engine = ParakeetTDTEngine(
            configuration: configuration,
            modelURL: modelURL
        )
        try await engine.prepare()
        guard engine.isLoaded else {
            throw NSError(
                domain: "ZenVoiceRuntimeChecks",
                code: 7,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Parakeet \(configuration.displayName) did not stay "
                        + "loaded after prepare()."
                ]
            )
        }
        let audioURL =
            try environment["ZENVOICE_PARAKEET_AUDIO"].map {
                URL(fileURLWithPath: $0)
            } ?? makeSilentFixture()
        let result = try await engine.transcribe(
            audioURL: audioURL,
            languageProfile: .english,
            initialPrompt: nil
        )
        guard result.modelID == configuration.engineID else {
            throw NSError(
                domain: "ZenVoiceRuntimeChecks",
                code: 8,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Parakeet decode reported modelID \(result.modelID), "
                        + "expected \(configuration.engineID)."
                ]
            )
        }
        let requiresSpeech = environment["ZENVOICE_PARAKEET_AUDIO"] != nil
        guard !requiresSpeech || !result.finalTranscript.isEmpty else {
            throw NSError(
                domain: "ZenVoiceRuntimeChecks",
                code: 9,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Parakeet \(configuration.displayName) produced an "
                        + "empty transcript for real speech audio."
                ]
            )
        }
        await engine.release()
        guard !engine.isLoaded else {
            throw NSError(
                domain: "ZenVoiceRuntimeChecks",
                code: 10,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Parakeet \(configuration.displayName) stayed loaded "
                        + "after release()."
                ]
            )
        }
        exercised += 1
        print(
            "  parakeet \(configuration.displayName) decoded "
                + "\(result.finalTranscript.isEmpty ? "silence" : "speech") "
                + "· transcript \"\(result.finalTranscript)\""
        )
    }
    if exercised == 0 {
        print("Parakeet TDT checks skipped: no TDT model in Models.")
    } else {
        print("Parakeet TDT checks passed (\(exercised) configuration(s)).")
    }
} catch {
    FileHandle.standardError.write(
        Data("ZenVoice Parakeet checks failed: \(error)\n".utf8)
    )
    exit(1)
}

/// This process's physical footprint, which is what macOS charges the app.
///
/// `ps`-style RSS counts shared and file-backed pages and reads far higher
/// than the number that matters, so the memory checks use this instead.
private func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size
            / MemoryLayout<natural_t>.size
    )
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard status == KERN_SUCCESS else {
        return -1
    }
    return Double(info.phys_footprint) / 1024 / 1024
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
    if let modelPath = environment["ZENVOICE_MODEL_PATH"] {
        print(
            "model artifact: "
                + URL(fileURLWithPath: modelPath).standardizedFileURL.path
        )
    }
    print("hardware profile: \(HardwareProfile.current().summary)")
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
    // Idle unloading is what keeps a menu-bar app from holding a gigabyte-plus
    // Whisper context all day. Two things have to hold: `unload()` must
    // actually give the memory back, and the transcriber must decode normally
    // afterwards by reloading on demand.
    let loadedMB = footprintMB()
    transcriber.unload()
    let unloadedMB = footprintMB()
    let reclaimedMB = loadedMB - unloadedMB
    guard !transcriber.isLoaded else {
        throw NSError(
            domain: "ZenVoiceRuntimeChecks",
            code: 4,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "unload() left the model resident."
            ]
        )
    }
    // A generous floor. The point is that unloading returns the weights, not
    // that it returns every last page — ggml's Metal backend keeps allocator
    // and pipeline state that survives `whisper_free`.
    guard reclaimedMB > 200 else {
        throw NSError(
            domain: "ZenVoiceRuntimeChecks",
            code: 5,
            userInfo: [
                NSLocalizedDescriptionKey: String(
                    format:
                        "unload() reclaimed only %.0f MB "
                        + "(%.0f MB before, %.0f MB after).",
                    reclaimedMB,
                    loadedMB,
                    unloadedMB
                )
            ]
        )
    }
    try runPass(3, transcriber: transcriber, audioURL: audioURL)
    guard transcriber.isLoaded else {
        throw NSError(
            domain: "ZenVoiceRuntimeChecks",
            code: 6,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Decoding after unload() did not reload the model."
            ]
        )
    }
    print(
        String(
            format:
                "  memory %.0f MB loaded · %.0f MB after unload "
                + "(reclaimed %.0f MB) · reloaded on next decode",
            loadedMB,
            unloadedMB,
            reclaimedMB
        )
    )
    print(
        "ZenVoice runtime checks passed (persistent model + live samples: "
            + "\(transcriber.modelID))."
    )
} catch ZenVoiceConfiguration.ConfigurationError.modelMissing {
    // Skipping is a local-development convenience only. CI sets
    // ZENVOICE_RUNTIME_REQUIRED so a runner without a resolvable model
    // fails the build instead of passing vacuously.
    if ProcessInfo.processInfo.environment["ZENVOICE_RUNTIME_REQUIRED"] == "1" {
        let message =
            "ZenVoice runtime checks failed: no verified model is "
            + "resolvable, but ZENVOICE_RUNTIME_REQUIRED is set. Install "
            + "a verified model in Models or set ZENVOICE_MODEL_PATH.\n"
        FileHandle.standardError.write(Data(message.utf8))
        exit(1)
    }
    print(
        "ZenVoice runtime checks skipped: install a verified model in Models."
    )
} catch {
    FileHandle.standardError.write(
        Data("ZenVoice runtime checks failed: \(error)\n".utf8)
    )
    exit(1)
}
