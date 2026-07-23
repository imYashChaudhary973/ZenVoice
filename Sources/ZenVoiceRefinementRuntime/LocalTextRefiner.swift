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

    private let modelURL: URL
    private let lock = NSLock()
    private var model: OpaquePointer?
    private var vocab: OpaquePointer?

    public init(modelURL: URL) {
        self.modelURL = modelURL
    }

    deinit {
        if let model {
            llama_model_free(model)
        }
    }

    public func refine(
        _ transcript: String,
        context: String = "",
        timeLimit: TimeInterval = 5,
        maximumOutputTokens: Int32 = 192
    ) throws -> String {
        try lock.withLock {
            _ = Self.backendInitialized
            let (model, vocab) = try loadedModel()
            return try generate(
                prompt: LocalRefinementPrompt.make(
                    transcript: transcript,
                    context: context
                ),
                model: model,
                vocab: vocab,
                timeLimit: timeLimit,
                maximumOutputTokens: maximumOutputTokens
            )
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
        prompt: String,
        model: OpaquePointer,
        vocab: OpaquePointer,
        timeLimit: TimeInterval,
        maximumOutputTokens: Int32
    ) throws -> String {
        let promptTokens = try tokenize(prompt, vocab: vocab)
        let contextSize: UInt32 = 2_048
        guard promptTokens.count
                + Int(maximumOutputTokens) < Int(contextSize) else {
            throw RefinementError.promptTooLong
        }

        let threads = Int32(
            max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        )
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = contextSize
        contextParameters.n_batch = contextSize
        contextParameters.n_threads = threads
        contextParameters.n_threads_batch = threads
        contextParameters.no_perf = true
        guard let context = llama_init_from_model(
            model,
            contextParameters
        ) else {
            throw RefinementError.contextCreationFailed
        }
        defer {
            llama_free(context)
        }

        var samplerParameters =
            llama_sampler_chain_default_params()
        samplerParameters.no_perf = true
        guard let sampler = llama_sampler_chain_init(
            samplerParameters
        ) else {
            throw RefinementError.contextCreationFailed
        }
        let grammar = #"""
        root ::= "{" ws "\"text\"" ws ":" ws string "}" ws
        string ::= "\"" ([^"\\\x7F\x00-\x1F] | "\\" (["\\bfnrt] | "u" [0-9a-fA-F]{4}))* "\"" ws
        ws ::= | " " | "\n" [ \t]{0,20}
        """#
        guard let grammarSampler = llama_sampler_init_grammar(
            vocab,
            grammar,
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

        var batch = llama_batch_init(
            Int32(promptTokens.count),
            0,
            1
        )
        defer {
            llama_batch_free(batch)
        }
        batch.n_tokens = Int32(promptTokens.count)
        for (index, token) in promptTokens.enumerated() {
            batch.token[index] = token
            batch.pos[index] = Int32(index)
            batch.n_seq_id[index] = 1
            batch.seq_id[index]?[0] = 0
            batch.logits[index] = 0
        }
        batch.logits[promptTokens.count - 1] = 1

        let startedAt = Date()
        guard llama_decode(context, batch) == 0 else {
            throw RefinementError.decodeFailed
        }
        guard Date().timeIntervalSince(startedAt) <= timeLimit else {
            throw RefinementError.timedOut
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
                Int32(promptTokens.count) + generatedCount
            batch.n_seq_id[0] = 1
            batch.seq_id[0]?[0] = 0
            batch.logits[0] = 1
            guard llama_decode(context, batch) == 0 else {
                throw RefinementError.decodeFailed
            }
            generatedCount += 1
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
        vocab: OpaquePointer
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
            true,
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
