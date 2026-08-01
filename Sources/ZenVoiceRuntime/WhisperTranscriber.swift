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
        case timedOut

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
            case .timedOut:
                return
                    "Transcription took too long and was stopped. "
                    + "Try a model suited to this language."
            }
        }
    }

    private let configuration: ZenVoiceConfiguration
    private let cleaner = TranscriptCleaner()
    private var context: OpaquePointer?
    private var hasWarmedUp = false
    private let parakeetEngine: ParakeetTranscriberEngine?
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
        parakeetEngine =
            VerifiedModelCatalog.model(
                filename: configuration.modelURL.lastPathComponent
            )?.runtime == .parakeetCoreML
                ? ParakeetTranscriberEngine(modelURL: configuration.modelURL)
                : nil
        whisper_log_set({ _, _, _ in }, nil)
    }

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    /// Pays the model's one-off setup cost before the user needs it.
    ///
    /// Loading is otherwise lazy — ``loadedContext()`` runs inside the *first*
    /// `transcribe`, which is to say after the user has already stopped
    /// talking. On top of the file read, that first call is also where Metal
    /// builds its pipelines, and
    /// ``WhisperDecoding/minimumDecodeTimeoutSeconds`` is set high partly to
    /// absorb it. None of that work depends on what was said, so none of it
    /// belongs on the critical path.
    ///
    /// The Parakeet runtime already does this in
    /// `ParakeetTranscriberEngine.init` — load, then a throwaway decode of
    /// silence, because CoreML's first prediction is expensive. This brings the
    /// whisper path to the same footing, using the same trick: a real decode of
    /// one second of silence, which exercises mel, encoder and decoder and then
    /// reports no speech.
    ///
    /// - Important: `context` is unguarded mutable state, so this must run on
    ///   the same serial queue as every decode. Callers use
    ///   `AppDelegate.transcriptionQueue`.
    public func warmUp() {
        guard !hasWarmedUp else {
            return
        }
        // Parakeet *starts* warming at construction but does not finish there:
        // the load runs in a detached task, so a decode arriving first simply
        // waits for it. Measured, that wait was the whole of an 8.41s first
        // decode against 0.03s for the second.
        if let parakeetEngine {
            parakeetEngine.warmUp()
            hasWarmedUp = true
            return
        }
        guard (try? loadedContext()) != nil else {
            // A model that cannot load now may load later — a download could
            // still be finishing. Leave the flag down so a retry is possible.
            return
        }
        hasWarmedUp = true
        _ = try? transcribe(samples: [Float](repeating: 0, count: 16_000))
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
        if let parakeetEngine {
            return try transcribeWithParakeet(
                samples: samples,
                activeProfile: activeProfile,
                initialPrompt: initialPrompt,
                engine: parakeetEngine
            )
        }
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
            : ProcessorTopology.decodeThreadCount
        // `audio_ctx` is deliberately left at the model default. See
        // ``WhisperDecoding`` for the measurement that settled it.
        if isReproducible {
            // Disables the sampled re-decode. With no increment there is no
            // second temperature to fall back to, so a hard segment stays on
            // the greedy or beam result rather than being resampled.
            parameters.temperature_inc = 0
        }
        // Timestamps must stay on. With them suppressed whisper returns the
        // whole recording as a single segment spanning the full window, so
        // there is nothing to derive paragraph structure from — the pauses
        // exist in the audio but never reach us. print_timestamps keeps them
        // out of the text.
        parameters.no_timestamps = false
        parameters.print_special = false
        parameters.print_progress = false
        parameters.print_realtime = false
        parameters.print_timestamps = false
        parameters.translate = activeProfile.shouldTranslateToEnglish

        // A deadline, because a stuck decode is otherwise indistinguishable
        // from a slow one and the app simply appears frozen. ggml calls this
        // before each computation; returning true unwinds the decode.
        //
        // The C callback cannot capture, so the deadline travels through
        // user_data as a raw pointer.
        let deadline = UnsafeMutablePointer<Double>.allocate(capacity: 1)
        defer { deadline.deallocate() }
        deadline.pointee = Date().timeIntervalSinceReferenceDate
            + WhisperDecoding.decodeDeadline(
                audioSeconds: Double(samples.count) / 16_000
            )
        parameters.abort_callback = { data in
            guard let data else { return false }
            return Date().timeIntervalSinceReferenceDate
                > data.assumingMemoryBound(to: Double.self).pointee
        }
        parameters.abort_callback_user_data = UnsafeMutableRawPointer(deadline)

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
            // An aborted decode and a genuine failure both return non-zero,
            // so the deadline is what distinguishes them.
            throw Date().timeIntervalSinceReferenceDate > deadline.pointee
                ? TranscriptionError.timedOut
                : TranscriptionError.runtimeFailed
        }

        var rawTranscript = ""
        var segments: [TranscriptSegment] = []
        let segmentCount = whisper_full_n_segments(context)
        for index in 0..<segmentCount {
            guard let text = whisper_full_get_segment_text(context, index) else {
                continue
            }
            let piece = String(cString: text)
            rawTranscript += piece
            // whisper reports segment times in centiseconds, measured
            // against the padded buffer it was given. Subtracting the lead-in
            // puts them back on the caller's own timeline, which is what the
            // silence detection is measured against — leaving the offset in
            // skews every boundary by half a second and pauses stop lining up
            // with the segments they belong to.
            let start =
                Double(whisper_full_get_segment_t0(context, index)) / 100
                - WhisperDecoding.leadInSilenceSeconds
            let end =
                Double(whisper_full_get_segment_t1(context, index)) / 100
                - WhisperDecoding.leadInSilenceSeconds
            segments.append(
                TranscriptSegment(
                    text: piece,
                    startSeconds: max(0, start),
                    endSeconds: max(0, end)
                )
            )
        }
        // Paragraph structure comes from the speaker's own pauses, measured
        // from the audio because whisper's segment bounds abut and contain no
        // silence. Cleaning runs per paragraph: TranscriptCleaner collapses
        // all whitespace, so cleaning the joined text would erase the breaks
        // it was just given.
        let structured = segments.isEmpty
            ? rawTranscript
            : SpokenStructure.text(
                from: segments,
                silences: SpokenStructure.silences(in: samples)
            )
        // A runaway loop is collapsed before anything else looks at the text.
        // Instant Refine would catch some of it, but refinement is a user
        // preference that can be switched off, and a transcript repeating
        // itself a hundred times is broken rather than untidy. The cut size
        // travels with the result: a large one means the decode failed and
        // the app should say so.
        var runawayWordsCut = 0
        let cleanedTranscript = structured
            .components(separatedBy: "\n\n")
            .map { paragraph -> String in
                let collapse =
                    TranscriptRepetition.collapsingRunawayReporting(paragraph)
                runawayWordsCut += collapse.wordsCut
                return cleaner.clean(collapse.text)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
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
                Date().timeIntervalSince(processingStartedAt),
            segments: segments,
            runawayWordsCut: runawayWordsCut
        )
    }

    /// The language Whisper hears, and how sure it is.
    ///
    /// Costs one encoder pass over the first window — the expensive half of a
    /// decode — so this is only worth running when its answer changes which
    /// model gets used.
    public func detectedLanguage(
        samples: [Float]
    ) throws -> (code: String, probability: Float) {
        guard !samples.isEmpty else {
            throw TranscriptionError.invalidAudio
        }
        if parakeetEngine != nil {
            return ("en", 1)
        }
        let context = try loadedContext()
        let padded = WhisperDecoding.withLeadInSilence(samples)
        let threads = ProcessorTopology.decodeThreadCount
        let melStatus = padded.withUnsafeBufferPointer { buffer in
            whisper_pcm_to_mel(
                context,
                buffer.baseAddress,
                Int32(buffer.count),
                threads
            )
        }
        guard melStatus == 0 else {
            throw TranscriptionError.runtimeFailed
        }
        var probabilities = [Float](
            repeating: 0,
            count: Int(whisper_lang_max_id()) + 1
        )
        let identifier = probabilities.withUnsafeMutableBufferPointer { buffer in
            whisper_lang_auto_detect(context, 0, threads, buffer.baseAddress)
        }
        guard identifier >= 0, let name = whisper_lang_str(identifier) else {
            throw TranscriptionError.runtimeFailed
        }
        return (String(cString: name), probabilities[Int(identifier)])
    }

    private func transcribeWithParakeet(
        samples: [Float],
        activeProfile: LanguageProfile,
        initialPrompt: String?,
        engine: ParakeetTranscriberEngine
    ) throws -> TranscriptionResult {
        guard activeProfile.isCompatible(with: .english) else {
            throw TranscriptionError.runtimeFailed
        }
        // Parakeet Unified has no decoder-prompt API. ZenVoice still applies
        // its local correction vocabulary after decoding.
        _ = initialPrompt
        let processingStartedAt = Date()
        let decoded: ParakeetDecodedResult
        do {
            decoded = try engine.transcribe(samples: samples)
        } catch {
            throw TranscriptionError.runtimeFailed
        }
        let structured = decoded.segments.isEmpty
            ? decoded.text
            : SpokenStructure.text(
                from: decoded.segments,
                silences: SpokenStructure.silences(in: samples)
            )
        var runawayWordsCut = 0
        let cleanedTranscript = structured
            .components(separatedBy: "\n\n")
            .map { paragraph -> String in
                let collapse =
                    TranscriptRepetition.collapsingRunawayReporting(paragraph)
                runawayWordsCut += collapse.wordsCut
                return cleaner.clean(collapse.text)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard !cleanedTranscript.isEmpty else {
            throw TranscriptionError.noSpeech
        }
        return TranscriptionResult(
            rawTranscript: decoded.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            finalTranscript: cleanedTranscript,
            correctionCount: 0,
            isPartial: false,
            modelID: configuration.modelID,
            processingDurationSeconds:
                Date().timeIntervalSince(processingStartedAt),
            segments: decoded.segments,
            runawayWordsCut: runawayWordsCut
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
