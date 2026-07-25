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
    /// Resolved once — it reads the model file when the model is not in the
    /// catalogue, and transcription happens far too often to repeat that.
    private let usesBeamSearch: Bool

    public var modelID: String {
        configuration.modelID
    }

    public var language: String {
        configuration.language
    }

    public var languageProfile: LanguageProfile {
        configuration.languageProfile
    }

    public var languageCapability: ModelLanguageCapability {
        configuration.modelLanguageCapability
    }

    /// Makes decoding repeatable, for measurement rather than for dictation.
    ///
    /// Whisper's default temperature fallback re-decodes a segment with
    /// sampling when it trips the entropy or logprob thresholds, and the
    /// thread count follows the machine. Both are the right defaults for a
    /// user — fallback rescues genuinely hard audio — and both make the
    /// output differ run to run, which was measured at more than a point of
    /// word error rate between identical harness runs.
    ///
    /// A measurement instrument that moves under its own subject cannot
    /// support fine-grained conclusions, so the harness pins them. Nothing in
    /// the app path sets this.
    private let isReproducible: Bool

    public init(
        configuration: ZenVoiceConfiguration,
        isReproducible: Bool = false
    ) {
        self.configuration = configuration
        self.isReproducible = isReproducible
        usesBeamSearch = configuration.usesBeamSearchDecoding
        whisper_log_set({ _, _, _ in }, nil)
    }

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    public func transcribe(
        audioURL: URL,
        languageProfile: LanguageProfile? = nil,
        initialPrompt: String? = nil
    ) throws -> TranscriptionResult {
        let samples = try loadSamples(from: audioURL)
        return try transcribe(
            samples: samples,
            languageProfile: languageProfile,
            initialPrompt: initialPrompt
        )
    }

    public func transcribe(
        samples: [Float],
        languageProfile: LanguageProfile? = nil,
        initialPrompt: String? = nil
    ) throws -> TranscriptionResult {
        guard !samples.isEmpty else {
            throw TranscriptionError.invalidAudio
        }
        let activeProfile =
            languageProfile ?? configuration.languageProfile
        let contextPrompt = NextDictationContext.sanitized(
            initialPrompt ?? ""
        )
        let processingStartedAt = Date()
        // Push-to-talk starts the buffer on the first syllable; without a
        // moment of lead-in some models drop the opening word. See
        // ``WhisperDecoding/leadInSilenceSeconds``.
        let paddedSamples = WhisperDecoding.withLeadInSilence(samples)
        let context = try loadedContext()
        var parameters = whisper_full_default_params(
            usesBeamSearch
                ? WHISPER_SAMPLING_BEAM_SEARCH
                : WHISPER_SAMPLING_GREEDY
        )
        if usesBeamSearch {
            parameters.beam_search.beam_size = WhisperDecoding.beamSize
        }
        parameters.n_threads = isReproducible
            ? 4
            : Int32(
                max(1, min(8, ProcessInfo.processInfo.activeProcessorCount))
            )
        if isReproducible {
            // Disables the sampled re-decode. With no increment there is no
            // second temperature to fall back to, so a hard segment stays on
            // the greedy or beam result rather than being resampled.
            parameters.temperature_inc = 0
        }
        parameters.no_timestamps = true
        parameters.print_special = false
        parameters.print_progress = false
        parameters.print_realtime = false
        parameters.print_timestamps = false
        parameters.translate = activeProfile.shouldTranslateToEnglish

        let status = activeProfile.whisperLanguageArgument(
            for: languageCapability
        ).withCString { language in
            parameters.language = language
            return contextPrompt.withCString { prompt in
                if !contextPrompt.isEmpty {
                    parameters.initial_prompt = prompt
                }
                return paddedSamples.withUnsafeBufferPointer { buffer in
                    whisper_full(
                        context,
                        parameters,
                        buffer.baseAddress,
                        Int32(buffer.count)
                    )
                }
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
        // A Hinglish-native model has already written Latin script, and
        // romanizing it again would only damage text that is correct.
        let needsTransliteration = activeProfile.shouldTransliterateToLatin
            && !languageCapability.emitsLatinScriptNatively
        let finalTranscript = needsTransliteration
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
