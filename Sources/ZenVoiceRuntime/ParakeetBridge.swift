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

import Foundation
import parakeet

/// Thin Swift wrapper over the parakeet.cpp flat C-API.
///
/// The C API loads a GGUF model once into a `parakeet_ctx`, then transcribes
/// mono float PCM or WAV files. This wrapper owns the context and frees the
/// malloc'd strings the library returns. It is intentionally low-level: the
/// `ParakeetTDTv3Engine` translates ZenVoice's `LanguageProfile` and audio into
/// these calls.
final class ParakeetContext: @unchecked Sendable {
    private let ctx: OpaquePointer
    private let lock = NSLock()

    init(modelPath: String) throws {
        guard let ctx = parakeet_capi_load(modelPath) else {
            throw ParakeetError.cannotLoadModel(modelPath)
        }
        self.ctx = ctx
    }

    deinit {
        parakeet_capi_free(ctx)
    }

    /// Transcribes 16 kHz mono float PCM using the default decoder.
    func transcribe(
        samples: [Float],
        sampleRate: Int32 = 16_000,
        languageCode: String?
    ) throws -> String {
        let result: UnsafeMutablePointer<CChar>?
        if let languageCode, !languageCode.isEmpty {
            result = languageCode.withCString { lang in
                samples.withUnsafeBufferPointer { buffer in
                    lock.withLock {
                        parakeet_capi_transcribe_pcm_lang(
                            ctx,
                            buffer.baseAddress,
                            Int32(samples.count),
                            sampleRate,
                            0,
                            lang
                        )
                    }
                }
            }
        } else {
            result = samples.withUnsafeBufferPointer { buffer in
                lock.withLock {
                    parakeet_capi_transcribe_pcm(
                        ctx,
                        buffer.baseAddress,
                        Int32(samples.count),
                        sampleRate,
                        0
                    )
                }
            }
        }
        guard let result else {
            throw lastError()
        }
        defer { parakeet_capi_free_string(result) }
        return String(cString: result)
    }

    /// Transcribes a WAV file at `url`.
    func transcribe(url: URL, languageCode: String?) throws -> String {
        let path = url.path
        let result: UnsafeMutablePointer<CChar>?
        if let languageCode, !languageCode.isEmpty {
            result = path.withCString { cPath in
                languageCode.withCString { lang in
                    lock.withLock {
                        parakeet_capi_transcribe_path_lang(
                            ctx,
                            cPath,
                            0,
                            lang
                        )
                    }
                }
            }
        } else {
            result = path.withCString { cPath in
                lock.withLock {
                    parakeet_capi_transcribe_path(ctx, cPath, 0)
                }
            }
        }
        guard let result else {
            throw lastError()
        }
        defer { parakeet_capi_free_string(result) }
        return String(cString: result)
    }

    /// Cache-aware streaming transcription of 16 kHz mono float PCM.
    ///
    /// Feeds audio in fixed-size chunks and returns the finalized transcript
    /// accumulated across all chunks plus the stream tail. The stream session
    /// is created and freed inside this call so callers can treat it like the
    /// offline `transcribe(samples:)` interface.
    func transcribeStreaming(
        samples: [Float],
        sampleRate: Int32 = 16_000,
        languageCode: String?
    ) throws -> String {
        guard sampleRate == 16_000 else {
            throw ParakeetError.transcriptionFailed(
                "streaming transcription requires 16 kHz mono PCM"
            )
        }
        guard let stream = makeStream(languageCode: languageCode) else {
            throw lastError()
        }
        defer { parakeet_capi_stream_free(stream) }

        let chunkSize = 8_000 // 0.5 s at 16 kHz
        var transcript = ""
        var index = 0
        while index < samples.count {
            let end = min(index + chunkSize, samples.count)
            let chunk = Array(samples[index..<end])
            let piece = try feed(stream: stream, samples: chunk)
            transcript += piece
            index += chunkSize
        }
        let tail = try finalize(stream: stream)
        return (transcript + tail).trimmingCharacters(in: .whitespaces)
    }

    private func makeStream(languageCode: String?) -> OpaquePointer? {
        if let languageCode, !languageCode.isEmpty {
            return languageCode.withCString { lang in
                lock.withLock { parakeet_capi_stream_begin_lang(ctx, lang) }
            }
        }
        return lock.withLock { parakeet_capi_stream_begin(ctx) }
    }

    private func feed(stream: OpaquePointer, samples: [Float]) throws -> String {
        var events: Int32 = 0
        let result = withUnsafeMutablePointer(to: &events) { eventsPtr in
            samples.withUnsafeBufferPointer { buffer in
                lock.withLock {
                    parakeet_capi_stream_feed(
                        stream,
                        buffer.baseAddress,
                        Int32(samples.count),
                        eventsPtr
                    )
                }
            }
        }
        guard let result else {
            throw lastError()
        }
        defer { parakeet_capi_free_string(result) }
        return String(cString: result)
    }

    private func finalize(stream: OpaquePointer) throws -> String {
        let result = lock.withLock { parakeet_capi_stream_finalize(stream) }
        guard let result else {
            throw lastError()
        }
        defer { parakeet_capi_free_string(result) }
        return String(cString: result)
    }

    private func lastError() -> Error {
        guard let errorPointer = parakeet_capi_last_error(ctx) else {
            return ParakeetError.transcriptionFailed("unknown error")
        }
        let message = String(cString: errorPointer)
        return ParakeetError.transcriptionFailed(message)
    }
}

enum ParakeetError: LocalizedError {
    case cannotLoadModel(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotLoadModel(let path):
            return "Could not load Parakeet model at \(path)."
        case .transcriptionFailed(let message):
            return "Parakeet transcription failed: \(message)"
        }
    }
}

private extension NSLock {
    func withLock<T>(_ action: () -> T) -> T {
        lock()
        defer { unlock() }
        return action()
    }
}
