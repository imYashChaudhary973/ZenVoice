import Foundation
import ZenVoiceCore
import llama

public final class LocalTextRefiner: @unchecked Sendable {
    public enum RefinementError: LocalizedError {
        case modelLoadFailed
        case contextCreationFailed
        case promptTooLong
        case tokenizationFailed
        case decodeFailed
        case timedOut
        case emptyOutput

        public var errorDescription: String? {
            switch self {
            case .modelLoadFailed:
                "The selected local refinement model could not be loaded."
            case .contextCreationFailed:
                "ZenVoice could not create a local refinement context."
            case .promptTooLong:
                "This transcript is too long for the selected refinement model."
            case .tokenizationFailed:
                "The local refinement model could not read this transcript."
            case .decodeFailed:
                "The local refinement model stopped unexpectedly."
            case .timedOut:
                "Local refinement exceeded its time limit."
            case .emptyOutput:
                "The local refinement model returned no usable text."
            }
        }
    }

    private static let backendInitialized: Void = {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()

    /// Tokens per generation, and the context they share with the prompt.
    private static let contextSize: UInt32 = 2_048

    private let modelURL: URL
    private let lock = NSLock()
    private var model: OpaquePointer?
    private var vocab: OpaquePointer?
    /// Held open for the refiner's lifetime rather than rebuilt per call.
    ///
    /// Creating and freeing a context per dictation discarded the KV cache for
    /// the instruction block, which is identical every time — measured at
    /// roughly half a second of the user-visible path, spent recomputing a
    /// constant.
    private var context: OpaquePointer?
    /// The prefix currently resident in the KV cache, so a changed context
    /// string can be detected and re-prefilled rather than silently reused.
    private var cachedPrefixTokens: [llama_token] = []

    public init(modelURL: URL) {
        self.modelURL = modelURL
    }

    deinit {
        if let context {
            llama_free(context)
        }
        if let model {
            llama_model_free(model)
        }
    }

    /// Loads the model and prefills the instruction block without generating.
    ///
    /// Called at launch so the first dictation of a session does not pay the
    /// model load inside the path the user is waiting on.
    public func warmUp(context: String = "") throws {
        try lock.withLock {
            _ = Self.backendInitialized
            let (_, vocab) = try loadedModel()
            let llamaContext = try activeContext()
            try primePrefix(
                LocalRefinementPrompt.systemPrefix(context: context),
                context: llamaContext,
                vocab: vocab
            )
        }
    }

    public func refine(
        _ transcript: String,
        context: String = "",
        timeLimit: TimeInterval = 5,
        // A drop list is a handful of integers, not a restated transcript, so
        // the budget no longer has to scale with the dictation. 64 tokens
        // covers far more deletions than the guard's 40% ceiling permits.
        maximumOutputTokens: Int32 = 64
    ) throws -> String {
        try lock.withLock {
            _ = Self.backendInitialized
            let (_, vocab) = try loadedModel()
            let llamaContext = try activeContext()
            let prefixLength = try primePrefix(
                LocalRefinementPrompt.systemPrefix(context: context),
                context: llamaContext,
                vocab: vocab
            )
            return try generate(
                tail: LocalRefinementPrompt.tail(transcript: transcript),
                prefixLength: prefixLength,
                context: llamaContext,
                vocab: vocab,
                timeLimit: timeLimit,
                maximumOutputTokens: maximumOutputTokens
            )
        }
    }

    private func activeContext() throws -> OpaquePointer {
        if let context {
            return context
        }
        guard let model else {
            throw RefinementError.modelLoadFailed
        }
        let threads = Int32(
            max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        )
        var parameters = llama_context_default_params()
        parameters.n_ctx = Self.contextSize
        parameters.n_batch = Self.contextSize
        parameters.n_threads = threads
        parameters.n_threads_batch = threads
        parameters.no_perf = true
        guard let created = llama_init_from_model(model, parameters) else {
            throw RefinementError.contextCreationFailed
        }
        context = created
        cachedPrefixTokens = []
        return created
    }

    /// Ensures the instruction block is resident in the KV cache and returns
    /// its length in tokens.
    ///
    /// When the prefix is unchanged — the ordinary case — this decodes nothing
    /// and only trims whatever the previous generation left behind it.
    @discardableResult
    private func primePrefix(
        _ prefix: String,
        context: OpaquePointer,
        vocab: OpaquePointer
    ) throws -> Int {
        let prefixTokens = try tokenize(
            prefix,
            vocab: vocab,
            addSpecial: true
        )
        let memory = llama_get_memory(context)

        if prefixTokens == cachedPrefixTokens {
            // Drop the previous transcript and its generated reply, keeping
            // the instruction block resident.
            //
            // A partial removal is allowed to fail. If it does, the cache
            // still holds the last dictation and reusing it would splice two
            // transcripts together, so fall through to a full rebuild rather
            // than generating from corrupt state.
            if llama_memory_seq_rm(
                memory,
                0,
                Int32(prefixTokens.count),
                -1
            ) {
                return prefixTokens.count
            }
        }

        llama_memory_clear(memory, true)
        cachedPrefixTokens = []
        try decode(
            prefixTokens,
            startingAt: 0,
            context: context,
            wantsLogitsOnLast: false
        )
        cachedPrefixTokens = prefixTokens
        return prefixTokens.count
    }

    /// Feeds a run of tokens through the model in one batch.
    private func decode(
        _ tokens: [llama_token],
        startingAt position: Int,
        context: OpaquePointer,
        wantsLogitsOnLast: Bool
    ) throws {
        guard !tokens.isEmpty else { return }
        var batch = llama_batch_init(Int32(tokens.count), 0, 1)
        defer { llama_batch_free(batch) }
        batch.n_tokens = Int32(tokens.count)
        for (index, token) in tokens.enumerated() {
            batch.token[index] = token
            batch.pos[index] = Int32(position + index)
            batch.n_seq_id[index] = 1
            batch.seq_id[index]?[0] = 0
            batch.logits[index] = 0
        }
        if wantsLogitsOnLast {
            batch.logits[tokens.count - 1] = 1
        }
        guard llama_decode(context, batch) == 0 else {
            throw RefinementError.decodeFailed
        }
    }

    private func loadedModel() throws -> (OpaquePointer, OpaquePointer) {
        if let model, let vocab {
            return (model, vocab)
        }

        var parameters = llama_model_default_params()
        parameters.n_gpu_layers = 99
        parameters.check_tensors = true
        guard let loaded = llama_model_load_from_file(
            modelURL.path,
            parameters
        ),
        let loadedVocab = llama_model_get_vocab(loaded) else {
            throw RefinementError.modelLoadFailed
        }
        model = loaded
        vocab = loadedVocab
        return (loaded, loadedVocab)
    }

    private func generate(
        tail: String,
        prefixLength: Int,
        context: OpaquePointer,
        vocab: OpaquePointer,
        timeLimit: TimeInterval,
        maximumOutputTokens: Int32
    ) throws -> String {
        // The prefix carries the only BOS, so the tail must not add another.
        let tailTokens = try tokenize(
            tail,
            vocab: vocab,
            addSpecial: false
        )
        let promptLength = prefixLength + tailTokens.count
        guard promptLength
                + Int(maximumOutputTokens) < Int(Self.contextSize) else {
            throw RefinementError.promptTooLong
        }

        var samplerParameters =
            llama_sampler_chain_default_params()
        samplerParameters.no_perf = true
        guard let sampler = llama_sampler_chain_init(
            samplerParameters
        ) else {
            throw RefinementError.contextCreationFailed
        }
        guard let grammarSampler = llama_sampler_init_grammar(
            vocab,
            LocalRefinementPrompt.dropGrammar,
            "root"
        ) else {
            throw RefinementError.contextCreationFailed
        }
        llama_sampler_chain_add(sampler, grammarSampler)
        llama_sampler_chain_add(
            sampler,
            llama_sampler_init_greedy()
        )
        defer {
            llama_sampler_free(sampler)
        }

        // Only the transcript is decoded here. The instruction block is
        // already resident in the KV cache from primePrefix.
        let startedAt = Date()
        try decode(
            tailTokens,
            startingAt: prefixLength,
            context: context,
            wantsLogitsOnLast: true
        )
        let prefillSeconds = Date().timeIntervalSince(startedAt)
        guard prefillSeconds <= timeLimit else {
            throw RefinementError.timedOut
        }

        var batch = llama_batch_init(1, 0, 1)
        defer {
            llama_batch_free(batch)
        }

        var output = ""
        var utf8Buffer: [CChar] = []
        var generatedCount: Int32 = 0
        while generatedCount < maximumOutputTokens {
            guard Date().timeIntervalSince(startedAt) <= timeLimit else {
                throw RefinementError.timedOut
            }
            let token = llama_sampler_sample(
                sampler,
                context,
                -1
            )
            if llama_vocab_is_eog(vocab, token) {
                break
            }
            if let piece = tokenPiece(
                token,
                vocab: vocab,
                utf8Buffer: &utf8Buffer
            ) {
                output += piece
            }
            if output.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).last == "}",
            let data = output.data(using: .utf8),
            (try? JSONSerialization.jsonObject(with: data)) != nil {
                break
            }

            batch.n_tokens = 1
            batch.token[0] = token
            batch.pos[0] =
                Int32(promptLength) + generatedCount
            batch.n_seq_id[0] = 1
            batch.seq_id[0]?[0] = 0
            batch.logits[0] = 1
            guard llama_decode(context, batch) == 0 else {
                throw RefinementError.decodeFailed
            }
            generatedCount += 1
        }

        if ProcessInfo.processInfo.environment["ZENVOICE_REFINE_TRACE"] == "1" {
            FileHandle.standardError.write(
                Data(
                    String(
                        format:
                            "  trace: prefix %d tail %d generated %d "
                            + "prefill %.0fms total %.0fms\n",
                        prefixLength,
                        tailTokens.count,
                        Int(generatedCount),
                        prefillSeconds * 1_000,
                        Date().timeIntervalSince(startedAt) * 1_000
                    ).utf8
                )
            )
        }

        let result = output.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !result.isEmpty else {
            throw RefinementError.emptyOutput
        }
        return result
    }

    private func tokenize(
        _ text: String,
        vocab: OpaquePointer,
        addSpecial: Bool
    ) throws -> [llama_token] {
        let byteCount = text.utf8.count
        var tokens = [llama_token](
            repeating: 0,
            count: byteCount + 8
        )
        let count = llama_tokenize(
            vocab,
            text,
            Int32(byteCount),
            &tokens,
            Int32(tokens.count),
            addSpecial,
            true
        )
        guard count > 0 else {
            throw RefinementError.tokenizationFailed
        }
        tokens.removeLast(tokens.count - Int(count))
        return tokens
    }

    private func tokenPiece(
        _ token: llama_token,
        vocab: OpaquePointer,
        utf8Buffer: inout [CChar]
    ) -> String? {
        var bytes = [CChar](repeating: 0, count: 16)
        var count = llama_token_to_piece(
            vocab,
            token,
            &bytes,
            Int32(bytes.count),
            0,
            false
        )
        if count < 0 {
            bytes = [CChar](
                repeating: 0,
                count: Int(-count)
            )
            count = llama_token_to_piece(
                vocab,
                token,
                &bytes,
                Int32(bytes.count),
                0,
                false
            )
        }
        guard count > 0 else {
            return nil
        }
        bytes.removeLast(bytes.count - Int(count))
        utf8Buffer.append(contentsOf: bytes)
        let data = Data(utf8Buffer.map { UInt8(bitPattern: $0) })
        guard let value = String(data: data, encoding: .utf8) else {
            if utf8Buffer.count >= 4 {
                utf8Buffer.removeAll()
            }
            return nil
        }
        utf8Buffer.removeAll()
        return value
    }
}
