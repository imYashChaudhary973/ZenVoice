import AVFoundation
import Foundation
import ZenVoiceCore
import whisper

public final class WhisperTranscriber: @unchecked Sendable {
    public enum TranscriptionError: LocalizedError {
        case invalidAudio
        case modelLoadFailed
        case runtimeFailed
        case noSpeech

        public var errorDescription: String? {
            switch self {
            case .invalidAudio:
                return "The recorded audio could not be decoded."
            case .modelLoadFailed:
                return "The selected local model could not be loaded."
            case .runtimeFailed:
                return "Local transcription failed."
            case .noSpeech:
                return "No speech detected."
            }
        }
    }

    private let configuration: ZenVoiceConfiguration
    private let cleaner = TranscriptCleaner()
    private var context: OpaquePointer?

    public var modelID: String {
        configuration.modelID
    }

    public var language: String {
        configuration.language
    }

    public var languageProfile: LanguageProfile {
        configuration.languageProfile
    }

    public init(configuration: ZenVoiceConfiguration) {
        self.configuration = configuration
        whisper_log_set({ _, _, _ in }, nil)
    }

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    public func transcribe(audioURL: URL) throws -> TranscriptionResult {
        let samples = try loadSamples(from: audioURL)
        return try transcribe(samples: samples)
    }

    public func transcribe(samples: [Float]) throws -> TranscriptionResult {
        guard !samples.isEmpty else {
            throw TranscriptionError.invalidAudio
        }
        let processingStartedAt = Date()
        let context = try loadedContext()
        var parameters = whisper_full_default_params(
            WHISPER_SAMPLING_GREEDY
        )
        parameters.n_threads = Int32(
            max(1, min(8, ProcessInfo.processInfo.activeProcessorCount))
        )
        parameters.no_timestamps = true
        parameters.print_special = false
        parameters.print_progress = false
        parameters.print_realtime = false
        parameters.print_timestamps = false
        parameters.translate = configuration.shouldTranslateToEnglish

        let status = configuration.language.withCString { language in
            parameters.language = language
            return samples.withUnsafeBufferPointer { buffer in
                whisper_full(
                    context,
                    parameters,
                    buffer.baseAddress,
                    Int32(buffer.count)
                )
            }
        }
        guard status == 0 else {
            throw TranscriptionError.runtimeFailed
        }

        var rawTranscript = ""
        let segmentCount = whisper_full_n_segments(context)
        for index in 0..<segmentCount {
            guard let text = whisper_full_get_segment_text(context, index) else {
                continue
            }
            rawTranscript += String(cString: text)
        }
        let cleanedTranscript = cleaner.clean(rawTranscript)
        let finalTranscript = configuration.shouldTransliterateToLatin
            ? LocalTransliterator.latinScript(cleanedTranscript)
            : cleanedTranscript

        guard !finalTranscript.isEmpty else {
            throw TranscriptionError.noSpeech
        }

        return TranscriptionResult(
            rawTranscript: rawTranscript
                .trimmingCharacters(in: .whitespacesAndNewlines),
            finalTranscript: finalTranscript,
            correctionCount: 0,
            isPartial: false,
            modelID: configuration.modelID,
            processingDurationSeconds:
                Date().timeIntervalSince(processingStartedAt)
        )
    }

    private func loadedContext() throws -> OpaquePointer {
        if let context {
            return context
        }
        var parameters = whisper_context_default_params()
        parameters.use_gpu = true
        parameters.flash_attn = true
        let loaded = configuration.modelURL.path.withCString { path in
            whisper_init_from_file_with_params(path, parameters)
        }
        guard let loaded else {
            throw TranscriptionError.modelLoadFailed
        }
        context = loaded
        return loaded
    }

    private func loadSamples(from audioURL: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: audioURL)
        let format = file.processingFormat
        guard format.sampleRate == 16_000,
              format.channelCount == 1,
              format.commonFormat == .pcmFormatFloat32,
              file.length > 0,
              file.length <= AVAudioFramePosition(UInt32.max),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(file.length)
              ) else {
            throw TranscriptionError.invalidAudio
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?.pointee,
              buffer.frameLength > 0 else {
            throw TranscriptionError.invalidAudio
        }
        return Array(
            UnsafeBufferPointer(
                start: channel,
                count: Int(buffer.frameLength)
            )
        )
    }
}
